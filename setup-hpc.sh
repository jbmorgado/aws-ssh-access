#!/usr/bin/env bash
set -euo pipefail

# Relaunch with bash if not already running in bash
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
    exit $?
fi

# Color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK="✓"
WARN="⚠"
INFO="ℹ"

# Check for required arguments
if [ $# -ne 3 ]; then
    echo -e "${RED}Usage: $0 <iam_username> <mfa_identifier> <profile_name>${NC}"
    echo -e "${YELLOW}Example: curl -sSL https://example.com/installer.sh | bash -s -- iam-john.smith arn:aws:iam::441841723118:mfa/Example jsmith${NC}"
    exit 1
fi

IAM_USER="$1"
MFA_IDENTIFIER="$2"
PROFILE_NAME="$3"

# -------- Configuration ----------
INSTALLER_BASE_URL="https://raw.githubusercontent.com/jbmorgado/aws-ssh-access"
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

# ----------------------------------

detect_os() {
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$OS" in
        linux*)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS_ID="$ID"
                if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" && "$OS_ID" != "pop" && "$OS_ID" != "fedora" ]]; then
                    echo -e "${RED}Unsupported Linux distribution: $OS_ID${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}Unsupported Linux distribution${NC}"
                exit 1
            fi
            ;;
        darwin*) OS="macos" ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac
}

setup_aws_config() {
    local aws_dir="$HOME/.aws"
    local config_file="$aws_dir/config"
    
    mkdir -p "$aws_dir"
    
    if ! grep -q "\[profile $IAM_USER\]" "$config_file"; then
        cat >> "$config_file" <<EOF
[profile $IAM_USER]
region = eu-west-2
mfa_serial = $MFA_IDENTIFIER
EOF
    fi

    if ! grep -q "\[profile dp-hpc\]" "$config_file"; then
        cat >> "$config_file" <<EOF

[profile dp-hpc]
source_profile = $IAM_USER
role_arn = arn:aws:iam::533267315508:role/SKAO-DP-HPC-user
region = eu-west-2
mfa_serial = $MFA_IDENTIFIER
EOF
    fi

    echo -e "${GREEN}${CHECK} AWS configuration created/updated at $config_file${NC}"
}

setup_ssh_config() {
    local ssh_dir="$HOME/.ssh"
    local config_file="$ssh_dir/config"
    local identity_file="$ssh_dir/id_ed25519"
    local script_path="$LOCAL_BIN_DIR/ssh-aws-ssm.sh"

    if [ ! -f "$identity_file" ]; then
        echo -e "\n${YELLOW}${WARN} WARNING: Expected SSH key $identity_file not found!${NC}"
        echo -e "${YELLOW}Unless you have a specific reason to use a different key, generate one with:"
        echo -e "ssh-keygen -t ed25519 -f $identity_file${NC}\n"
    fi
    
    mkdir -p "$ssh_dir"
    touch "$config_file"
    
    if ! grep -q "Host dp-hpc-headnode" "$config_file"; then
        cat >> "$config_file" <<EOF

Host dp-hpc-headnode
    Hostname i-03bbc056f0dec808b
    User $PROFILE_NAME
    ProxyCommand $script_path %h %p
    IdentityFile $identity_file
    ServerAliveInterval 60
EOF
        echo -e "${GREEN}${CHECK} SSH configuration updated at $config_file${NC}"
    else
        echo -e "${CYAN}${INFO} SSH configuration already exists, skipping update${NC}"
    fi
}

install_ssh_script() {
    local script_path="$LOCAL_BIN_DIR/ssh-aws-ssm.sh"
    local ssh_script_url="$INSTALLER_BASE_URL/refs/heads/master/ssh-aws-ssm.sh"
    
    mkdir -p "$LOCAL_BIN_DIR"

    echo -e "${CYAN}${INFO} Downloading SSH helper script from $ssh_script_url...${NC}"
    if ! curl -fsSL -o "$script_path" "$ssh_script_url"; then
        echo -e "\n${RED}✖ ERROR: Failed to download ssh-aws-ssm.sh${NC}"
        echo -e "${RED}Please verify the URL is accessible:"
        echo -e "$ssh_script_url${NC}\n"
        exit 1
    fi
    
    chmod +x "$script_path"
    echo -e "${GREEN}${CHECK} Installed ssh-aws-ssm.sh to $LOCAL_BIN_DIR${NC}"
    
    if ! head -1 "$script_path" | grep -q '^#!/'; then
        echo -e "\n${RED}✖ ERROR: Downloaded script appears invalid${NC}"
        rm -f "$script_path"
        exit 1
    fi
    
    if [[ ":$PATH:" != *":$LOCAL_BIN_DIR:"* ]]; then
        echo -e "${YELLOW}${WARN} WARNING: $LOCAL_BIN_DIR is not in your PATH. Add to shell config:${NC}"
        echo "export PATH=\"$LOCAL_BIN_DIR:\$PATH\""
    fi
}

