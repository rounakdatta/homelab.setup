#!/bin/bash
set -e

# Local setup script for homelab infrastructure
# This script helps you set up the infrastructure locally before using GitHub Actions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Homelab Infrastructure Setup ===${NC}"
echo ""

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}Loading environment variables from .env${NC}"
    set -a  # automatically export all variables
    source .env
    set +a
    echo ""
fi

# Check if required commands are available
command -v ansible-playbook >/dev/null 2>&1 || {
    echo -e "${RED}Error: ansible-playbook is not installed${NC}"
    exit 1
}

command -v ssh >/dev/null 2>&1 || {
    echo -e "${RED}Error: ssh is not installed${NC}"
    exit 1
}

# Check for required environment variables
REQUIRED_VARS=(
    "BW_CLIENTID"
    "BW_CLIENTSECRET"
    "BW_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var environment variable is not set${NC}"
        echo ""
        echo "Please set the following Bitwarden environment variables:"
        echo "  export BW_CLIENTID='your-bitwarden-client-id'"
        echo "  export BW_CLIENTSECRET='your-bitwarden-client-secret'"
        echo "  export BW_PASSWORD='your-bitwarden-master-password'"
        exit 1
    fi
done

echo -e "${YELLOW}Configuration:${NC}"
echo "  Bitwarden Client ID: ${BW_CLIENTID:0:10}***"
echo ""

read -p "Continue with infrastructure setup? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo -e "${GREEN}Running Ansible playbook...${NC}"
cd ansible/

# Run playbook with Bitwarden credentials
ansible-playbook playbook.yml \
  -i hosts \
  --extra-vars "bitwarden_client_id=${BW_CLIENTID}" \
  --extra-vars "bitwarden_client_secret=${BW_CLIENTSECRET}" \
  --extra-vars "bitwarden_password=${BW_PASSWORD}" \
  -v

cd ..

echo ""
echo -e "${GREEN}Infrastructure setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Setup kubeconfig: export KUBECONFIG=\$(pwd)/.k3s-kubeconfig.yaml"
echo "  2. Deploy apps: kubectl apply -k kubernetes/"
echo ""
echo "Or check cluster health: ./scripts/health-check.sh"
