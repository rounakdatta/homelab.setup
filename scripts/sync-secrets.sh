#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Bitwarden Secret Sync Script ===${NC}"
echo ""

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}Loading environment variables from .env${NC}"
    set -a  # automatically export all variables
    source .env
    set +a
    echo ""
fi

# Verify required environment variables
if [ -z "${BW_CLIENTID:-}" ] || [ -z "${BW_CLIENTSECRET:-}" ] || [ -z "${BW_PASSWORD:-}" ]; then
    echo -e "${RED}ERROR: Missing required Bitwarden credentials${NC}"
    echo "Please ensure BW_CLIENTID, BW_CLIENTSECRET, and BW_PASSWORD are set"
    echo "Either create a .env file or export them as environment variables"
    exit 1
fi

# Check if bitwarden CLI is installed
if ! command -v bw &> /dev/null; then
    echo -e "${RED}ERROR: Bitwarden CLI not found${NC}"
    echo "Please install it first:"
    echo "  npm install -g @bitwarden/cli"
    echo "  or: brew install bitwarden-cli"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}ERROR: kubectl not found${NC}"
    echo "Please ensure kubectl is installed and configured"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Login to Bitwarden
echo -e "${YELLOW}Logging into Bitwarden...${NC}"
export BW_SESSION=$(bw login --apikey --raw || bw unlock --raw "${BW_PASSWORD}")

if [ -z "$BW_SESSION" ]; then
    echo -e "${RED}ERROR: Failed to login to Bitwarden${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Logged into Bitwarden${NC}"
echo ""

# Sync Bitwarden vault
echo -e "${YELLOW}Syncing Bitwarden vault...${NC}"
bw sync --session "$BW_SESSION" > /dev/null
echo -e "${GREEN}✓ Vault synced${NC}"
echo ""

# Function to get secret from Bitwarden and create in K8s
create_k8s_secret() {
    local secret_name=$1
    local namespace=$2
    local bw_item_name=$3
    local key_name=$4

    echo -e "${YELLOW}Processing: ${secret_name} in namespace ${namespace}${NC}"

    # Fetch secret value from Bitwarden
    local secret_value
    secret_value=$(bw get password "$bw_item_name" --session "$BW_SESSION" 2>/dev/null || echo "")

    if [ -z "$secret_value" ]; then
        echo -e "${RED}  ✗ Failed to fetch secret from Bitwarden: ${bw_item_name}${NC}"
        return 1
    fi

    # Create or update secret in Kubernetes
    kubectl create secret generic "$secret_name" \
        --namespace="$namespace" \
        --from-literal="${key_name}=${secret_value}" \
        --dry-run=client -o yaml | kubectl apply -f - > /dev/null

    echo -e "${GREEN}  ✓ Created/Updated secret: ${secret_name}${NC}"
}

# Function to create multi-key secrets
create_k8s_secret_multi() {
    local secret_name=$1
    local namespace=$2
    shift 2

    echo -e "${YELLOW}Processing: ${secret_name} in namespace ${namespace}${NC}"

    local cmd="kubectl create secret generic \"$secret_name\" --namespace=\"$namespace\""
    local failed=0

    # Process each key-value pair
    while [ $# -gt 0 ]; do
        local key_name=$1
        local bw_item_name=$2
        shift 2

        local secret_value
        secret_value=$(bw get password "$bw_item_name" --session "$BW_SESSION" 2>/dev/null || echo "")

        if [ -z "$secret_value" ]; then
            echo -e "${RED}  ✗ Failed to fetch secret from Bitwarden: ${bw_item_name}${NC}"
            failed=1
            break
        fi

        cmd="$cmd --from-literal=\"${key_name}=${secret_value}\""
    done

    if [ $failed -eq 0 ]; then
        eval "$cmd --dry-run=client -o yaml | kubectl apply -f - > /dev/null"
        echo -e "${GREEN}  ✓ Created/Updated secret: ${secret_name}${NC}"
    fi
}

# Define secrets to sync
# Format: create_k8s_secret "k8s-secret-name" "namespace" "bitwarden-item-name" "key-name"

echo -e "${BLUE}=== Syncing Secrets ===${NC}"
echo ""

# MySQL credentials (consolidated)
create_k8s_secret "mysql-credentials" "databases" "mysql/root_password" "root-password"

# Firefly III credentials (consolidated)
create_k8s_secret_multi "firefly-credentials" "apps" \
    "app-key" "firefly/app_key" \
    "db-name" "firefly/db_name" \
    "db-username" "firefly/db_username" \
    "db-password" "firefly/db_password"

# Add more secrets here as needed:
# create_k8s_secret "another-secret" "namespace" "bitwarden-item-name" "key-name"

echo ""
echo -e "${GREEN}=== Secret sync complete! ===${NC}"
echo ""

# Logout from Bitwarden
bw lock --session "$BW_SESSION" > /dev/null 2>&1 || true

echo -e "${BLUE}Next steps:${NC}"
echo "  1. Verify secrets: kubectl get secrets -A"
echo "  2. Deploy applications: kubectl apply -k kubernetes/"
echo ""
