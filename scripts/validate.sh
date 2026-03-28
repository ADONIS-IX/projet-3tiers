#!/bin/bash
# =============================================================================
# Script de validation de l'architecture 3-tiers
# À exécuter depuis VM1 (Firewall / Passerelle)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

IP_VM2="192.168.100.10"
IP_VM3="192.168.10.10"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local cmd="$2"
  local expected_exit="${3:-0}"
  echo -n "  [TEST] $desc ... "
  if eval "$cmd" &>/dev/null; then
    if [ "$expected_exit" -eq 0 ]; then
      echo -e "${GREEN}✓ PASS${NC}"
      ((PASS++))
    else
      echo -e "${RED}✗ FAIL (devrait être inaccessible)${NC}"
      ((FAIL++))
    fi
  else
    if [ "$expected_exit" -ne 0 ]; then
      echo -e "${GREEN}✓ PASS (correctement bloqué)${NC}"
      ((PASS++))
    else
      echo -e "${RED}✗ FAIL${NC}"
      ((FAIL++))
    fi
  fi
}

echo ""
echo "================================================="
echo " VALIDATION — Architecture 3-tiers"
echo "================================================="

echo ""
echo -e "${YELLOW}1. Connectivité de base${NC}"
check "Ping VM2 (Web) depuis VM1"   "ping -c 2 -W 2 $IP_VM2"
check "Ping VM3 (BD)  depuis VM1"   "ping -c 2 -W 2 $IP_VM3"

echo ""
echo -e "${YELLOW}2. Accès Web (port 80/443)${NC}"
check "HTTP vers VM2 (port 80)"     "curl -s -o /dev/null -w '%{http_code}' http://$IP_VM2 | grep -q '200\|301'"
check "API /health/db sur VM2"      "curl -s http://$IP_VM2/health/db | grep -q 'OK'"

echo ""
echo -e "${YELLOW}3. Isolation LAN — Serveur BD (R1 + R2)${NC}"
check "VM2 (DMZ) -> VM3 (LAN) sur 3306 autorisé" \
  "ssh -o StrictHostKeyChecking=no admin@$IP_VM2 'nc -z -w 3 $IP_VM3 3306'"
check "VM2 (DMZ) -> VM3 (LAN) sur 22 bloqué" \
  "ssh -o StrictHostKeyChecking=no admin@$IP_VM2 'nc -z -w 3 $IP_VM3 22'" 1

echo ""
echo -e "${YELLOW}4. Accès Internet${NC}"
check "VM2 (DMZ) -> Internet (R5)" \
  "ssh -o StrictHostKeyChecking=no admin@$IP_VM2 'curl -s --max-time 5 https://example.com | grep -q Example'"
check "VM3 (LAN) -> Internet (R3)" \
  "ssh -o StrictHostKeyChecking=no admin@$IP_VM3 'curl -s --max-time 5 https://example.com | grep -q Example'"

echo ""
echo "================================================="
echo -e " Résultats : ${GREEN}${PASS} PASS${NC} / ${RED}${FAIL} FAIL${NC}"
echo "================================================="

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN} Architecture validée avec succès !${NC}"
  exit 0
else
  echo -e "${RED} $FAIL test(s) en échec — vérifiez la configuration.${NC}"
  exit 1
fi
