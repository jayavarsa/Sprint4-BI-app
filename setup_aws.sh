#!/usr/bin/env bash
# =============================================================================
# AWS EKS Cluster Setup Script
# Owner: Chaithanya (CI/CD Lead)
#
# Creates:
#   - EKS cluster (bi-platform-cluster)
#   - Node group (2-4 t3.medium nodes)
#   - ECR repository
#   - kubeconfig update
#   - nginx ingress controller
#   - ECR pull secret
#
# Prerequisites:
#   - AWS CLI v2 installed and configured (aws configure)
#   - eksctl installed: https://eksctl.io/introduction/#installation
#   - kubectl installed
#   - helm installed (for ingress controller)
#
# Run: chmod +x scripts/setup_aws.sh && ./scripts/setup_aws.sh
# =============================================================================

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────
AWS_REGION="us-east-1"
CLUSTER_NAME="bi-platform-cluster"
ECR_REPO_NAME="bi-platform"
NODE_TYPE="t3.medium"
MIN_NODES=2
MAX_NODES=4
DESIRED_NODES=2

echo "========================================="
echo " BI Platform — AWS EKS Setup"
echo "========================================="
echo "Region:    ${AWS_REGION}"
echo "Cluster:   ${CLUSTER_NAME}"
echo "Nodes:     ${MIN_NODES}-${MAX_NODES} x ${NODE_TYPE}"
echo ""

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "ECR Registry: ${ECR_REGISTRY}"
echo ""

# ── Step 1: Create ECR Repository ─────────────────────────────
echo "[1/6] Creating ECR repository..."
aws ecr create-repository \
  --repository-name "${ECR_REPO_NAME}" \
  --region "${AWS_REGION}" \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability MUTABLE \
  2>/dev/null || echo "    Repository already exists — skipping"

echo "    ✅ ECR: ${ECR_REGISTRY}/${ECR_REPO_NAME}"

# ── Step 2: Create EKS Cluster ────────────────────────────────
echo "[2/6] Creating EKS cluster (this takes ~15 minutes)..."
eksctl create cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --nodegroup-name "bi-platform-nodes" \
  --node-type "${NODE_TYPE}" \
  --nodes "${DESIRED_NODES}" \
  --nodes-min "${MIN_NODES}" \
  --nodes-max "${MAX_NODES}" \
  --managed \
  --asg-access \
  2>/dev/null || echo "    Cluster already exists — skipping creation"

echo "    ✅ EKS cluster ready"

# ── Step 3: Configure kubectl ─────────────────────────────────
echo "[3/6] Configuring kubectl..."
aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}"

kubectl cluster-info
echo "    ✅ kubectl configured"

# ── Step 4: Install nginx Ingress Controller ──────────────────
echo "[4/6] Installing nginx ingress controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --wait \
  --timeout 5m

echo "    ✅ Ingress controller installed"
echo "    LoadBalancer IP (for DNS):"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""

# ── Step 5: Create ECR pull secret ────────────────────────────
echo "[5/6] Creating ECR pull secret in default namespace..."
ECR_PASSWORD=$(aws ecr get-login-password --region "${AWS_REGION}")

kubectl create secret docker-registry ecr-registry-secret \
  --docker-server="${ECR_REGISTRY}" \
  --docker-username="AWS" \
  --docker-password="${ECR_PASSWORD}" \
  --namespace=default \
  --dry-run=client -o yaml | kubectl apply -f -

echo "    ✅ ECR secret created"

# ── Step 6: Create initial client namespaces ──────────────────
echo "[6/6] Creating initial tenant namespaces..."
kubectl create namespace client-acme   --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace client-globex --dry-run=client -o yaml | kubectl apply -f -

for NS in client-acme client-globex; do
  kubectl label namespace "${NS}" "app.bi-platform/tenant=true" --overwrite
  # Copy ECR secret to each namespace
  kubectl get secret ecr-registry-secret --namespace=default \
    -o yaml | sed "s/namespace: default/namespace: ${NS}/" | kubectl apply -f -
done

echo "    ✅ Initial namespaces ready"

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "========================================="
echo " ✅ AWS Setup Complete!"
echo "========================================="
echo ""
echo "Add these to your GitHub Secrets:"
echo "  AWS_ACCESS_KEY_ID     → from IAM user"
echo "  AWS_SECRET_ACCESS_KEY → from IAM user"
echo ""
echo "Update k8s/overlays/*/kustomization.yaml image with:"
echo "  ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest"
echo ""
echo "Next steps:"
echo "  1. Push code to main branch to trigger CI/CD"
echo "  2. Run: ./scripts/onboard_client.sh <client-id> <domain>"
