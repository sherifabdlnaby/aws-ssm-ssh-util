#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

# This is a modifed script of a open-source helper script: https://github.com/elpy1/ssh-over-ssm

# ----------------------------------------  GET INSTANCE ID IF GIVEN INPUT IS NOT ID ----------------------------------------

instance=${1}

# If not instance ID, try if it is a name, or IP, or ID
if [[ ! $instance =~ ^i-([0-9a-f]{8,})$ ]]
then
  instance=$(echo $instance | awk '{split($0,a,"-"); print a[2]}')
  # Try by top instance name
  if instance_id=$(aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --filters Name=instance-state-name,Values=running Name=tag:Name,Values="*$instance*" --output json | jq -r '.[0]');
   then
   instance=$instance_id
  # Try by private DNS Name
  elif instance_id=$(aws ec2 describe-instances --filters Name=private-dns-name,Values=${instance} --query 'Reservations[].Instances[].InstanceId' --output json | jq -r '.[0]');
   then
   instance=$instance_id
  # Try by Private IP
  elif instance_id=$(aws ec2 describe-instances --filters Name=network-interface.addresses.private-ip-address,Values=${instance} --query 'Reservations[].Instances[].InstanceId' --output json | jq -r '.[0]');
   then
   instance=$instance_id
    # Try by Public IP
  elif instance_id=$(aws ec2 describe-instances --filters Name=network-interface.addresses.public-ip-address,Values=${instance} --query 'Reservations[].Instances[].InstanceId' --output json | jq -r '.[0]');
   then
   instance=$instance_id
  fi
fi

# Exit If we couldn't find ID
if [ "$instance" = "null" ]; then
  echo "❌ Invalid Instance Identifier, couldn't match it to InstanceID, Name, Public/Private DNS Or IP." >&2; echo "(Do you have permission to access these instances?)" >&2 && exit 1;
fi

# ----------------------------------------  ADD PUBLIC KEY TO REMOTE INSTANCE ----------------------------------------

# Check If SSM key is on client, create it if it doesn't exist.
if [ ! -f ~/.ssh/ssm-ssh-key.pub ] || [ ! -f ~/.ssh/ssm-ssh-key ]
then    
  ssh-keygen -t ed25519 -N '' -f ~/.ssh/ssm-ssh-key -C ssm-ssh-session-$USER <<< yes
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


# Send The Command to the Remote Instance to run instantly (and asyncrhonusly)
# - The Command puts the key and deletes it after 15 seconds, we only need it to be present only when we run the below ssm command.
aws ssm send-command \
  --instance-ids "$instance" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="${ssm_cmd}" \
  --comment "Adding Temp Access Key for USER:$USER" || (echo "Invalid Instance ID: $instance. Make sure you have permission to instance." >&2 && exit 1);

# Sleep for some time to avoid if the above script didn't run instantly (Although the SSM Send-Command returns when the script HAS Started)
sleep 1

# Start SSH Session over SSM
# - Session Manager is going to proxy our SSH Client traffic(that is running this script) to the SSH on the host.
# - This Script does the inital setup and then hands sending ssh traffic to the ssh client that invoked it via `ssh` command.
#   <Client SSH> ---ssh-traffic--> <This Script> ---ssh-traffic--> <SSM> ---ssh-traffic--> <Remote Host SSH>
# - SSM let us reach the Remote Instances even if they're in a private subnet.
aws ssm start-session --document-name AWS-StartSSHSession --target "$instance"