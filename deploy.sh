#!/bin/bash
# =============================================================================
# deploy.sh — Déploiement complet de l'architecture 3-tiers sur OpenShift
#
# Usage :
#   ./deploy.sh              # Déploiement complet
#   ./deploy.sh --destroy    # Supprimer toutes les ressources
#   ./deploy.sh --status     # Vérifier l'état des VMs
#
# Prérequis :
#   - oc CLI installé et authentifié (oc login ...)
#   - virtctl installé
#   - OpenShift Virtualization (KubeVirt) actif sur le cluster
# =============================================================================

set -euo pipefail

NAMESPACE="ad-gomis-dev"
TIMEOUT_VM=300    # secondes d'attente max par VM
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

get_secret_value() {
  local key="$1"
  oc get secret db-credentials -n "$NAMESPACE" -o "jsonpath={.data.${key}}" | base64 -d
}

configure_vm_services() {
  log "Injection des secrets OpenShift dans VM2..."

  local db_host db_port db_name db_user db_pass
  db_host="$(get_secret_value DB_HOST)"
  db_port="$(get_secret_value DB_PORT)"
  db_name="$(get_secret_value DB_NAME)"
  db_user="$(get_secret_value DB_USER)"
  db_pass="$(get_secret_value DB_PASS)"

  local vm2_env
  vm2_env=$(cat <<EOF
DB_HOST=$db_host
DB_PORT=$db_port
DB_NAME=$db_name
DB_USER=$db_user
DB_PASS=$db_pass
EOF
)

  printf '%s\n' "$vm2_env" | virtctl ssh admin@vm2-web -n "$NAMESPACE" -- "cat > /root/db-secrets.env && chmod 600 /root/db-secrets.env"

  log "Exécution du script applicatif sur VM2..."
  virtctl ssh admin@vm2-web -n "$NAMESPACE" -- "TP3_SECRET_ENV_PATH=/root/db-secrets.env bash /root/vm2-setup.sh"

  ok "Service VM2 (Nginx+Node.js) configure"
}

# ── Vérifications préalables ─────────────────────────────────────────────────
check_prerequisites() {
  log "Vérification des prérequis..."

  for tool in oc virtctl kubectl; do
    if ! command -v $tool &>/dev/null; then
      err "$tool n'est pas installé ou absent du PATH"
      exit 1
    fi
  done

  if ! oc whoami &>/dev/null; then
    err "Non connecté à OpenShift. Exécutez : oc login --server=https://api.CLUSTER:6443"
    exit 1
  fi

  # Vérifier que OpenShift Virtualization est installé
  if ! oc get crd virtualmachines.kubevirt.io &>/dev/null; then
    err "OpenShift Virtualization (KubeVirt) n'est pas installé sur ce cluster"
    exit 1
  fi

  ok "Tous les prérequis sont satisfaits"
  log "Cluster   : $(oc whoami --show-server)"
  log "Utilisateur: $(oc whoami)"
}

