# Projet de Fin de Module — Architecture 3-tiers Hybride sur OpenShift

## Vue d'ensemble

Ce projet déploie une architecture **3-tiers hybride** sur OpenShift:

- Tiers 1: VM1 Firewall (KubeVirt)
- Tiers 2: VM2 Web (KubeVirt)
- Tiers 3: Base MySQL en Pod natif OpenShift

```text
Internet
    |
Route OpenShift (TLS edge)
    |
Service svc-web
    |
VM2 Web (Nginx + Node.js)
    |
Service mysql-db
    |
Pod MySQL + PVC

VM1 Firewall est deployee comme composant critique de securite.
```

## Structure du dépôt

```text
projet-3tiers/
├── .github/workflows/ci.yml      # Pipeline CI/CD GitHub Actions
├── openshift/
│   ├── namespace.yaml            # Namespace OpenShift
│   ├── services/
│   │   ├── db-mysql.yaml         # Deployment+Service+PVC MySQL (Pod OpenShift)
│   │   └── svc-web.yaml          # Service+Route Web
│   └── vms/
│       ├── vm1-firewall.yaml     # VM1 Passerelle / Firewall
│       ├── vm2-web.yaml          # VM2 Serveur Web (Nginx + Node.js)
│       └── (retire)              # VM3 remplacee par DB Pod OpenShift
├── scripts/
│   ├── vm1-iptables.sh           # Règles iptables VM1
│   ├── vm2-setup.sh              # Installation Nginx + Node.js
│   ├── vm3-mysql.sh              # Script historique (non utilise en mode hybride)
│   └── validate.sh               # Script de validation finale
└── app/
    ├── server.js                 # Application Node.js
    └── package.json
```

## Prérequis

- OpenShift 4.x avec OpenShift Virtualization (KubeVirt) activé
- `oc` CLI configuré et connecté au cluster
- Accès cluster-admin ou permissions sur le namespace

## Déploiement — Guide pas à pas

### Étape 1 — Préparer l'environnement OpenShift

```bash
# Connexion au cluster
oc login --server=https://api.VOTRE_CLUSTER:6443

# Créer le namespace
oc apply -f openshift/namespace.yaml

# Vérifier que OpenShift Virtualization est actif
oc get csv -n openshift-cnv | grep kubevirt
```

### Étape 2 — Créer le Secret OpenShift pour la base

```bash
oc apply -f openshift/secrets/db-credentials.yaml
```

### Étape 3 — Déployer la base MySQL (Pod OpenShift)

```bash
oc apply -f openshift/services/db-mysql.yaml
oc rollout status deploy/mysql-db -n ad-gomis-dev
```

### Étape 4 — Déployer les VMs critiques

```bash
oc apply -f openshift/vms/vm1-firewall.yaml
oc apply -f openshift/vms/vm2-web.yaml

# runStrategy=Manual en sandbox
virtctl start vm1-firewall -n ad-gomis-dev
virtctl start vm2-web -n ad-gomis-dev

# Suivre le démarrage des VMs
oc get vmi -n ad-gomis-dev -w
```

### Étape 5 — Se connecter aux VMs (via virtctl)

```bash
# Installer virtctl
oc get ConsoleCLIDownload virtctl-clidownloads -o json | jq -r '.spec.links[0].href'

# Connexion SSH aux VMs
virtctl ssh admin@vm1-firewall -n ad-gomis-dev
virtctl ssh admin@vm2-web      -n ad-gomis-dev
```

### Étape 6 — Configurer le service Web (si cloud-init n'est pas utilisé)

```bash
# Injecter les secrets puis configurer VM2
./deploy.sh

# Sur VM1 : Configurer iptables
virtctl ssh admin@vm1-firewall -n ad-gomis-dev -- 'bash /root/iptables-setup.sh'

# Sur VM2 : Installer Nginx + Node.js
virtctl ssh admin@vm2-web -n ad-gomis-dev -- 'bash /root/vm2-setup.sh'
```

### Étape 7 — Valider l'architecture

```bash
# Vérification des ressources
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev

# Vérifier l'URL publique
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
```

## Règles iptables — Politique de sécurité

| # | Source | Destination | Port | Action | Justification |
| --- | --- | --- | --- | --- | --- |
| R1 | Internet | VM2 Web | 80/443 | ACCEPT | Accès applicatif public via Route |
| R2 | VM2 Web | Service mysql-db | 3306 | ACCEPT | Flux applicatif Web -> DB |
| R3 | Internet | Pod MySQL | Tous | DROP implicite | DB non exposée publiquement |

## Vérification de la connectivité

```bash
# Test 1 : Accès Web depuis l'extérieur (R4)
curl http://<IP_EXTERNE>/

# Test 2 : MySQL ne doit pas être exposé publiquement
oc get svc -n ad-gomis-dev | grep mysql-db
# attendu: ClusterIP uniquement

# Test 3 : Santé applicative
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
curl -k "https://${ROUTE_URL}/api/users"
```

## Intégration GitHub

### Initialisation du dépôt

```bash
git init
git remote add origin https://github.com/ADONIS-IX/projet-3tiers.git
git add .
git commit -m "feat: architecture 3-tiers initiale"
git push -u origin main
```

### Conventions de commit

```text
feat:  nouvelle fonctionnalité
fix:   correction de bug
docs:  documentation
chore: maintenance
```

## Partie 4 — Structure recommandée des branches GitHub

```text
main          ← production stable
├── develop   ← intégration
│   ├── feature/vm1-iptables
│   ├── feature/vm2-nginx-nodejs
│   └── feature/db-pod-openshift
```

---

## Note

Projet réalisé dans le cadre du TP Architecture Réseau Virtualisée.
