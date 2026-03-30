# Guide D'Execution De Mise En Oeuvre

Ce guide fournit une procedure de demonstration complete pour l'architecture validee:

- VM1 Firewall (KubeVirt)
- VM2 Web (KubeVirt, mode secours containerDisk)
- DB MySQL en Pod OpenShift

Objectif: executer la procedure, verifier le resultat et produire les captures essentielles a inserer dans le rapport academique.

## 1. Pre-requis

- Etre connecte au cluster OpenShift
- Etre positionne dans le namespace `ad-gomis-dev`
- Avoir `oc` et `virtctl` disponibles
- Avoir `kubectl` disponible si vous utilisez `./deploy.sh` en mode deploiement complet
- Etre dans la racine du projet

Commandes de verification:

```bash
oc whoami
oc project -q
command -v oc
command -v virtctl
command -v kubectl || echo "kubectl optionnel (requis pour ./deploy.sh complet)"
```

## 2. Sequence d'execution

### Etape 1 - Contexte Et Acces

```bash
oc whoami
oc project ad-gomis-dev
oc project -q
```

Resultat attendu:

- utilisateur correct
- namespace actif: ad-gomis-dev

Capture essentielle:

- ID: CAP-01
- Nom fichier conseille: `cap-01-contexte-rbac-namespace.png`
- Contenu visible: user + namespace

### Etape 2 - Deploiement Des Ressources

```bash
oc apply -k openshift
```

Si vous obtenez un timeout (API:6443), executer ce diagnostic rapide:

```bash
oc whoami --show-server
getent hosts api.rm2.thpm.p1.openshiftapps.com
curl -k --connect-timeout 8 -I https://api.rm2.thpm.p1.openshiftapps.com:6443/readyz
```

Interpretation:

- DNS OK + curl timeout: connectivite reseau/VPN vers le cluster indisponible
- DNS KO: probleme de resolution locale

Relance recommandee une fois la connectivite retablie:

```bash
oc login --server=https://api.rm2.thpm.p1.openshiftapps.com:6443
oc project ad-gomis-dev
oc apply -k openshift
```

Resultat attendu:

- secret configure/created
- mysql-db (configmap/deployment/service/pvc) applique
- vm1-firewall et vm2-web appliquees
- web-service-ha + web-fallback + route-web appliquees

Capture essentielle:

- ID: CAP-02
- Nom fichier conseille: `cap-02-apply-kustomize.png`
- Contenu visible: resume `created/configured`

### Etape 3 - Demarrage Des VMs Critiques

```bash
virtctl start vm1-firewall -n ad-gomis-dev || true
virtctl start vm2-web -n ad-gomis-dev || true
oc get vm,vmi -n ad-gomis-dev
```

Resultat attendu:

- vm1-firewall: Running
- vm2-web: Running

Important sandbox:

- la route continue de repondre via `web-fallback`, meme en cas d'arret/instabilite de vm2-web
- vm1-firewall peut s'arreter de facon intermittente (runStrategy Manual), relancer avec `virtctl start vm1-firewall -n ad-gomis-dev`
- vm2-web peut aussi s'arreter en contexte sandbox, relancer avec `virtctl start vm2-web -n ad-gomis-dev`
- pour maintenir VM1 active automatiquement pendant la demo: `./scripts/watch-vm1.sh ad-gomis-dev 15`
- pour maintenir VM2 active automatiquement pendant la demo: `./scripts/watch-vm2.sh ad-gomis-dev 20`

Capture essentielle:

- ID: CAP-03
- Nom fichier conseille: `cap-03-vm-vmi-running.png`
- Contenu visible: etat Running

### Etape 4 - Verification Du Tier Base De Donnees

```bash
oc rollout status deploy/mysql-db -n ad-gomis-dev
oc get deploy,pod,svc,pvc -n ad-gomis-dev | grep -E 'mysql-db|pvc-mysql-data'
```

Resultat attendu:

- deployment mysql-db successful
- pod mysql Running
- service mysql-db en ClusterIP
- pvc-mysql-data Bound (selon delai du provisioner)

Capture essentielle:

- ID: CAP-04
- Nom fichier conseille: `cap-04-db-pod-service-pvc.png`
- Contenu visible: deployment/pod/service/pvc

### Etape 5 - Verification Route Web

```bash
oc get route route-web -n ad-gomis-dev
```

Si la route affiche "Application is not available", appliquer ce correctif:

```bash
virtctl start vm2-web -n ad-gomis-dev || true
oc delete svc web-service-ha -n ad-gomis-dev --ignore-not-found=true
oc apply -f openshift/services/svc-web.yaml
oc get endpoints web-service-ha -n ad-gomis-dev -o yaml
```

Verification attendue apres correctif:

- le service `web-service-ha` existe
- au moins une entree apparait dans `subsets.addresses` des endpoints

Resultat attendu:

- host route-web present
- termination TLS edge

Capture essentielle:

- ID: CAP-05
- Nom fichier conseille: `cap-05-route-web.png`
- Contenu visible: host de la route

