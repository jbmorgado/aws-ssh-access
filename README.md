# AWS HPC Access Configuration Script

## Prerequisites

### All Systems
- You need the SSH key pair at `~/.ssh/id_ed25519`:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
  ```

### macOS Requirements
- Homebrew installed. If you don't have homebrew installed on your system yet, check the [webpage](https://brew.sh/) for the Homebrew project.

### Linux Requirements
- Supported distributions: Ubuntu/Debian/Fedora
- sudo privileges

## Installation
```bash
curl -sSL https://raw.githubusercontent.com/jbmorgado/aws-ssh-access/refs/heads/master/installer.sh | bash -s -- <iam_user> <mfa_arn> <hpc_username>
```

**Parameters**:
1. `iam_user` - Your AWS IAM username (e.g. `iam-john.smith`). This will be provided to you by the SKAO IT. i.e.: iam-john.smith
2. `mfa_arn` - MFA device ARN (e.g. `arn:aws:iam::123456789012:mfa/user`). You will set this up when you loging into the AWS Web Console. i.e.: arn:aws:iam::123456789012:mfa/john.smith
3. `hpc_username` - HPC cluster login name. This will be the 1st letter of your 1st name followed by your last name: i.e.: jsmith

**Example**:
```bash
curl -sSL https://raw.githubusercontent.com/jbmorgado/aws-ssh-access/refs/heads/master/installer.sh | bash -s -- iam-john.smith arn:aws:iam::123456789012:mfa/john.smith jsmith
```

## Features
- Creates AWS CLI profiles with MFA authentication
- Configures SSH access via AWS Session Manager
- Installs required tools:
  - AWS CLI v2, AWS Vault, Session Manager Plugin, HashiCorp Vault

## Security
Always inspect scripts before running:
```bash
curl -sSL https://raw.githubusercontent.com/jbmorgado/aws-ssh-access/refs/heads/master/installer.sh
```

## Troubleshooting

### Missing SSH Key
You should have generated one to make request access, but it needs to be in the proper location at `~/.ssh/id_ed25519`.

Otherwise, you need to change the `dp-hpc-headnode` entry on `~/.ssh/config` to point at the correct file.

### Homebrew Missing (macOS)
Install it with: 
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### PATH Configuration
Make sure `~/.local/bin` is in your `$PATH`.
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Fish Shell Warning
Add to `~/.config/fish/config.fish`:
```fish
set -gx AWS_VAULT_BACKEND file
```

---

**Repository**: https://github.com/jbmorgado/aws-ssh-access  
**Maintainer**: [J. Bruno Morgado]