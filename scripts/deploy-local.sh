#!/bin/bash
set -e

# Local deployment script
# This script deploys Kubernetes manifests from your local machine

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Homelab K8s Deployment ===${NC}"
echo ""

# Check if kubeconfig exists
if [ ! -f ".k3s-kubeconfig.yaml" ]; then
    echo -e "${RED}Error: .k3s-kubeconfig.yaml not found${NC}"
    echo "Run ./scripts/local-setup.sh first to set up infrastructure"
    exit 1
fi

export KUBECONFIG=.k3s-kubeconfig.yaml

# Check connection
echo -e "${YELLOW}Checking cluster connection...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to cluster${NC}"
    echo "Make sure:"
    echo "  1. K3s is running on the homelab machine"
    echo "  2. Tailscale is connected"
    echo "  3. The kubeconfig has the correct IP"
    exit 1
fi

echo -e "${GREEN}Connected to cluster!${NC}"
echo ""

# Check if Bitwarden secret exists
if ! kubectl get secret bitwarden-cli -n external-secrets-system >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Bitwarden secret not found${NC}"
    echo "Creating Bitwarden secret..."

    if [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ] || [ -z "$BW_PASSWORD" ]; then
        echo -e "${RED}Error: Bitwarden credentials not set${NC}"
        echo "Please set the following environment variables:"
        echo "  export BW_CLIENTID='your-client-id'"
        echo "  export BW_CLIENTSECRET='your-client-secret'"
        echo "  export BW_PASSWORD='your-password'"
        exit 1
    fi

    kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic bitwarden-cli \
      --namespace external-secrets-system \
      --from-literal=BW_CLIENTID="${BW_CLIENTID}" \
      --from-literal=BW_CLIENTSECRET="${BW_CLIENTSECRET}" \
      --from-literal=BW_PASSWORD="${BW_PASSWORD}" \
      --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}Bitwarden secret created${NC}"
    echo ""
fi

# Show what will be deployed
echo -e "${YELLOW}Deploying manifests from kubernetes/${NC}"
echo ""

read -p "Continue with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Deploy
echo -e "${GREEN}Deploying...${NC}"
kubectl apply -k kubernetes/

echo ""
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Status:"
kubectl get pods -A

echo ""
echo "To watch the deployment:"
echo "  kubectl get pods -A -w"
echo ""
echo "To check a specific namespace:"
echo "  kubectl get all -n apps"
echo ""
echo "To check external secrets:"
echo "  kubectl get externalsecrets -A"
