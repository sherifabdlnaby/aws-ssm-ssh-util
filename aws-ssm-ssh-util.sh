#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

# This is a modifed script of a open-source helper script: https://github.com/elpy1/ssh-over-ssm

# ----------------------------------------  GET INSTANCE ID IF GIVEN INPUT IS NOT ID ----------------------------------------

export instance=${1}
export instance_name=$instance
user=$(whoami)


# If not instance ID, try if it is a name, or IP, or ID
if [[ ! $instance =~ ^i-([0-9a-f]{8,})$ ]]
then
  instance=$(echo "$instance" | awk '{split($0,a,"-"); print a[2]}')

  printf " 🔍 Looking up $instance ... " >&2;

  # Try by top instance name
  if instance_query=$(aws ec2 describe-instances --query 'Reservations[].Instances[].{Instance:InstanceId, Name:Tags[?Key==`Name`]|[0].Value}' --filters Name=instance-state-name,Values=running Name=tag:Name,Values="*$instance*" --output json | jq -e '.[0]');
    then
     instance=$(echo "$instance_query" | jq -r '.Instance')
     instance_name=$(echo "$instance_query" | jq -r '.Name')
  # Try by private DNS Name
  elif instance_query=$(aws ec2 describe-instances --filters Name=private-dns-name,Values=${instance} --query 'Reservations[].Instances[].{Instance:InstanceId, Name:Tags[?Key==`Name`]|[0].Value}' --output json | jq -e '.[0]');
    then
     instance=$(echo "$instance_query" | jq -r '.Instance')
     instance_name=$(echo "$instance_query" | jq -r '.Name')
  # Try if IP
  elif [[ "$instance" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]];
    then
    # Try by Private IP
    if instance_query=$(aws ec2 describe-instances --filters Name=network-interface.addresses.private-ip-address,Values=$instance --query 'Reservations[].Instances[].{Instance:InstanceId, Name:Tags[?Key==`Name`]|[0].Value}' --output json | jq -e '.[0]');
     then
       instance=$(echo "$instance_query" | jq -r '.Instance')
       instance_name=$(echo "$instance_query" | jq -r '.Name')
    # Try by Public IP
    elif instance_query=$(aws ec2 describe-instances --filters Name=ip-address,Values=$instance --query 'Reservations[].Instances[].{Instance:InstanceId, Name:Tags[?Key==`Name`]|[0].Value}' --output json | jq -e '.[0]' );
     then
       instance=$(echo "$instance_query" | jq -r '.Instance')
       instance_name=$(echo "$instance_query" | jq -r '.Name')
    else
      echo "❌ Couldn't Match Public/Private IP to an instance." >&2; echo "   (Do you have permission to view this instance?)" >&2 && exit 1;
    fi
  else
     echo "❌ Invalid Instance Identifier, couldn't match it to a Name, Public/Private DNS, Or an IP." >&2; echo "   (Do you have permission to view this instance?)" >&2 && exit 1;
  fi
  echo "✔️  Found '$instance' | '$instance_name'" >&2;
else
  # Validate ID and get Instance Name
  if instance_query=$(aws ec2 describe-instances --query 'Reservations[].Instances[].{Instance:InstanceId, Name:Tags[?Key==`Name`]|[0].Value}' --filters "Name=instance-id,Values=$instance" --output json) ;
   then
     instance=$(echo "$instance_query" | jq -r '.[0].Instance')
     instance_name=$(echo "$instance_query" | jq -r '.[0].Name')
   else
    echo "❌ Instance ID is either wrong, or you don't have permissions to access it." >&2;
    exit 1
  fi
fi

# Just in-case name wasn't set (so won't confuse the user with the 'null')
if [ "$instance_name" = "null" ]; then
  instance_name=$instance
fi


# ----------------------------------------  ADD PUBLIC KEY TO REMOTE INSTANCE ----------------------------------------

# Check If SSM key is on client, create it if it doesn't exist.
if [ ! -f ~/.ssh/ssm-ssh-key.pub ] || [ ! -f ~/.ssh/ssm-ssh-key ]
then
  ssh-keygen -t ed25519 -N '' -f ~/.ssh/ssm-ssh-key -C ssm-ssh-session-"${user}" <<< yes
  echo "🔐 Created Keypair to use with SSH using SSM." >&2;
fi

# Public Key Value that we're going to set at the remote instance
ssh_pubkey="$(< ~/.ssh/ssm-ssh-key.pub)"

# The Command that is going to run at the remote instance to ad the key.
# - Notice that the expression with escaped \${var} is going to be expaned AT the remote instance.
ssm_cmd=$(cat <<EOF
  "
  # Get User Home Directory (cant use ~)
  user=\$(getent passwd ${2}) && home=\$(echo \$user |cut -d: -f6)
  # Create Folder for the user if it doesn't exist
  install -d -m700 -o${2} \${home}/.ssh
  # Add Public Key to Authorized Keys and Wait 15 Seconds
  echo '${ssh_pubkey}' >> \${home}/.ssh/authorized_keys && sleep 15;
  # Delete the Key
  sed -i '0,\,${ssh_pubkey},{//d;}' \${home}/.ssh/authorized_keys
  "
EOF
)

echo " 🔐 Adding ephemeral public key to remote instance..." >&2;

# Send The Command to the Remote Instance to run instantly (and asyncrhonusly)
# - The Command puts the key and deletes it after 15 seconds, we only need it to be present only when we run the below ssm command.
aws ssm send-command \
  --instance-ids "$instance" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="${ssm_cmd}" \
  --comment "Adding Temp Access Key for USER:${user}" || (echo -e "❌ Invalid Instance ID: $instance. Make sure you have permission to instance." >&2 && exit 1);


printf " ✅ Added." >&2;


# Sleep for some time to avoid if the above script didn't run instantly (Although the SSM Send-Command returns when the script HAS Started)
sleep 1


echo " 🏃 Connecting to instance '$instance_name'... " >&2;

# Start SSH Session over SSM
# - Session Manager is going to proxy our SSH Client traffic(that is running this script) to the SSH on the host.
# - This Script does the inital setup and then hands sending ssh traffic to the ssh client that invoked it via `ssh` command.
#   <Client SSH> ---ssh-traffic--> <This Script> ---ssh-traffic--> <SSM> ---ssh-traffic--> <Remote Host SSH>
# - SSM let us reach the Remote Instances even if they're in a private subnet.
aws ssm start-session --document-name AWS-StartSSHSession --target "$instance"