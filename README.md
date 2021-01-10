
# ssh-over-ssm
Configure SSH and use AWS SSM to connect to instances. Consider git-managing your configs for quick setup and keeping users up-to-date and in sync.   
    

# Setup

```shell
curl -o- https://raw.githubusercontent.com/sherifabdlnaby/aws-ssm-ssh-util/master/setup.sh | bash
```

## Info and requirements
Recently I was required to administer AWS instances via Session Manager. After downloading the required plugin and initiating a SSM session locally using `aws ssm start-session` I found myself in a situation where I couldn't easily copy a file from my machine to the server (e.g. SCP, sftp, rsync etc). After some reading of AWS documentation I found it's possible to connect via SSH over SSM, solving this issue. You also get all the other benefits and functionality of SSH e.g. encryption, proxy jumping, port forwarding, socks etc.

At first I really wasn't too keen on SSM but now I'm an advocate! Some cool features:

- You can connect to your private instances inside your VPC without jumping through a public-facing bastion or instance
- You don't need to store any SSH keys locally or on the server.
- Users only require necessary IAM permissions and ability to reach their regional SSM endpoint (via HTTPS).
- SSM 'Documents' available to restrict users to specific tasks e.g. `AWS-PasswordReset` and` AWS-StartPortForwardingSession`.
- Due to the way SSM works it's unlikely to find yourself blocked by network-level security, making it a great choice if you need to get out to the internet from inside a restrictive network :p

### Requirements
- Instances must have access to ssm.{region}.amazonaws.com
- IAM instance profile allowing SSM access must be attached to EC2 instance
- SSM agent must be installed on EC2 instance
- AWS cli requires you install `session-manager-plugin` locally
- AWS_PROFILE enviroment variable set.

Existing instances with SSM agent already installed may require agent updates.

## How it works
You configure each of your instances in your SSH config and specify `ssh-ssm.sh` to be executed as a `ProxyCommand` with your `AWS_PROFILE` environment variable set.
If your key is available via `ssh-agent` it will be used by the script, otherwise a temporary key will be created, used and destroyed on termination of the script. The public key is copied across to the instance using `aws ssm send-command` and then the SSH session is initiated through SSM using `aws ssm start-session` (with document `AWS-StartSSHSession`) after which the SSH connection is made. The public key copied to the server is removed after 15 seconds and provides enough time for SSH authentication.