# ── Attendre qu'une VM soit en état Running ──────────────────────────────────
wait_for_vm() {
  local vm_name="$1"
  local elapsed=0
  log "Attente du démarrage de $vm_name (max ${TIMEOUT_VM}s)..."

  while [ $elapsed -lt $TIMEOUT_VM ]; do
    local phase
    phase=$(oc get vmi "$vm_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [ "$phase" = "Running" ]; then
      ok "$vm_name est Running"
      return 0
    fi
    echo -n "."
    sleep 5
    ((elapsed += 5))
  done

  echo ""
  err "$vm_name n'a pas démarré dans les ${TIMEOUT_VM}s (phase actuelle : $phase)"
  return 1
}

# ── Déploiement ──────────────────────────────────────────────────────────────
deploy() {
  echo ""
  echo "========================================================"
  echo "  Déploiement — Architecture 3-tiers sur OpenShift"
  echo "========================================================"
  echo ""

  check_prerequisites

  # Étape 1 — Namespace
  log "Étape 1/6 — Création du namespace..."
  oc apply -f "$SCRIPT_DIR/openshift/namespace.yaml"
  ok "Namespace $NAMESPACE prêt"

  # Étape 2 — Secret OpenShift
  log "Étape 2/6 — Création du Secret OpenShift (db-credentials)..."
  oc apply -f "$SCRIPT_DIR/openshift/secrets/db-credentials.yaml"
  ok "Secret db-credentials prêt"

  # Étape 3 — Base de données en Pod OpenShift
  log "Étape 3/6 — Déploiement de la base MySQL (Pod OpenShift + PVC + Service)..."
  oc apply -f "$SCRIPT_DIR/openshift/services/db-mysql.yaml"
  oc rollout status deploy/mysql-db -n "$NAMESPACE" --timeout=180s
  ok "Base MySQL prête"

  # Étape 4 — Déploiement des VMs critiques
  log "Étape 4/6 — Déploiement des VMs Firewall et Web..."
  oc apply -f "$SCRIPT_DIR/openshift/vms/vm1-firewall.yaml"
  oc apply -f "$SCRIPT_DIR/openshift/vms/vm2-web.yaml"

  log "Démarrage explicite des VMs (runStrategy=Manual)..."
  virtctl start vm1-firewall -n "$NAMESPACE" || true
  virtctl start vm2-web -n "$NAMESPACE" || true

  # Attendre chaque VM
  wait_for_vm "vm1-firewall"
  wait_for_vm "vm2-web"

  # Étape 5 — Configuration applicative via Secret OpenShift
  log "Étape 5/6 — Configuration du service Web..."
  configure_vm_services

  # Étape 6 — Service et Route
  log "Étape 6/6 — Exposition du service Web..."
  oc apply -f "$SCRIPT_DIR/openshift/services/svc-web.yaml"
  local route_url
  route_url=$(oc get route route-web -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
  ok "Route Web : https://$route_url"

  # Vérification finale
  log "Vérification finale..."
  status

  echo ""
  echo "========================================================"
  echo -e "${GREEN} Déploiement terminé avec succès !${NC}"
  echo ""
  echo "  Prochaine étape — Validation :"
  echo "  virtctl ssh admin@vm1-firewall -n $NAMESPACE"
  echo "  curl -k https://$route_url/health"
  echo "========================================================"
}

# ── Statut des VMs ───────────────────────────────────────────────────────────
status() {
  log "État des VMs dans $NAMESPACE :"
  echo ""
  oc get vmi -n "$NAMESPACE" 2>/dev/null || warn "Aucune VMI trouvée"
  echo ""
  log "Base de données (Pod OpenShift) :"
  oc get deploy,pod,svc,pvc -n "$NAMESPACE" -l role=db 2>/dev/null || warn "Aucune ressource DB trouvée"
  echo ""
  log "Services et Routes :"
  oc get svc,route -n "$NAMESPACE" 2>/dev/null || warn "Aucun service trouvé"
}

# ── Suppression ──────────────────────────────────────────────────────────────
destroy() {
  warn "ATTENTION : Suppression de toutes les ressources du namespace $NAMESPACE"
  read -r -p "Confirmer la suppression ? (oui/non) : " confirm
  [ "$confirm" != "oui" ] && { log "Annulé."; exit 0; }

  log "Arrêt et suppression des VMs..."
  oc delete vm vm1-firewall vm2-web -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression de la base MySQL (Pod OpenShift)..."
  oc delete deploy mysql-db -n "$NAMESPACE" --ignore-not-found=true
  oc delete svc mysql-db -n "$NAMESPACE" --ignore-not-found=true
  oc delete configmap mysql-init-sql -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression des services..."
  oc delete svc svc-web -n "$NAMESPACE" --ignore-not-found=true
  oc delete route route-web -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression du secret db-credentials..."
  oc delete secret db-credentials -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression du PVC MySQL..."
  oc delete pvc pvc-mysql-data -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression du namespace..."
  oc delete namespace "$NAMESPACE" --ignore-not-found=true

  ok "Toutes les ressources supprimées"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  --destroy) destroy ;;
  --status)  status  ;;
  --help|-h)
    echo "Usage : $0 [--destroy | --status | --help]"
    echo "  (sans argument) : déploiement complet"
    ;;
  "") deploy ;;
  *) err "Option inconnue : $1"; exit 1 ;;
esac
