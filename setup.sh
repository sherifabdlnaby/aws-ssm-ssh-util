#!/usr/bin/env sh
set -o nounset -o pipefail -o errexit

# Download Script
curl -o- -s https://raw.githubusercontent.com/sherifabdlnaby/aws-ssm-ssh-util/master/aws-ssm-ssh-util.sh > ~/.ssh/aws-ssm-ssh-util
chmod +x ~/.ssh/aws-ssm-ssh-util
echo "✅  Added aws-ssm-ssh-util script to SSH folder"

# Add SSH Config
curl -o- -s https://raw.githubusercontent.com/sherifabdlnaby/aws-ssm-ssh-util/master/ssh-config >> ~/.ssh/config
echo "✅  Added aws-ssm-ssh-util config to SSH Config"

echo "
To Use:
  Requirements For Instances:
      - 📝 Instances must have access to ssm.{region}.amazonaws.com
      - 📝 IAM instance profile allowing SSM access must be attached to EC2 instance
      - 📝 SSM agent must be installed on EC2 instance
  Requirements For Client:
      - 📝 AWS cli requires you install \`session-manager-plugin\` locally
      - 📝 AWS_PROFILE enviroment variable set.

Usage:
  1. Using InstanceID     ==>     ssh user@i-123xxx42x31x2xx
  2. Using Name(fuzzy)    ==>     ssh user@i-<search query> (will pick first result)
  3. Using DNS            ==>     ssh user@i-<Private/Public DNS Record>
  4. Using IP             ==>     ssh user@i-<IP>
"