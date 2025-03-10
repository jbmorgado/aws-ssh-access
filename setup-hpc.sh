#!/usr/bin/env bash
set -euo pipefail

# Relaunch with bash if not already running in bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
    exit $?
fi

# Check for required arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <profile_name> <mfa_identifier>"
    echo "Example: curl -sSL https://example.com/installer.sh | bash -s -- my_profile my_mfa"
    exit 1
fi

PROFILE_NAME="$1"
MFA_IDENTIFIER="$2"

# -------- Configuration ----------
INSTALLER_URL="https://raw.githubusercontent.com/jbmorgado/aws-ssh-access"
LOCAL_BIN_DIR="$HOME/.local/bin"

LINUX_EXECUTABLES=(
    "https://github.com/99designs/aws-vault/releases/download/v7.2.0/aws-vault-linux-amd64|aws-vault"
)

MACOS_BREW_PACKAGES=(
    "hashicorp/tap/vault"
    "awscli"
)

MACOS_BREW_CASKS=(
    "aws-vault"
    "session-manager-plugin"
)

BREW_TAPS=(
    "hashicorp/tap"
)

ENV_VARS=(
    "PROFILE_NAME=$PROFILE_NAME"
    "MFA_IDENTIFIER=$MFA_IDENTIFIER"
    "PATH=/custom/path:\$PATH"
)
# ----------------------------------

detect_os() {
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$OS" in
        linux*)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_ID="$ID"
            else
                echo "Unsupported Linux distribution"
                exit 1
            fi
            ;;
        darwin*) OS="macos" ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

setup_aws_config() {
    local aws_dir="$HOME/.aws"
    local config_file="$aws_dir/config"
    
    mkdir -p "$aws_dir"
    
    if ! grep -q "\[profile $PROFILE_NAME\]" "$config_file"; then
        cat >> "$config_file" <<EOF
[profile $PROFILE_NAME]
region = eu-west-2
mfa_serial = $MFA_IDENTIFIER
EOF
    fi

    if ! grep -q "\[profile dp-hpc\]" "$config_file"; then
        cat >> "$config_file" <<EOF

[profile dp-hpc]
source_profile = $PROFILE_NAME
role_arn = "arn:aws:iam::533267315508:role/SKAO-DP-HPC-user"
region = eu-west-2
mfa_serial = $MFA_IDENTIFIER
EOF
    fi

    echo "AWS configuration created/updated at $config_file"
}

setup_ssh_config() {
    local ssh_dir="$HOME/.ssh"
    local config_file="$ssh_dir/config"
    local identity_file="$ssh_dir/id_ed25519"
    local script_path="$LOCAL_BIN_DIR/ssh-aws-ssm.sh"
    
    mkdir -p "$ssh_dir"
    touch "$config_file"
    
    if ! grep -q "Host dp-hpc-headnode" "$config_file"; then
        cat >> "$config_file" <<EOF

Host dp-hpc-headnode
    Hostname i-03bbc056f0dec808b
    User $(whoami)
    ProxyCommand $script_path %h %p
    IdentityFile $identity_file
    ServerAliveInterval 60
EOF
        echo "SSH configuration updated at $config_file"
    else
        echo "SSH configuration already exists, skipping update"
    fi
}

install_ssh_script() {
    local script_path="$LOCAL_BIN_DIR/ssh-aws-ssm.sh"
    
    mkdir -p "$LOCAL_BIN_DIR"
    
    # Derive SSH script URL from installer URL
    local ssh_script_url="${INSTALLER_URL}/refs/heads/master/ssh-aws-ssm.sh"
    
    echo "Downloading SSH helper script from $ssh_script_url..."
    curl -fsSL -o "$script_path" "$ssh_script_url" || {
        echo "ERROR: Failed to download ssh-aws-ssm.sh"
        return 1
    }
    
    chmod +x "$script_path"
    echo "Installed ssh-aws-ssm.sh to $LOCAL_BIN_DIR"
    
    # Check if LOCAL_BIN_DIR is in PATH
    if [[ ":$PATH:" != *":$LOCAL_BIN_DIR:"* ]]; then
        echo "WARNING: $LOCAL_BIN_DIR is not in your PATH. Add the following to your shell configuration:"
        echo "export PATH=\"$LOCAL_BIN_DIR:\$PATH\""
    fi
}

setup_linux() {
    echo "Setting up Linux ($OS_ID)..."
    
    # Install system dependencies
    case "$OS_ID" in
        debian|ubuntu|pop)
            sudo apt-get update
            sudo apt-get install -y curl wget
            ;;
        fedora|centos|rhel)
            sudo dnf install -y curl wget
            ;;
    esac
    
    # Install custom executables
    for entry in "${LINUX_EXECUTABLES[@]}"; do
        URL="${entry%%|*}"
        NAME="${entry##*|}"
        echo "Installing $NAME..."
        curl -fsSL "$URL" | sudo tee "/usr/local/bin/$NAME" >/dev/null
        sudo chmod +x "/usr/local/bin/$NAME"
    done
}

setup_macos() {
    echo "Setting up macOS..."
    
    # Install Homebrew if not exists
    if ! command -v brew &> /dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Add taps
    for tap in "${BREW_TAPS[@]}"; do
        brew tap "$tap"
    done
    
    # Install packages
    for pkg in "${MACOS_BREW_PACKAGES[@]}"; do
        brew install "$pkg"
    done
    
    # Install casks
    for cask in "${MACOS_BREW_CASKS[@]}"; do
        brew install --cask "$cask"
    done
}

set_environment() {
    echo "Setting environment variables in ~/.profile..."
    local profile_file="$HOME/.profile"
    
    # Create profile if it doesn't exist
    touch "$profile_file"
    
    # Add environment variables
    for var in "${ENV_VARS[@]}"; do
        if ! grep -qF "export $var" "$profile_file"; then
            echo "export $var" >> "$profile_file"
        fi
    done
    
    # Linux-specific environment variable
    if [ "$OS" = "linux" ]; then
        if ! grep -qF "export AWS_VAULT_BACKEND=file" "$profile_file"; then
            echo "export AWS_VAULT_BACKEND=file" >> "$profile_file"
        fi
    fi
    
    # Apply to current session
    source "$profile_file"
}

main() {
    detect_os
    setup_aws_config
    install_ssh_script
    setup_ssh_config
    
    if [ "$OS" = "macos" ]; then
        setup_macos
    else
        setup_linux
    fi
    
    set_environment
    
    # Linux Fish shell warning
    if [ "$OS" = "linux" ] && [[ "$SHELL" == *"fish" ]]; then
        echo ""
        echo "WARNING: Detected Fish shell. Please manually add the following to your environment variables:"
        echo "AWS_VAULT_BACKEND=file"
    fi
    
    echo ""
    echo "Installation complete for profile: $PROFILE_NAME"
    echo "Please restart your shell to apply all changes"
}

main "$@"
