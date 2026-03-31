# Guide de Demonstration - Execution

Ce guide est la version operatoire de soutenance.
Il est aligne avec le rapport de demonstration et privilegie la preuve d execution reelle en OpenShift Sandbox.

## 1. Portee de la demo

Architecture demontree:

- VM1 Firewall (KubeVirt)
- VM2 Web (KubeVirt, containerDisk, cloud-init statique)
- Pod web-fallback (continuite de service)
- MySQL en Pod OpenShift (Deployment + PVC + Service ClusterIP)

Objectif:

- prouver disponibilite web, stabilite de parcours et securite minimale du tier DB

## 2. Pre-requis

- connexion OpenShift valide (`oc login`)
- namespace `ad-gomis-dev`
- binaires `oc` et `virtctl` disponibles
- execution depuis la racine du depot

Verification rapide:

```bash
oc whoami
oc project ad-gomis-dev
oc project -q
command -v oc
command -v virtctl
```

## 3. Sequence de demonstration (9 etapes)

### Etape 1 - Verifier contexte

```bash
oc whoami
oc project -q
```

Attendu:

- utilisateur et namespace corrects

Capture:

- CAP-01 - contexte-rbac-namespace

### Etape 2 - Deployer les manifests

```bash
oc apply -k openshift
```

Attendu:

- secret DB applique
- mysql-db (deploy, svc, pvc) applique
- vm1-firewall et vm2-web appliquees
- web-service-ha, web-fallback et route-web appliques

Capture:

- CAP-02 - apply-kustomize

Si timeout API ou DNS instable:

```bash
oc whoami --show-server
getent hosts api.rm2.thpm.p1.openshiftapps.com
curl -k --connect-timeout 8 -I https://api.rm2.thpm.p1.openshiftapps.com:6443/readyz
```

### Etape 3 - Demarrer les VMs critiques

```bash
virtctl start vm1-firewall -n ad-gomis-dev || true
virtctl start vm2-web -n ad-gomis-dev || true
oc get vm,vmi -n ad-gomis-dev
```

Attendu:

- vm1-firewall Running (ou redemarree)
- vm2-web Running (ou fallback actif si arret transitoire)

Capture:

- CAP-03 - vm-vmi-running

Conseil soutenance:

```bash
./scripts/watch-vm1.sh ad-gomis-dev 15
./scripts/watch-vm2.sh ad-gomis-dev 20
```

### Etape 4 - Verifier tier donnees

```bash
oc rollout status deploy/mysql-db -n ad-gomis-dev
oc get deploy,pod,svc,pvc -n ad-gomis-dev | grep -E 'mysql-db|pvc-mysql-data'
```

Attendu:

- mysql-db pret
- pod mysql Running
- service mysql-db en ClusterIP
- pvc-mysql-data Bound

Capture:

- CAP-04 - db-pod-service-pvc

### Etape 5 - Verifier service et route web

```bash
oc get svc web-service-ha -n ad-gomis-dev
oc get endpoints web-service-ha -n ad-gomis-dev -o yaml
oc get route route-web -n ad-gomis-dev
```

Attendu:

- service web-service-ha present
- endpoints non vides (VM2 et/ou fallback)
- host route-web present

Capture:

- CAP-05 - route-web

### Etape 6 - Tester endpoint health public

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
```

Attendu:

- HTTP 200
- JSON depuis `vm2-web-containerdisk` ou `pod-fallback`

Capture:

- CAP-06 - health-endpoint

### Etape 7 - Tester endpoint users public

```bash
curl -k "https://${ROUTE_URL}/api/users"
```

Attendu:

- HTTP 200
- JSON valide (souvent `[]` en mode sandbox)

Capture:

- CAP-07 - api-users

### Etape 8 - Checkup global

```bash
./deploy.sh --status
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
```

Attendu:

- vue complete et coherente des tiers

Capture:

- CAP-08 - checkup-final

### Etape 9 - Validation automatique

```bash
./scripts/validate.sh ad-gomis-dev
```

Attendu:

- 0 FAIL
- WARN possibles en sandbox (ex: VM2 stoppee mais fallback actif)

Capture:

- CAP-09 - validation-script

## 4. Matrice des captures

| ID | Preuve | Commande | Nom conseille |
| --- | --- | --- | --- |
| CAP-01 | Contexte cluster | `oc whoami && oc project -q` | `cap-01-contexte-rbac-namespace.png` |
| CAP-02 | Application manifests | `oc apply -k openshift` | `cap-02-apply-kustomize.png` |
| CAP-03 | Etat VM/VMI | `oc get vm,vmi -n ad-gomis-dev` | `cap-03-vm-vmi-running.png` |
| CAP-04 | Tier DB | `oc get deploy,pod,svc,pvc -n ad-gomis-dev \| grep mysql-db` | `cap-04-db-pod-service-pvc.png` |
| CAP-05 | Route web | `oc get route route-web -n ad-gomis-dev` | `cap-05-route-web.png` |
| CAP-06 | Health public | `curl -k https://<route>/health` | `cap-06-health-endpoint.png` |
| CAP-07 | API users public | `curl -k https://<route>/api/users` | `cap-07-api-users.png` |
| CAP-08 | Checkup global | `./deploy.sh --status` | `cap-08-checkup-final.png` |
| CAP-09 | Validation script | `./scripts/validate.sh ad-gomis-dev` | `cap-09-validation-script.png` |

## 5. Depannage express

### Cas A - "Application is not available"

```bash
oc get vm,vmi -n ad-gomis-dev
oc get endpoints web-service-ha -n ad-gomis-dev -o yaml
oc get svc web-service-ha -n ad-gomis-dev -o yaml | sed -n '1,120p'
```

Actions:

```bash
virtctl start vm2-web -n ad-gomis-dev || true
oc apply -f openshift/services/svc-web.yaml
```

### Cas B - DB non prete

```bash
oc rollout status deploy/mysql-db -n ad-gomis-dev
oc logs deploy/mysql-db -n ad-gomis-dev --tail=80
```

### Cas C - Instabilite VM en sandbox

```bash
./scripts/watch-vm1.sh ad-gomis-dev 15
./scripts/watch-vm2.sh ad-gomis-dev 20
```

## 6. Phrase de synthese soutenance

Nous demontrons une architecture 3-tiers hybride resiliente, adaptee aux contraintes OpenShift Sandbox: disponibilite assuree par le service HA (VM2 et fallback), tier donnees interne en ClusterIP, et posture Zero Trust orientee identite/autorisation plutot qu une micro-segmentation reseau fine non garantie en self-service.
