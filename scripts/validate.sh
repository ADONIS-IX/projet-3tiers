#!/bin/bash
# =============================================================================
# Validation architecture 3-tiers hybride (version sandbox actuelle)
# Exécution: depuis le poste avec oc + virtctl connectés au cluster
# =============================================================================

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${1:-ad-gomis-dev}"
PASS=0
WARN=0
FAIL=0

pass() { echo -e "${GREEN}✓ PASS${NC}  $1"; PASS=$((PASS + 1)); }
warn() { echo -e "${YELLOW}! WARN${NC}  $1"; WARN=$((WARN + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}  $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "================================================="
echo " VALIDATION — Architecture 3-tiers (sandbox)"
echo "================================================="
echo "Namespace: $NAMESPACE"

if ! command -v oc >/dev/null 2>&1; then
  fail "oc CLI introuvable"
  echo ""
  exit 2
fi

if ! oc whoami >/dev/null 2>&1; then
  fail "Non connecté à OpenShift"
  echo ""
  exit 2
fi

echo -e "${BLUE}1) Ressources principales${NC}"
if oc get deploy mysql-db -n "$NAMESPACE" >/dev/null 2>&1; then
  ready=$(oc get deploy mysql-db -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "${ready:-0}" -ge 1 ]; then
    pass "mysql-db Ready"
  else
    fail "mysql-db non Ready"
  fi
else
  fail "deployment mysql-db absent"
fi

if oc get deploy web-fallback -n "$NAMESPACE" >/dev/null 2>&1; then
  ready=$(oc get deploy web-fallback -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "${ready:-0}" -ge 1 ]; then
    pass "web-fallback Ready"
  else
    warn "web-fallback present mais non Ready"
  fi
else
  fail "deployment web-fallback absent"
fi

if oc get vm vm2-web -n "$NAMESPACE" >/dev/null 2>&1; then
  vm2_status=$(oc get vm vm2-web -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "Unknown")
  if [ "$vm2_status" = "Running" ] || [ "$vm2_status" = "Starting" ]; then
    pass "vm2-web status=$vm2_status"
  else
    warn "vm2-web status=$vm2_status (fallback doit couvrir)"
  fi
else
  fail "vm2-web absente"
fi

if oc get vm vm1-firewall -n "$NAMESPACE" >/dev/null 2>&1; then
  vm1_status=$(oc get vm vm1-firewall -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "Unknown")
  if [ "$vm1_status" = "Running" ]; then
    pass "vm1-firewall Running"
  else
    warn "vm1-firewall status=$vm1_status (intermittence sandbox connue)"
  fi
else
  warn "vm1-firewall absente"
fi

echo ""
echo -e "${BLUE}2) Exposition web${NC}"
if oc get svc web-service-ha -n "$NAMESPACE" >/dev/null 2>&1; then
  pass "service web-service-ha present"
else
  fail "service web-service-ha absent"
fi

if oc get route route-web -n "$NAMESPACE" >/dev/null 2>&1; then
  pass "route route-web presente"
  ROUTE_URL=$(oc get route route-web -n "$NAMESPACE" -o jsonpath='{.spec.host}')
  code=$(curl -sk -o /tmp/validate_health.out -w '%{http_code}' "https://${ROUTE_URL}/health")
  body=$(cat /tmp/validate_health.out)
  if [ "$code" = "200" ]; then
    pass "GET /health => 200 ($body)"
  else
    fail "GET /health => $code"
  fi

  code=$(curl -sk -o /tmp/validate_users.out -w '%{http_code}' "https://${ROUTE_URL}/api/users")
  body=$(cat /tmp/validate_users.out)
  if [ "$code" = "200" ]; then
    pass "GET /api/users => 200 ($body)"
  else
    fail "GET /api/users => $code"
  fi
else
  fail "route route-web absente"
fi

if oc get endpoints web-service-ha -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses[0].ip}' >/tmp/validate_ep 2>/dev/null; then
  ep_ip=$(cat /tmp/validate_ep)
  if [ -n "$ep_ip" ]; then
    pass "endpoints web-service-ha actifs ($ep_ip)"
  else
    fail "endpoints web-service-ha vides"
  fi
else
  fail "impossible de lire endpoints web-service-ha"
fi

echo ""
echo -e "${BLUE}3) Vérification base de données${NC}"
if oc get svc mysql-db -n "$NAMESPACE" >/dev/null 2>&1; then
  svc_type=$(oc get svc mysql-db -n "$NAMESPACE" -o jsonpath='{.spec.type}')
  if [ "$svc_type" = "ClusterIP" ]; then
    pass "mysql-db non exposé publiquement (ClusterIP)"
  else
    fail "mysql-db type=$svc_type (devrait être ClusterIP)"
  fi
else
  fail "service mysql-db absent"
fi

echo ""
echo "================================================="
echo -e " Résultat: ${GREEN}${PASS} PASS${NC} / ${YELLOW}${WARN} WARN${NC} / ${RED}${FAIL} FAIL${NC}"
echo "================================================="

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Validation échouée: corriger les FAIL avant soutenance.${NC}"
  exit 1
fi

if [ "$WARN" -gt 0 ]; then
  echo -e "${YELLOW}Validation acceptable avec réserves (sandbox).${NC}"
  exit 0
fi

echo -e "${GREEN}Validation complète: architecture healthy/opérationnelle.${NC}"
exit 0
