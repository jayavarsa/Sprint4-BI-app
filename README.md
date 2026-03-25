# BI Platform — DevOps Pipeline
### Production-Ready Multi-Tenant Kubernetes Deployment

---

## Table of Contents
1. [Project Overview](#1-project-overview)
2. [Project Structure](#2-project-structure)
3. [Team Responsibilities](#3-team-responsibilities)
4. [Prerequisites](#4-prerequisites)
5. [Local Development Setup](#5-local-development-setup)
6. [AWS Cloud Setup](#6-aws-cloud-setup)
7. [CI/CD Pipeline](#7-cicd-pipeline)
8. [Multi-Tenant Onboarding](#8-multi-tenant-onboarding)
9. [Deployment Flow](#9-deployment-flow)
10. [Zero-Downtime Deployment](#10-zero-downtime-deployment)
11. [Testing Instructions](#11-testing-instructions)
12. [Troubleshooting Guide](#12-troubleshooting-guide)

---

## 1. Project Overview

### Problem Solved
| Before | After |
|--------|-------|
| 3 days to onboard new client | < 10 minutes with automation script |
| Manual Docker builds | Automated CI on every git push |
| Inconsistent patches | Single image → all clients updated together |
| Downtime during deploy | Rolling updates → zero downtime |
| No isolation between clients | Separate Kubernetes namespace per client |

### Architecture at a Glance

```
Developer pushes code
        │
        ▼
┌─────────────────────┐
│   GitHub Actions CI  │  ← Runs tests, builds image, pushes to ECR
└─────────────────────┘
        │ triggers
        ▼
┌─────────────────────┐
│   GitHub Actions CD  │  ← Updates all client namespaces via kubectl
└─────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────┐
│                  AWS EKS Cluster                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │ client-acme  │  │client-globex │  │ client-... │  │
│  │  (NS)        │  │  (NS)        │  │  (NS)      │  │
│  │  2 pods      │  │  3 pods      │  │  2 pods    │  │
│  └──────────────┘  └──────────────┘  └────────────┘  │
└──────────────────────────────────────────────────────┘
```

---

## 2. Project Structure

```
bi-devops-platform/
│
├── app/                          # Flask BI application
│   ├── src/
│   │   └── app.py                # Main app: /, /health, /version, /api/dashboard
│   ├── tests/
│   │   └── test_app.py           # Pytest test suite
│   ├── requirements.txt          # Python dependencies
│   └── pytest.ini                # Test configuration
│
├── docker/
│   └── Dockerfile                # Multi-stage optimized Docker build
│
├── .github/
│   └── workflows/
│       ├── ci.yml                # CI: test → build → push to ECR
│       └── cd.yml                # CD: pull → deploy to EKS namespaces
│
├── k8s/
│   ├── base/                     # Shared Kubernetes manifests (Kustomize base)
│   │   ├── deployment.yaml       # Rolling update deployment
│   │   ├── service.yaml          # ClusterIP service
│   │   ├── ingress.yaml          # nginx ingress (per-client host)
│   │   └── kustomization.yaml    # Kustomize base config
│   │
│   └── overlays/                 # Per-client customizations
│       ├── client-acme/
│       │   └── kustomization.yaml
│       └── client-globex/
│           └── kustomization.yaml
│
├── scripts/
│   ├── onboard_client.sh         # New client in < 10 minutes
│   ├── setup_aws.sh              # One-time AWS/EKS cluster setup
│   └── test_deployment.sh        # Smoke tests + chaos test
│
├── docs/
│   └── README.md                 # This file
│
├── .dockerignore                 # Docker build exclusions
└── docker-compose.yml            # Local multi-tenant simulation
```

---

## 3. Team Responsibilities

| Member | Role | Files Owned |
|--------|------|-------------|
| **Chaithanya** | CI/CD Lead | `.github/workflows/ci.yml`, `.github/workflows/cd.yml`, `scripts/setup_aws.sh` |
| **Jayavarsan** | Kubernetes Lead | `k8s/base/*`, `k8s/overlays/*`, `scripts/onboard_client.sh` |
| **Premapriya** | Containerization & QA | `docker/Dockerfile`, `.dockerignore`, `docker-compose.yml`, `app/tests/*` |

### Week-by-Week Plan
```
Week 1: Premapriya — Finalize app + Dockerfile + local tests pass
Week 2: Chaithanya — GitHub Actions CI working end-to-end (ECR push)
Week 3: Jayavarsan — EKS cluster up, manifests applied, 2 clients live
Week 4: All        — CD automation, onboarding script, demo dry-run
```

---

## 4. Prerequisites

Install these tools before starting:

```bash
# 1. Docker Desktop
https://docs.docker.com/get-docker/

# 2. kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# 3. AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# 4. eksctl
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# 5. Helm (for ingress controller)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 6. Python 3.11 (for local app dev)
# https://www.python.org/downloads/

# Verify all tools
docker --version
kubectl version --client
aws --version
eksctl version
helm version
python3 --version
```

---

## 5. Local Development Setup

### 5.1 Clone the Repository

```bash
git clone https://github.com/YOUR_ORG/bi-devops-platform.git
cd bi-devops-platform
```

### 5.2 Run App Locally (Python)

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate

# Install dependencies
pip install -r app/requirements.txt
pip install pytest

# Run the app
cd app/src
CLIENT_ID=acme ENVIRONMENT=dev python app.py

# Test endpoints (open new terminal)
curl http://localhost:5000/health
curl http://localhost:5000/version
curl http://localhost:5000/api/dashboard
```

Expected output for `/health`:
```json
{
  "status": "healthy",
  "uptime_seconds": 5.23,
  "client": "acme",
  "environment": "dev",
  "timestamp": "2024-01-15T10:30:00"
}
```

### 5.3 Run Tests

```bash
# From project root
pip install pytest pytest-cov
pytest app/tests/ -v

# Expected:
# test_health_returns_200        PASSED
# test_health_returns_json       PASSED
# test_version_returns_200       PASSED
# ... (12 tests total)
```

### 5.4 Run with Docker (single container)

```bash
# Build the image
docker build -f docker/Dockerfile -t bi-platform:local .

# Run it
docker run -d \
  -p 5000:5000 \
  -e CLIENT_ID=acme \
  -e ENVIRONMENT=dev \
  --name bi-app \
  bi-platform:local

# Verify
curl http://localhost:5000/health
docker logs bi-app
docker stop bi-app && docker rm bi-app
```

### 5.5 Run Multi-Tenant Locally (Docker Compose)

```bash
# Start both simulated tenants
docker-compose up --build

# ACME client
curl http://localhost:5001/health          # {"client": "acme", ...}

# Globex client  
curl http://localhost:5002/health          # {"client": "globex", ...}

# Stop
docker-compose down
```

---

## 6. AWS Cloud Setup

> **Who does this:** Chaithanya (one-time setup)

### 6.1 Configure AWS CLI

```bash
aws configure
# AWS Access Key ID:     [from IAM → your user → Security credentials]
# AWS Secret Access Key: [same place]
# Default region:        us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity
```

### 6.2 Run the Setup Script

```bash
chmod +x scripts/setup_aws.sh
./scripts/setup_aws.sh
```

This script does everything:
- Creates ECR repository
- Creates EKS cluster (takes ~15 minutes)
- Configures kubectl
- Installs nginx ingress controller
- Creates ECR pull secrets
- Creates initial client namespaces

### 6.3 Add GitHub Secrets

Go to: GitHub repo → Settings → Secrets and variables → Actions → New repository secret

| Secret Name | Value |
|-------------|-------|
| `AWS_ACCESS_KEY_ID` | From IAM user |
| `AWS_SECRET_ACCESS_KEY` | From IAM user |

> **Minimum IAM Permissions needed:**
> - `AmazonEKSClusterPolicy`
> - `AmazonEC2ContainerRegistryFullAccess`
> - `AmazonEKSWorkerNodePolicy`

### 6.4 Update Image References

After setup, replace the placeholder ECR URL in all overlay files:

```bash
# Get your actual ECR registry URL
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="${AWS_ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com/bi-platform"

echo "Your ECR URL: ${ECR_URL}"

# Update all overlay files
sed -i "s|123456789.dkr.ecr.us-east-1.amazonaws.com/bi-platform|${ECR_URL}|g" \
  k8s/overlays/client-acme/kustomization.yaml \
  k8s/overlays/client-globex/kustomization.yaml
```

Also update `ci.yml` and `cd.yml`:
```yaml
# In .github/workflows/ci.yml and cd.yml, update:
AWS_REGION:    us-east-1         # your region
ECR_REPOSITORY: bi-platform      # your ECR repo name
EKS_CLUSTER:  bi-platform-cluster  # your cluster name
```

### 6.5 Apply Initial Kubernetes Manifests

```bash
# Deploy for ACME
kubectl apply -k k8s/overlays/client-acme/

# Deploy for Globex
kubectl apply -k k8s/overlays/client-globex/

# Verify both deployments are running
kubectl get pods -n client-acme
kubectl get pods -n client-globex
```

---

## 7. CI/CD Pipeline

### 7.1 How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                        CI Pipeline                           │
│                                                             │
│  git push                                                   │
│      │                                                      │
│      ▼                                                      │
│  [test job]                                                 │
│    - Install Python deps                                    │
│    - Run pytest (must pass, coverage ≥ 70%)                 │
│      │                                                      │
│      ▼ (only if tests pass)                                 │
│  [build-and-push job]                                       │
│    - Generate tags: latest + short-SHA                      │
│    - docker build (with BUILD_DATE, GIT_COMMIT baked in)    │
│    - Trivy security scan                                    │
│    - docker push → ECR                                      │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼ (only on main branch)
┌─────────────────────────────────────────────────────────────┐
│                        CD Pipeline                           │
│                                                             │
│  [deploy job]                                               │
│    - Configure kubectl (EKS)                                │
│    - Discover all namespaces labeled tenant=true            │
│    - kubectl set image → triggers rolling update per NS     │
│    - kubectl rollout status → waits for health              │
└─────────────────────────────────────────────────────────────┘
```

### 7.2 Trigger a Deployment

```bash
# Normal flow (recommended)
git add .
git commit -m "feat: update dashboard KPIs"
git push origin main
# → CI triggers automatically → CD triggers after CI succeeds

# Emergency manual deploy (specific image tag)
# Go to: GitHub Actions → CD Pipeline → Run workflow
# Enter image tag: abc1234
```

### 7.3 Monitor Pipeline Status

```bash
# Check GitHub Actions in the browser:
# https://github.com/YOUR_ORG/bi-devops-platform/actions

# Or watch rollout from CLI:
kubectl rollout status deployment/bi-platform-app -n client-acme
kubectl rollout status deployment/bi-platform-app -n client-globex
```

---

## 8. Multi-Tenant Onboarding

### Onboard a New Client in < 10 Minutes

```bash
chmod +x scripts/onboard_client.sh

# Usage: ./scripts/onboard_client.sh <client-id> <domain> [replicas]
./scripts/onboard_client.sh tesla tesla.bi-platform.io 2
```

The script:
1. Creates `k8s/overlays/client-tesla/kustomization.yaml` automatically
2. Creates and labels the `client-tesla` namespace
3. Copies the ECR pull secret into the new namespace
4. Applies all Kubernetes manifests
5. Waits for pods to become ready
6. Runs a smoke test (health check)

### What Gets Created Per Client

```
Kubernetes Namespace: client-tesla
├── Deployment: bi-platform-app  (2 replicas, rolling update)
├── Service:    bi-platform-svc  (ClusterIP, port 80)
├── Ingress:    bi-platform-ingress (host: tesla.bi-platform.io)
├── ConfigMap:  client-config    (CLIENT_ID=tesla)
└── Secret:     ecr-registry-secret
```

### Client Isolation

| Resource | Isolated? | How |
|----------|-----------|-----|
| Pods | ✅ Yes | Separate namespace |
| Config | ✅ Yes | Separate ConfigMap per namespace |
| Network | ✅ Yes | Each namespace gets its own Service + Ingress |
| Image | ❌ Shared | Same Docker image — configs differentiate behavior |
| Data | ⚠️ App-level | App reads `CLIENT_ID` env var for data scoping |

### DNS Setup for New Client

After onboarding, point the client's subdomain to the Load Balancer:

```bash
# Get the Load Balancer hostname
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Add a CNAME record in your DNS provider:
# tesla.bi-platform.io → CNAME → <above LB hostname>
```

---

## 9. Deployment Flow

Complete end-to-end flow with commands:

```bash
# ── STEP 1: Developer makes a change ──────────────────────────
vim app/src/app.py
git add app/src/app.py
git commit -m "fix: improve dashboard response time"

# ── STEP 2: Push triggers CI ───────────────────────────────────
git push origin main
# GitHub Actions CI starts:
#   ✅ pytest passes
#   ✅ docker build succeeds
#   ✅ trivy scan clean
#   ✅ image pushed: 123456.ecr.../bi-platform:latest

# ── STEP 3: CD triggers automatically ─────────────────────────
# GitHub Actions CD starts after CI succeeds:
#   ✅ kubectl configured
#   ✅ namespaces discovered: client-acme, client-globex
#   ✅ kubectl set image ... → rolling update starts
#   ✅ rollout complete in all namespaces

# ── STEP 4: Verify manually ───────────────────────────────────
kubectl get pods -n client-acme
# NAME                               READY   STATUS    RESTARTS
# bi-platform-app-7d9f8b6c4-xk2mp   1/1     Running   0
# bi-platform-app-7d9f8b6c4-pq9zl   1/1     Running   0

kubectl exec -n client-acme \
  $(kubectl get pods -n client-acme -l app=bi-platform-app -o jsonpath='{.items[0].metadata.name}') \
  -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5000/version').read())"
```

---

## 10. Zero-Downtime Deployment

### How Rolling Updates Work

```
BEFORE deploy:      Pod-A (v1.0)   Pod-B (v1.0)
                         ↑               ↑
                    [Traffic split between both]

DURING deploy:
  Step 1: Spawn  Pod-C (v1.1)           [SURGE +1]
  Step 2: Wait for Pod-C readiness probe to pass
  Step 3: Shift traffic to Pod-C
  Step 4: Terminate Pod-A               [DRAIN old]
  Step 5: Spawn  Pod-D (v1.1)           [SURGE +1]
  Step 6: Wait for Pod-D readiness probe
  Step 7: Terminate Pod-B

AFTER deploy:       Pod-C (v1.1)   Pod-D (v1.1)
```

Key settings in `deployment.yaml`:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0    # Never reduce below 2 running pods
    maxSurge: 1          # Allow 1 extra pod during transition
```

### Rollback if Something Goes Wrong

```bash
# Immediate rollback to previous version
kubectl rollout undo deployment/bi-platform-app -n client-acme

# Rollback to a specific revision
kubectl rollout history deployment/bi-platform-app -n client-acme
kubectl rollout undo deployment/bi-platform-app -n client-acme --to-revision=3

# Check rollback status
kubectl rollout status deployment/bi-platform-app -n client-acme
```

---

## 11. Testing Instructions

### Unit Tests (Premapriya)

```bash
# Install test dependencies
pip install pytest pytest-cov

# Run all tests
pytest app/tests/ -v

# Run with coverage
pytest app/tests/ --cov=app/src --cov-report=term-missing

# Run single test
pytest app/tests/test_app.py::TestHealthEndpoint::test_health_returns_200 -v
```

### Smoke Test After Deploy (All team)

```bash
chmod +x scripts/test_deployment.sh

# Test single client
./scripts/test_deployment.sh acme

# Test all clients
./scripts/test_deployment.sh
```

### Manual Pod Failure Test (Jayavarsan)

```bash
# Watch pods in real time (keep this terminal open)
watch kubectl get pods -n client-acme

# In a NEW terminal, kill a pod
kubectl delete pod \
  $(kubectl get pods -n client-acme -l app=bi-platform-app -o jsonpath='{.items[0].metadata.name}') \
  -n client-acme --force --grace-period=0

# Observe in first terminal:
# Old pod shows Terminating → new pod shows ContainerCreating → Running
# Takes about 15-30 seconds
```

### Rolling Update Test (Chaithanya)

```bash
# Trigger a fake update by changing the image tag
kubectl set image deployment/bi-platform-app \
  bi-platform-app=123456.dkr.ecr.us-east-1.amazonaws.com/bi-platform:latest \
  -n client-acme

# Watch the rollout (should complete with no downtime)
kubectl rollout status deployment/bi-platform-app -n client-acme

# While rollout is happening, in another terminal, keep curling:
while true; do
  curl -s http://acme.bi-platform.io/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])"
  sleep 0.5
done
# You should see: healthy healthy healthy ... (no gaps)
```

---

## 12. Troubleshooting Guide

### Pods Stuck in `CrashLoopBackOff`

```bash
# Check pod logs
kubectl logs -n client-acme -l app=bi-platform-app --previous

# Describe pod to see events
kubectl describe pod \
  $(kubectl get pods -n client-acme -o jsonpath='{.items[0].metadata.name}') \
  -n client-acme

# Common causes:
# 1. Missing ConfigMap → kubectl get configmap -n client-acme
# 2. Image pull failed → kubectl get events -n client-acme
# 3. OOM → increase memory limit in deployment.yaml
```

### Image Pull Errors (`ErrImagePull`)

```bash
# Verify ECR secret exists in namespace
kubectl get secret ecr-registry-secret -n client-acme

# Recreate the secret (run from scripts/setup_aws.sh logic)
AWS_REGION=us-east-1
ECR_REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com
ECR_PASSWORD=$(aws ecr get-login-password --region $AWS_REGION)

kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=$ECR_REGISTRY \
  --docker-username=AWS \
  --docker-password=$ECR_PASSWORD \
  -n client-acme \
  --dry-run=client -o yaml | kubectl apply -f -
```

### CI Fails at Test Step

```bash
# Run tests locally to replicate
cd bi-devops-platform
pip install -r app/requirements.txt pytest
pytest app/tests/ -v

# Common cause: import error → check sys.path in test_app.py
# Common cause: Flask version mismatch → check requirements.txt
```

### CD Fails: `namespaces not found`

```bash
# Check namespace labels (CD discovers namespaces by label)
kubectl get namespaces --show-labels | grep tenant

# Re-label a namespace manually
kubectl label namespace client-acme app.bi-platform/tenant=true --overwrite
```

### Rollout Stuck / Timeout

```bash
# Check deployment events
kubectl describe deployment bi-platform-app -n client-acme

# Check if new pods are crashing
kubectl get pods -n client-acme

# If stuck, rollback immediately
kubectl rollout undo deployment/bi-platform-app -n client-acme
```

### Check Resource Usage

```bash
# Pod resource usage
kubectl top pods -n client-acme

# Node usage
kubectl top nodes

# If pods are OOMKilled, increase memory limits in deployment.yaml:
# limits.memory: "512Mi"
```

### Useful Debug Commands

```bash
# Get all resources in a namespace
kubectl get all -n client-acme

# Stream live logs from all pods of a deployment
kubectl logs -n client-acme -l app=bi-platform-app -f

# Get recent events (sorted by time)
kubectl get events -n client-acme --sort-by='.lastTimestamp'

# Execute into a running pod
kubectl exec -it \
  $(kubectl get pods -n client-acme -l app=bi-platform-app -o jsonpath='{.items[0].metadata.name}') \
  -n client-acme -- /bin/sh

# Port-forward to test without ingress
kubectl port-forward \
  $(kubectl get pods -n client-acme -l app=bi-platform-app -o jsonpath='{.items[0].metadata.name}') \
  8080:5000 -n client-acme
# Then: curl http://localhost:8080/health
```

---

## Quick Reference Card

```bash
# ── Daily Commands ────────────────────────────────────────────
kubectl get pods -n client-acme                              # Check pod status
kubectl logs -n client-acme -l app=bi-platform-app -f       # Live logs
kubectl rollout status deployment/bi-platform-app -n client-acme  # Rollout watch

# ── Onboard New Client ────────────────────────────────────────
./scripts/onboard_client.sh <id> <domain> [replicas]

# ── Manual Deploy ─────────────────────────────────────────────
kubectl set image deployment/bi-platform-app \
  bi-platform-app=<ECR_URL>:<tag> -n <namespace>

# ── Rollback ─────────────────────────────────────────────────
kubectl rollout undo deployment/bi-platform-app -n <namespace>

# ── Run Tests ─────────────────────────────────────────────────
pytest app/tests/ -v
./scripts/test_deployment.sh <client-id>
```
