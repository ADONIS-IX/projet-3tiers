# Rapport Academique - Architecture Hybride Validee

## 1. Contexte pedagogique

Suite a validation du professeur, l'architecture cible est adaptee en:

- VM1: Firewall (OpenShift Virtualization)
- VM2: Web (Nginx + Node.js sur OpenShift Virtualization)
- Tier DB: Pod MySQL natif OpenShift

Cette adaptation maintient:

- la virtualisation des tiers critiques (securite + presentation)
- la separation des responsabilites applicatives
- la persistance des donnees (PVC)
- l'exposition Web via Service + Route

## 2. Architecture retenue

```text
Internet
  |
Route OpenShift (TLS edge)
  |
Service svc-web
  |
VM2 Web (Nginx -> Node.js)
  |
Service mysql-db (ClusterIP)
  |
Pod MySQL + PVC

VM1 Firewall (VM critique) est deployee et administree comme composant securite.
```

## 3. Composants deployes

- Namespace: ad-gomis-dev
- Secret: db-credentials
- VM1: vm1-firewall
- VM2: vm2-web
- DB Pod: Deployment mysql-db + Service mysql-db + PVC pvc-mysql-data
- Exposition Web: Service svc-web + Route route-web

## 4. Fichiers techniques remis

- openshift/vms/vm1-firewall.yaml
- openshift/vms/vm2-web.yaml
- openshift/services/db-mysql.yaml
- openshift/services/svc-web.yaml
- openshift/secrets/db-credentials.yaml
- openshift/kustomization.yaml
- scripts/vm2-setup.sh
- deploy.sh

## 5. Procedure de deploiement

```bash
oc project ad-gomis-dev
oc apply -k openshift

# Demarrer les VMs (runStrategy Manual en sandbox)
virtctl start vm1-firewall -n ad-gomis-dev
virtctl start vm2-web -n ad-gomis-dev
```

## 6. Verification fonctionnelle

```bash
# Etat infrastructure
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev

# Verifier DB
oc rollout status deploy/mysql-db -n ad-gomis-dev
oc get svc mysql-db -n ad-gomis-dev

# Verifier Web
oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}{"\n"}'

# Tester API
curl -k "https://$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')/health"
curl -k "https://$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')/api/users"
```

## 7. Captures d'ecran essentielles a joindre

1. Capture 01 - Validation RBAC et contexte

```bash
oc whoami
oc project -q
```

Nom conseille: capture-01-contexte-cluster.png

1. Capture 02 - Etat complet des ressources

```bash
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
```

Nom conseille: capture-02-etat-ressources.png

1. Capture 03 - VM1 et VM2 demarrees

```bash
oc get vm,vmi -n ad-gomis-dev
```

Nom conseille: capture-03-vms-running.png

1. Capture 04 - Base en Pod OpenShift

```bash
oc get deploy,pod,svc,pvc -n ad-gomis-dev | grep -E 'mysql-db|pvc-mysql-data'
```

Nom conseille: capture-04-db-pod-pvc-service.png

1. Capture 05 - Route publique

```bash
oc get route route-web -n ad-gomis-dev
```

Nom conseille: capture-05-route-web.png

1. Capture 06 - Healthcheck applicatif

```bash
curl -k "https://$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')/health"
```

Nom conseille: capture-06-healthcheck.png

1. Capture 07 - API et lecture BD

```bash
curl -k "https://$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')/api/users"
```

Nom conseille: capture-07-api-users.png

## 8. Justification academique de l'adaptation

- Respect des objectifs pedagogiques centraux:
  - virtualisation de composants critiques
  - orchestration OpenShift
  - separation des tiers applicatifs
  - persistance et exposition de services
- Adaptation validee par le professeur pour contourner les contraintes sandbox (quota VM, restrictions NAD/Multus).

## 9. Limites et ameliorations

- En environnement non sandbox (droits complets), retour possible vers segmentation LAN/DMZ Multus stricte.
- Ajout recommande: NetworkPolicy pour limiter l'acces au Service mysql-db au seul composant web.

## 10. Conclusion

L'architecture hybride VM+Pod repond aux contraintes reelles de l'environnement tout en conservant la logique 3-tiers et les objectifs pedagogiques attendus.