### Etape 6 - Test Applicatif Health

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
```

Resultat attendu:

- JSON de statut (`ok` ou `OK`) selon la cible active (`vm2-web` ou `web-fallback`)

Capture essentielle:

- ID: CAP-06
- Nom fichier conseille: `cap-06-health-endpoint.png`
- Contenu visible: sortie JSON health

### Etape 7 - Test Applicatif Donnees

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/api/users"
```

Resultat attendu:

- en mode sandbox actuel, la reponse attendue est `[]` (VM2 et fallback exposent un endpoint minimal)
- l'objectif de ce test est la disponibilite HTTP de la route, pas la demonstration CRUD

Capture essentielle:

- ID: CAP-07
- Nom fichier conseille: `cap-07-api-users.png`
- Contenu visible: reponse JSON de l'endpoint users (souvent `[]` en sandbox)

### Etape 8 - Checkup Final Global

```bash
./deploy.sh --status
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
```

Resultat attendu:

- vue synthetique complete des tiers

Capture essentielle:

- ID: CAP-08
- Nom fichier conseille: `cap-08-checkup-final.png`
- Contenu visible: etat global de l'architecture

### Etape 9 - Validation Automatique Projet

```bash
./scripts/validate.sh ad-gomis-dev
```

Resultat attendu:

- bilan `PASS/WARN/FAIL` coherent avec l'etat du sandbox
- `GET /health => 200` et `GET /api/users => 200`

Capture essentielle:

- ID: CAP-09
- Nom fichier conseille: `cap-09-validation-script.png`
- Contenu visible: resume final PASS/WARN/FAIL

## 3. Tableau Resume Des Captures

| ID | Capture | Commande principale | Nom fichier conseille |
| --- | --- | --- | --- |
| CAP-01 | Contexte cluster | `oc whoami && oc project -q` | `cap-01-contexte-rbac-namespace.png` |
| CAP-02 | Application manifests | `oc apply -k openshift` | `cap-02-apply-kustomize.png` |
| CAP-03 | Etat VMs/VMI | `oc get vm,vmi -n ad-gomis-dev` | `cap-03-vm-vmi-running.png` |
| CAP-04 | Etat DB Pod | `oc get deploy,pod,svc,pvc -n ad-gomis-dev \| grep mysql-db` | `cap-04-db-pod-service-pvc.png` |
| CAP-05 | Route web | `oc get route route-web -n ad-gomis-dev` | `cap-05-route-web.png` |
| CAP-06 | Health endpoint | `curl -k https://<route>/health` | `cap-06-health-endpoint.png` |
| CAP-07 | API users | `curl -k https://<route>/api/users` | `cap-07-api-users.png` |
| CAP-08 | Checkup final | `./deploy.sh --status` | `cap-08-checkup-final.png` |
| CAP-09 | Validation automatique | `./scripts/validate.sh ad-gomis-dev` | `cap-09-validation-script.png` |

## 4. Gabarit Annexe A Copier Dans Le Rapport

Utiliser ce bloc pour inserer rapidement les captures dans le rapport final:

### Annexe CAP-01 - Contexte RBAC/Namespace

[INSERER LA CAPTURE CAP-01 ICI]

### Annexe CAP-02 - Application Kustomize

[INSERER LA CAPTURE CAP-02 ICI]

### Annexe CAP-03 - Etat VMs/VMI

[INSERER LA CAPTURE CAP-03 ICI]

### Annexe CAP-04 - Etat DB Pod/Service/PVC

[INSERER LA CAPTURE CAP-04 ICI]

### Annexe CAP-05 - Route Web

[INSERER LA CAPTURE CAP-05 ICI]

### Annexe CAP-06 - Health Endpoint

[INSERER LA CAPTURE CAP-06 ICI]

### Annexe CAP-07 - API Users

[INSERER LA CAPTURE CAP-07 ICI]

### Annexe CAP-08 - Checkup Final

[INSERER LA CAPTURE CAP-08 ICI]

### Annexe CAP-09 - Validation Automatique

[INSERER LA CAPTURE CAP-09 ICI]

## 5. Conseils De Capture Pour Une Remise Propre

- Garder la commande et la sortie dans la meme capture
- Afficher le prompt avec le namespace courant
- Eviter les captures tronquees
- Utiliser une nomenclature de fichiers numerotee (CAP-01, CAP-02, ...)
- Exporter le rapport final en PDF apres insertion des captures

## 6. Depannage Rapide - "Application is not available"

Si la route retourne la page HTML "Application is not available", verifier dans cet ordre:

```bash
oc get vm,vmi -n ad-gomis-dev
oc get endpoints web-service-ha -n ad-gomis-dev -o yaml
oc get svc web-service-ha -n ad-gomis-dev -o yaml | sed -n '1,120p'
```

Interpretation:

- VMI `vm2-web` non Running: demarrer la VM

```bash
virtctl start vm2-web -n ad-gomis-dev
```

- Endpoints vides alors que VM2 est Running: reappliquer les manifests (correction selecteur)

```bash
oc apply -k openshift
```

Validation finale:

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
curl -k "https://${ROUTE_URL}/api/users"
```
