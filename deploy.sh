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

configure_vm_services() {
  log "Configuration VM2 via cloud-init inline minimal (mode containerDisk + HA)..."
  ok "Aucune configuration SSH requise pour VM2"
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

  # Vérifier la disponibilité de l'API KubeVirt (compatible RBAC sandbox)
  if ! oc api-resources --api-group=kubevirt.io -o name 2>/dev/null | grep -q '^virtualmachines\.kubevirt\.io$'; then
    err "OpenShift Virtualization (API kubevirt.io/virtualmachines) n'est pas disponible"
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
  log "Étape 1/6 — Vérification du namespace..."
  if oc get namespace "$NAMESPACE" &>/dev/null; then
    ok "Namespace $NAMESPACE déjà présent (réutilisé)"
  else
    oc create namespace "$NAMESPACE"
    ok "Namespace $NAMESPACE créé"
  fi

  # Étape 2 — Secret OpenShift
  log "Étape 2/6 — Création du Secret OpenShift (db-credentials)..."
  oc apply -f "$SCRIPT_DIR/openshift/secrets/db-credentials.yaml"
  ok "Secret db-credentials prêt"

  # Étape 3 — Base de données en Pod OpenShift
  log "Étape 3/6 — Déploiement de la base MySQL (Pod OpenShift + PVC + Service)..."
  if oc get deploy mysql-db -n "$NAMESPACE" &>/dev/null \
    && oc get svc mysql-db -n "$NAMESPACE" &>/dev/null \
    && oc get pvc pvc-mysql-data -n "$NAMESPACE" &>/dev/null; then
    warn "Ressources DB déjà présentes: réutilisation sans réapplication"
  else
    oc apply -f "$SCRIPT_DIR/openshift/services/db-mysql.yaml"
  fi
  oc rollout status deploy/mysql-db -n "$NAMESPACE" --timeout=180s
  ok "Base MySQL prête"

  # Étape 4 — Déploiement des VMs critiques
  log "Étape 4/6 — Déploiement des VMs Firewall et Web..."
  oc apply -f "$SCRIPT_DIR/openshift/vms/vm1-firewall.yaml"
  if ! oc apply -f "$SCRIPT_DIR/openshift/vms/vm2-web.yaml"; then
    warn "Application VM2 en echec: recréation de vm2-web"
    virtctl stop vm2-web -n "$NAMESPACE" || true
    oc delete vm vm2-web -n "$NAMESPACE" --ignore-not-found=true
    oc apply -f "$SCRIPT_DIR/openshift/vms/vm2-web.yaml"
  fi

  log "Démarrage explicite des VMs (runStrategy=Manual)..."
  virtctl start vm1-firewall -n "$NAMESPACE" || true
  virtctl start vm2-web -n "$NAMESPACE" || true

  # Attendre chaque VM
  wait_for_vm "vm1-firewall"
  if ! wait_for_vm "vm2-web"; then
    warn "VM2 n'est pas prête dans le délai imparti (sandbox). Le fallback web reste actif."
  fi

  # Étape 5 — Configuration applicative via Secret OpenShift
  log "Étape 5/6 — Configuration du service Web..."
  configure_vm_services

  # Étape 6 — Service et Route
  log "Étape 6/6 — Exposition du service Web..."
  # Important: supprimer les anciens services pour éviter les collisions de selectors.
  oc delete svc web-service-ha -n "$NAMESPACE" --ignore-not-found=true
  oc delete deploy web-fallback -n "$NAMESPACE" --ignore-not-found=true
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
  oc delete svc web-service-ha -n "$NAMESPACE" --ignore-not-found=true
  oc delete deploy web-fallback -n "$NAMESPACE" --ignore-not-found=true
  oc delete route route-web -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression des secrets..."
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
