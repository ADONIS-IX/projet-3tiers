# Projet de Fin de Module — Architecture 3-tiers sur OpenShift Virtualization

## Vue d'ensemble

Ce projet déploie une architecture réseau **3-tiers virtualisée** sur **OpenShift Virtualization (KubeVirt)** avec isolation réseau complète via iptables.

```text
Internet (NAT)
      │
   [VM1 — Firewall/Passerelle]   eth0=WAN | eth1=LAN | eth2=DMZ
      │                    │
   Réseau LAN          Réseau DMZ
  192.168.10.0/24    192.168.100.0/24
      │                    │
  [VM3 — MySQL]       [VM2 — Nginx + Node.js]
  192.168.10.10       192.168.100.10
```

## Structure du dépôt

```text
projet-3tiers/
├── .github/workflows/ci.yml      # Pipeline CI/CD GitHub Actions
├── openshift/
│   ├── namespace.yaml            # Namespace OpenShift
│   ├── network/
│   │   ├── nad-lan.yaml          # NetworkAttachmentDefinition LAN
│   │   └── nad-dmz.yaml          # NetworkAttachmentDefinition DMZ
│   └── vms/
│       ├── vm1-firewall.yaml     # VM1 Passerelle / Firewall
│       ├── vm2-web.yaml          # VM2 Serveur Web (Nginx + Node.js)
│       └── vm3-db.yaml           # VM3 Serveur Base de Données (MySQL)
├── scripts/
│   ├── vm1-iptables.sh           # Règles iptables VM1
│   ├── vm2-setup.sh              # Installation Nginx + Node.js
│   ├── vm3-mysql.sh              # Installation MySQL
│   └── validate.sh               # Script de validation finale
└── app/
    ├── server.js                 # Application Node.js
    └── package.json
```

## Prérequis

- OpenShift 4.x avec OpenShift Virtualization (KubeVirt) activé
- Plugin Multus CNI installé (inclus par défaut dans OpenShift Virtualization)
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

### Étape 2 — Créer les réseaux virtuels

```bash
# Créer les NetworkAttachmentDefinitions
oc apply -f openshift/network/nad-lan.yaml
oc apply -f openshift/network/nad-dmz.yaml

# Vérifier
oc get network-attachment-definitions -n projet-3tiers
```

### Étape 2b — Créer le Secret OpenShift pour la base

```bash
oc apply -f openshift/secrets/db-credentials.yaml
```

### Étape 3 — Déployer les VMs

```bash
# Important : déployer dans cet ordre
oc apply -f openshift/vms/vm1-firewall.yaml
oc apply -f openshift/vms/vm2-web.yaml
oc apply -f openshift/vms/vm3-db.yaml

# Suivre le démarrage des VMs
oc get vmi -n projet-3tiers -w
```

### Étape 4 — Se connecter aux VMs (via virtctl)

```bash
# Installer virtctl
oc get ConsoleCLIDownload virtctl-clidownloads -o json | jq -r '.spec.links[0].href'

# Connexion SSH aux VMs
virtctl ssh admin@vm1-firewall -n projet-3tiers
virtctl ssh admin@vm2-web      -n projet-3tiers
virtctl ssh admin@vm3-db       -n projet-3tiers
```

### Étape 5 — Configurer les services (si cloud-init n'est pas utilisé)

```bash
# Injecter les secrets puis configurer VM2 et VM3
./deploy.sh

# Sur VM1 : Configurer iptables
virtctl ssh admin@vm1-firewall -n projet-3tiers -- 'bash /root/iptables-setup.sh'

# Sur VM2 : Installer Nginx + Node.js
virtctl ssh admin@vm2-web -n projet-3tiers -- 'bash /root/vm2-setup.sh'

# Sur VM3 : Installer MySQL
virtctl ssh admin@vm3-db -n projet-3tiers -- 'bash /root/vm3-mysql.sh'
```

### Étape 6 — Valider l'architecture

```bash
# Depuis VM1, exécuter le script de validation
virtctl ssh admin@vm1-firewall -n projet-3tiers -- 'bash /root/validate.sh'
```

## Règles iptables — Politique de sécurité

| # | Source | Destination | Port | Action | Justification |
| --- | --- | --- | --- | --- | --- |
| R1 | Internet (WAN) | LAN (VM3 BD) | Tous | **DROP** | BD non exposée à Internet |
| R2 | DMZ (VM2 Web) | LAN (VM3 BD) | 3306 | **ACCEPT** | Seul flux applicatif Web -> BD |
| R2b | DMZ (VM2 Web) | LAN (VM3 BD) | Autres | **DROP** | Isolation stricte Web/BD |
| R3 | LAN (VM3 BD) | DMZ (VM2 Web) | 80,443,3000 | ACCEPT | BD peut consulter Web |
| R3 | LAN (VM3 BD) | Internet | Tous | ACCEPT | BD peut accéder Internet |
| R4 | Internet | DMZ (VM2 Web) | 80, 443 | ACCEPT | Accès Web public |
| R5 | DMZ (VM2 Web) | Internet | Tous | ACCEPT | Web peut accéder Internet |

## Vérification de la connectivité

```bash
# Test 1 : Accès Web depuis l'extérieur (R4)
curl http://<IP_EXTERNE>/

# Test 2 : VM3 ne doit pas être accessible depuis Internet (R1)
nc -zv <IP_EXTERNE> 3306   # doit échouer

# Test 3 : VM2 accède à VM3 uniquement sur 3306 (R2)
# Depuis VM2 :
nc -zv 192.168.10.10 3306  # doit réussir
nc -zv 192.168.10.10 22    # doit échouer

# Test 4 : VM3 peut joindre VM2 (R3)
# Depuis VM3 :
curl http://192.168.100.10  # doit réussir
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
│   └── feature/vm3-mysql
```

---

## Note

Projet réalisé dans le cadre du TP Architecture Réseau Virtualisée.
