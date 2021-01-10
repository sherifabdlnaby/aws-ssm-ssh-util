#!/usr/bin/env sh
set -o nounset -o pipefail -o errexit

# Download Script
curl -o- -s https://raw.githubusercontent.com/sherifabdlnaby/aws-ssm-ssh-util/master/aws-ssm-ssh-util.sh >> ~/.ssh/aws-ssm-ssh-util
chmod +x ~/.ssh/aws-ssm-ssh-util
echo "✅ Added aws-ssm-ssh-util script to SSH folder"

# Add SSH Config
curl -o- -s https://raw.githubusercontent.com/sherifabdlnaby/aws-ssm-ssh-util/master/ssh-config >> ~/.ssh/config
echo "✅ Added aws-ssm-ssh-util config to SSH Config"