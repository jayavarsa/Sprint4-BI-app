#!/usr/bin/env bash
# =============================================================================
# Deployment Verification & Chaos Test Script
# Owner: Premapriya (QA)
#
# Tests:
#   1. Health endpoint of each tenant
#   2. Version endpoint
#   3. Pod failure simulation + auto-recovery
#
# Usage:
#   chmod +x scripts/test_deployment.sh
#   ./scripts/test_deployment.sh acme         # Test single client
#   ./scripts/test_deployment.sh              # Test all clients
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; }
info() { echo -e "${YELLOW}ℹ  INFO${NC}: $1"; }

TARGET_CLIENT="${1:-}"

# ── Helper: test a namespace ───────────────────────────────────
test_namespace() {
  local NS="$1"
  echo ""
  echo "══════════════════════════════════════"
  echo " Testing namespace: ${NS}"
  echo "══════════════════════════════════════"

  # ── Check pods are running ─────────────────────────────────
  info "Checking pods..."
  RUNNING=$(kubectl get pods -n "${NS}" -l app=bi-platform-app \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[*].metadata.name}' | wc -w)
  TOTAL=$(kubectl get pods -n "${NS}" -l app=bi-platform-app \
    -o jsonpath='{.items[*].metadata.name}' | wc -w)

  if [ "${RUNNING}" -gt 0 ]; then
    pass "Pods running: ${RUNNING}/${TOTAL}"
  else
    fail "No pods running in ${NS}"
    return 1
  fi

  # Pick the first pod for exec tests
  POD=$(kubectl get pods -n "${NS}" -l app=bi-platform-app \
    -o jsonpath='{.items[0].metadata.name}')

  # ── Health check ──────────────────────────────────────────
  info "Testing /health endpoint..."
  HEALTH=$(kubectl exec -n "${NS}" "${POD}" -- \
    python -c "import urllib.request, json; r=urllib.request.urlopen('http://localhost:5000/health'); print(json.loads(r.read())['status'])" 2>/dev/null)

  if [ "${HEALTH}" = "healthy" ]; then
    pass "/health → ${HEALTH}"
  else
    fail "/health returned: ${HEALTH}"
  fi

  # ── Version check ─────────────────────────────────────────
  info "Testing /version endpoint..."
  VERSION=$(kubectl exec -n "${NS}" "${POD}" -- \
    python -c "import urllib.request, json; r=urllib.request.urlopen('http://localhost:5000/version'); print(json.loads(r.read())['version'])" 2>/dev/null)
  pass "/version → ${VERSION}"

  # ── Readiness check ───────────────────────────────────────
  info "Testing /ready endpoint..."
  READY=$(kubectl exec -n "${NS}" "${POD}" -- \
    python -c "import urllib.request, json; r=urllib.request.urlopen('http://localhost:5000/ready'); print(json.loads(r.read())['ready'])" 2>/dev/null)

  if [ "${READY}" = "True" ]; then
    pass "/ready → ready"
  else
    fail "/ready returned: ${READY}"
  fi

  # ── Dashboard check ───────────────────────────────────────
  info "Testing /api/dashboard endpoint..."
  DASHBOARD_CLIENT=$(kubectl exec -n "${NS}" "${POD}" -- \
    python -c "import urllib.request, json; r=urllib.request.urlopen('http://localhost:5000/api/dashboard'); print(json.loads(r.read())['client'])" 2>/dev/null)
  pass "/api/dashboard → client: ${DASHBOARD_CLIENT}"
}

# ── Chaos test: Kill a pod, verify recovery ──────────────────
chaos_test() {
  local NS="$1"
  echo ""
  echo "══════════════════════════════════════"
  echo " Chaos Test: Pod Failure Recovery"
  echo "══════════════════════════════════════"

  # Get pod to kill
  POD_TO_KILL=$(kubectl get pods -n "${NS}" -l app=bi-platform-app \
    -o jsonpath='{.items[0].metadata.name}')

  info "Killing pod: ${POD_TO_KILL}"
  kubectl delete pod "${POD_TO_KILL}" -n "${NS}" --grace-period=0 --force 2>/dev/null || true

  info "Waiting 5 seconds for Kubernetes to detect and replace..."
  sleep 5

  # Kubernetes should auto-restart due to deployment desired state
  info "Checking new pod comes up..."
  kubectl wait pod \
    --for=condition=Ready \
    -l app=bi-platform-app \
    -n "${NS}" \
    --timeout=60s

  NEW_PODS=$(kubectl get pods -n "${NS}" -l app=bi-platform-app \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[*].metadata.name}')

  pass "Pod auto-restarted: ${NEW_PODS}"
}

# ── Main ──────────────────────────────────────────────────────
if [ -n "${TARGET_CLIENT}" ]; then
  # Test specific client
  test_namespace "client-${TARGET_CLIENT}"
  chaos_test "client-${TARGET_CLIENT}"
else
  # Test all tenant namespaces
  NAMESPACES=$(kubectl get namespaces -l "app.bi-platform/tenant=true" \
    -o jsonpath='{.items[*].metadata.name}')

  if [ -z "${NAMESPACES}" ]; then
    echo "No tenant namespaces found. Have you onboarded any clients?"
    exit 1
  fi

  for NS in ${NAMESPACES}; do
    test_namespace "${NS}"
  done

  # Run chaos test on first namespace only
  FIRST_NS=$(echo "${NAMESPACES}" | awk '{print $1}')
  chaos_test "${FIRST_NS}"
fi

echo ""
echo "══════════════════════════════════════"
echo " All tests complete!"
echo "══════════════════════════════════════"
