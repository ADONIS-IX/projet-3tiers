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

NAMESPACE="projet-3tiers"
TIMEOUT_VM=300    # secondes d'attente max par VM
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

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

  # Vérifier que Multus est disponible
  if ! oc get crd network-attachment-definitions.k8s.cni.cncf.io &>/dev/null; then
    err "Multus CNI n'est pas installé (requis pour les réseaux LAN/DMZ)"
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

  # Étape 2 — Réseaux
  log "Étape 2/6 — Création des segments réseau (LAN + DMZ)..."
  oc apply -f "$SCRIPT_DIR/openshift/network/nad-lan.yaml"
  oc apply -f "$SCRIPT_DIR/openshift/network/nad-dmz.yaml"
  oc get network-attachment-definitions -n "$NAMESPACE"
  ok "Réseaux LAN (192.168.10.0/24) et DMZ (192.168.100.0/24) créés"

  # Étape 3 — Stockage persistant pour VM3
  log "Étape 3/6 — Création du volume persistant MySQL..."
  oc apply -f "$SCRIPT_DIR/openshift/vms/vm3-db.yaml"
  # Attendre que le PVC soit lié
  local pvc_timeout=60; local pvc_elapsed=0
  while [ $pvc_elapsed -lt $pvc_timeout ]; do
    local pvc_phase
    pvc_phase=$(oc get pvc pvc-mysql-data -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    [ "$pvc_phase" = "Bound" ] && break
    echo -n "."; sleep 5; ((pvc_elapsed += 5))
  done
  ok "PVC MySQL lié"

  # Étape 4 — Déploiement des VMs
  log "Étape 4/6 — Déploiement des 3 VMs..."
  oc apply -f "$SCRIPT_DIR/openshift/vms/vm1-firewall.yaml"
  oc apply -f "$SCRIPT_DIR/openshift/vms/vm2-web.yaml"

  # Attendre chaque VM
  wait_for_vm "vm1-firewall"
  wait_for_vm "vm2-web"
  wait_for_vm "vm3-db"

  # Étape 5 — Service et Route
  log "Étape 5/6 — Exposition du service Web..."
  oc apply -f "$SCRIPT_DIR/openshift/services/svc-web.yaml"
  local route_url
  route_url=$(oc get route route-web -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "N/A")
  ok "Route Web : https://$route_url"

  # Étape 6 — Récapitulatif
  log "Étape 6/6 — Vérification finale..."
  status

  echo ""
  echo "========================================================"
  echo -e "${GREEN} Déploiement terminé avec succès !${NC}"
  echo ""
  echo "  Prochaine étape — Validation :"
  echo "  virtctl ssh admin@vm1-firewall -n $NAMESPACE"
  echo "  bash /root/validate.sh"
  echo "========================================================"
}

# ── Statut des VMs ───────────────────────────────────────────────────────────
status() {
  log "État des VMs dans $NAMESPACE :"
  echo ""
  oc get vmi -n "$NAMESPACE" 2>/dev/null || warn "Aucune VMI trouvée"
  echo ""
  log "Réseaux :"
  oc get network-attachment-definitions -n "$NAMESPACE" 2>/dev/null || warn "Aucun réseau trouvé"
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
  oc delete vm vm1-firewall vm2-web vm3-db -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression des réseaux..."
  oc delete network-attachment-definition reseau-lan reseau-dmz -n "$NAMESPACE" --ignore-not-found=true

  log "Suppression des services..."
  oc delete svc,route --all -n "$NAMESPACE" --ignore-not-found=true

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
