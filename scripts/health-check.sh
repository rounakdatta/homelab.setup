#!/bin/bash

# Health check script for homelab K8s cluster
# This script checks the status of all components

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if kubeconfig exists
if [ ! -f ".k3s-kubeconfig.yaml" ]; then
    echo -e "${RED}Error: .k3s-kubeconfig.yaml not found${NC}"
    exit 1
fi

export KUBECONFIG=.k3s-kubeconfig.yaml

echo -e "${BLUE}=== Homelab K8s Health Check ===${NC}"
echo ""

# Check cluster connectivity
echo -e "${YELLOW}Checking cluster connectivity...${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Cluster is reachable${NC}"
else
    echo -e "${RED}✗ Cannot connect to cluster${NC}"
    exit 1
fi
echo ""

# Check node status
echo -e "${YELLOW}Node Status:${NC}"
kubectl get nodes
echo ""

# Check system pods
echo -e "${YELLOW}System Pods (kube-system):${NC}"
kubectl get pods -n kube-system
echo ""

# Check External Secrets Operator
echo -e "${YELLOW}External Secrets Operator:${NC}"
ESO_PODS=$(kubectl get pods -n external-secrets-system --no-headers 2>/dev/null | wc -l)
if [ "$ESO_PODS" -gt 0 ]; then
    kubectl get pods -n external-secrets-system
    echo -e "${GREEN}✓ ESO is running${NC}"
else
    echo -e "${RED}✗ ESO is not running${NC}"
fi
echo ""

# Check ClusterSecretStore
echo -e "${YELLOW}Bitwarden Secret Store:${NC}"
if kubectl get clustersecretstore bitwarden-secret-store >/dev/null 2>&1; then
    echo -e "${GREEN}✓ ClusterSecretStore configured${NC}"
else
    echo -e "${RED}✗ ClusterSecretStore not found${NC}"
fi
echo ""

# Check all namespaces
echo -e "${YELLOW}All Namespaces:${NC}"
kubectl get namespaces
echo ""

# Check pods in all namespaces
echo -e "${YELLOW}All Pods:${NC}"
kubectl get pods -A
echo ""

# Count pods by status
RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running")
PENDING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Pending")
FAILED=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c -E "Error|CrashLoopBackOff|ImagePullBackOff")

echo -e "${YELLOW}Pod Summary:${NC}"
echo -e "  Running: ${GREEN}${RUNNING}${NC}"
echo -e "  Pending: ${YELLOW}${PENDING}${NC}"
echo -e "  Failed:  ${RED}${FAILED}${NC}"
echo ""

# Check PVCs
echo -e "${YELLOW}Persistent Volume Claims:${NC}"
kubectl get pvc -A
echo ""

# Check services
echo -e "${YELLOW}Services:${NC}"
kubectl get svc -A
echo ""

# Check ExternalSecrets
echo -e "${YELLOW}External Secrets:${NC}"
EXTERNALSECRETS=$(kubectl get externalsecrets -A --no-headers 2>/dev/null | wc -l)
if [ "$EXTERNALSECRETS" -gt 0 ]; then
    kubectl get externalsecrets -A

    # Check for failed syncs
    FAILED_SECRETS=$(kubectl get externalsecrets -A --no-headers 2>/dev/null | grep -v "SecretSynced" | wc -l)
    if [ "$FAILED_SECRETS" -gt 0 ]; then
        echo -e "${RED}Warning: Some secrets are not syncing${NC}"
    else
        echo -e "${GREEN}✓ All secrets synced${NC}"
    fi
else
    echo -e "${YELLOW}No ExternalSecrets found${NC}"
fi
echo ""

# Check recent events
echo -e "${YELLOW}Recent Events (last 10):${NC}"
kubectl get events -A --sort-by='.lastTimestamp' | tail -10
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ "$FAILED" -eq 0 ] && [ "$PENDING" -eq 0 ]; then
    echo -e "${GREEN}✓ All systems operational${NC}"
elif [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}✗ Some pods have failed${NC}"
    echo "  Run: kubectl get pods -A | grep -E 'Error|CrashLoopBackOff|ImagePullBackOff'"
elif [ "$PENDING" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some pods are pending${NC}"
    echo "  Run: kubectl describe pod <pod-name> -n <namespace>"
fi
echo ""