setup_linux() {
    echo -e "\n${CYAN}${INFO} Setting up Linux ($OS_ID)...${NC}"

    case "$OS_ID" in
        debian|ubuntu|pop)
            sudo apt-get update
            sudo apt-get install -y curl wget unzip
            ;;
        fedora)
            sudo dnf install -y curl wget unzip
            ;;
    esac

    if ! command -v aws &> /dev/null || ! aws --version 2>&1 | grep -q "aws-cli/2"; then
        echo -e "${CYAN}${INFO} Installing AWS CLI v2...${NC}"
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf awscliv2.zip aws || true
        echo -e "${GREEN}${CHECK} AWS CLI v2 installed${NC}"
    else
        echo -e "${CYAN}${INFO} AWS CLI v2 already installed, skipping...${NC}"
    fi

    if ! command -v session-manager-plugin &> /dev/null; then
        echo -e "${CYAN}${INFO} Installing Session Manager Plugin...${NC}"
        case "$OS_ID" in
            debian|ubuntu|pop)
                local session_plugin_deb="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
                wget "$session_plugin_deb" -O session-manager-plugin.deb
                sudo dpkg -i session-manager-plugin.deb
                rm session-manager-plugin.deb
                ;;
            fedora)
                local session_plugin_rpm="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm"
                wget "$session_plugin_rpm" -O session-manager-plugin.rpm
                sudo dnf install -y session-manager-plugin.rpm
                rm session-manager-plugin.rpm
                ;;
        esac
        echo -e "${GREEN}${CHECK} Session Manager Plugin installed${NC}"
    else
        echo -e "${CYAN}${INFO} Session Manager Plugin already installed, skipping...${NC}"
    fi

    if ! command -v vault &> /dev/null; then
        echo -e "${CYAN}${INFO} Installing HashiCorp Vault...${NC}"
        case "$OS_ID" in
            debian|ubuntu|pop)
                wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                sudo apt update
                sudo apt install -y vault
                ;;
            fedora)
                sudo dnf install -y dnf-plugins-core
                sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
                sudo dnf install -y vault
                ;;
        esac
        echo -e "${GREEN}${CHECK} HashiCorp Vault installed${NC}"
    else
        echo -e "${CYAN}${INFO} Vault already installed, skipping...${NC}"
    fi

    for entry in "${LINUX_EXECUTABLES[@]}"; do
        URL="${entry%%|*}"
        NAME="${entry##*|}"
        if ! command -v "$NAME" &> /dev/null; then
            echo -e "${CYAN}${INFO} Installing $NAME...${NC}"
            curl -fsSL "$URL" | sudo tee "/usr/local/bin/$NAME" >/dev/null
            sudo chmod +x "/usr/local/bin/$NAME"
            echo -e "${GREEN}${CHECK} $NAME installed${NC}"
        else
            echo -e "${CYAN}${INFO} $NAME already installed, skipping...${NC}"
        fi
    done
}

setup_macos() {
    echo -e "\n${CYAN}${INFO} Setting up macOS...${NC}"
    
    if ! command -v brew &> /dev/null; then
        echo -e "\n${RED}✖ ERROR: Homebrew is required for macOS installation.${NC}"
        echo -e "${YELLOW}Install it using:"
        echo -e '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n'"${NC}"
        exit 1
    fi
    
    for tap in "${BREW_TAPS[@]}"; do
        brew tap "$tap"
    done
    
    for pkg in "${MACOS_BREW_PACKAGES[@]}"; do
        echo -e "${CYAN}${INFO} Installing $pkg...${NC}"
        brew install "$pkg"
    done
    
    for cask in "${MACOS_BREW_CASKS[@]}"; do
        echo -e "${CYAN}${INFO} Installing $cask...${NC}"
        brew install --cask "$cask"
    done
}

set_environment() {
    echo -e "${CYAN}${INFO} Setting environment variables...${NC}"
    local profile_file="$HOME/.profile"
    touch "$profile_file"
    
    if [ "$OS" = "linux" ]; then
        if ! grep -qF "export AWS_VAULT_BACKEND=file" "$profile_file"; then
            echo "export AWS_VAULT_BACKEND=file" >> "$profile_file"
            echo -e "${GREEN}${CHECK} Added AWS_VAULT_BACKEND to $profile_file${NC}"
        fi
    fi
    
    source "$profile_file"
}

add_aws_vault_profile() {
    if ! aws-vault list --credentials | grep -qxF "$IAM_USER"; then
        echo -e "\n${CYAN}${INFO} Adding AWS Vault profile for $IAM_USER...${NC}"
        echo -e "${YELLOW}Please enter credentials when prompted:${NC}"
        aws-vault add "$IAM_USER" </dev/tty  # Critical fix here
        echo -e "${GREEN}${CHECK} AWS Vault profile added${NC}"
    else
        echo -e "${CYAN}${INFO} AWS Vault profile $IAM_USER already exists, skipping...${NC}"
    fi
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
    add_aws_vault_profile
    
    if [ "$OS" = "linux" ] && [[ "$SHELL" == *"fish" ]]; then
        echo -e "\n${YELLOW}${WARN} WARNING: Detected Fish shell. Add to environment:${NC}"
        echo "set -gx AWS_VAULT_BACKEND file"
    fi
    
    echo -e "\n${GREEN}${CHECK} Installation complete for profile: $PROFILE_NAME${NC}"
    echo -e "${CYAN}Please restart your shell to apply changes${NC}"
}

main "$@"