# Rapport de Synthese - Deploiement Architecture 3-Tiers

Version cible: PDF (10 pages max)

Auteur: ADONIS-IX (ad-gomis)
Date: 30 mars 2026
Namespace de demonstration: ad-gomis-dev

---

## 1. Introduction du projet

Ce document presente une synthese de demonstration du projet 3-tiers hybride sur OpenShift Sandbox.

Le projet vise a prouver qu'une architecture pedagogique avec composants virtualises et conteneurises peut rester operationnelle dans un environnement contraint.

Objectifs de demonstration:

- deployer l'architecture complete (VM1, VM2, Web fallback, MySQL)
- valider l'exposition web publique via Route OpenShift
- verifier que le tier donnees reste interne (ClusterIP)
- fournir des preuves exploitables (captures et logs)

Contexte d'execution:

- sandbox multi-tenant avec restrictions RBAC et admission
- instabilite possible des VMs KubeVirt en runStrategy Manual
- besoin de privilegier la disponibilite demonstrable

---

## 2. Architecture et technologies

### 2.1 Vue d'architecture

```text
Internet
  -> Route OpenShift (route-web)
  -> Service web-service-ha (role=web)
  -> VM2 web et/ou pod web-fallback
  -> Service mysql-db (ClusterIP)
  -> Pod MySQL + PVC
```

### 2.2 Technologies utilisees

- Plateforme: OpenShift Sandbox
- Virtualisation: KubeVirt (VM1 firewall, VM2 web)
- Orchestration workloads: Deployments, Services, Route, PVC
- Base de donnees: MySQL 8 (Deployment OpenShift)
- Exposition: Route TLS edge
- Outils de pilotage: oc, virtctl, deploy.sh, scripts/validate.sh

### 2.3 Choix techniques cle

- Service HA web pour absorber les fluctuations de VM2
- VM2 en mode statique cloud-init pour un demarrage rapide et robuste
- Tier DB non expose publiquement (Service ClusterIP)
- Posture Zero Trust orientee identite/autorisation adaptee au sandbox

---

## 3. Screenshots ou logs de deploiement

Cette section est la preuve principale. Utiliser soit des captures ecran, soit les logs texte equivalentes.

### 3.1 Preuve A - Contexte cluster

Commande:

```bash
oc whoami
oc project -q
```

Capture a inserer:

[CAP-01 - contexte-rbac-namespace]

Log texte acceptable:

```text
ad-gomis
ad-gomis-dev
```

### 3.2 Preuve B - Application des manifests

Commande:

```bash
oc apply -k openshift
```

Capture a inserer:

[CAP-02 - apply-kustomize]

Log texte acceptable:

```text
secret/db-credentials configured
virtualmachine.kubevirt.io/vm1-firewall configured
virtualmachine.kubevirt.io/vm2-web configured
service/web-service-ha configured
route.route.openshift.io/route-web configured
```

### 3.3 Preuve C - Etat des VMs et VMI

Commande:

```bash
oc get vm,vmi -n ad-gomis-dev
```

Capture a inserer:

[CAP-03 - vm-vmi-running]

Log texte acceptable:

```text
virtualmachine.kubevirt.io/vm1-firewall   Running
virtualmachine.kubevirt.io/vm2-web        Running
virtualmachineinstance.kubevirt.io/vm1-firewall   Running
virtualmachineinstance.kubevirt.io/vm2-web        Running
```

### 3.4 Preuve D - Tier donnees (DB)

Commandes:

```bash
oc rollout status deploy/mysql-db -n ad-gomis-dev
oc get deploy,pod,svc,pvc -n ad-gomis-dev | grep -E 'mysql-db|pvc-mysql-data'
```

Capture a inserer:

[CAP-04 - db-pod-service-pvc]

Log texte acceptable:

```text
deployment "mysql-db" successfully rolled out
service/mysql-db   ClusterIP
persistentvolumeclaim/pvc-mysql-data   Bound
```

### 3.5 Preuve E - Route web exposee

Commande:

```bash
oc get route route-web -n ad-gomis-dev
```

Capture a inserer:

[CAP-05 - route-web]

Log texte acceptable:

```text
route-web-ad-gomis-dev.apps.<cluster-domain>
termination: edge
```

### 3.6 Preuve F - Endpoint health public

Commande:

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
```

Capture a inserer:

[CAP-06 - health-endpoint]

Log texte acceptable:

```text
{"status":"ok","service":"pod-fallback"}
```

ou

```text
{"status":"ok","service":"vm2-web-containerdisk"}
```

### 3.7 Preuve G - Endpoint users public

Commande:

```bash
curl -k "https://${ROUTE_URL}/api/users"
```

Capture a inserer:

[CAP-07 - api-users]

Log texte acceptable:

```text
[]
```

### 3.8 Preuve H - Checkup final global

Commandes:

```bash
./deploy.sh --status
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
```

Capture a inserer:

[CAP-08 - checkup-final]

### 3.9 Preuve I - Validation automatique

Commande:

```bash
./scripts/validate.sh ad-gomis-dev
```

Capture a inserer:

[CAP-09 - validation-script]

Log texte acceptable:

```text
Resultat: X PASS / Y WARN / 0 FAIL
```

---

## 4. Tableau de synthese des preuves

| ID | Preuve | Commande principale | Fichier capture conseille |
| --- | --- | --- | --- |
| CAP-01 | Contexte cluster | oc whoami && oc project -q | cap-01-contexte-rbac-namespace.png |
| CAP-02 | Deploiement manifests | oc apply -k openshift | cap-02-apply-kustomize.png |
| CAP-03 | Etat VM/VMI | oc get vm,vmi -n ad-gomis-dev | cap-03-vm-vmi-running.png |
| CAP-04 | Etat DB | oc get deploy,pod,svc,pvc ... | cap-04-db-pod-service-pvc.png |
| CAP-05 | Route web | oc get route route-web -n ad-gomis-dev | cap-05-route-web.png |
| CAP-06 | Health public | curl -k https://ROUTE_URL/health | cap-06-health-endpoint.png |
| CAP-07 | API users public | curl -k https://ROUTE_URL/api/users | cap-07-api-users.png |
| CAP-08 | Checkup global | ./deploy.sh --status | cap-08-checkup-final.png |
| CAP-09 | Validation script | ./scripts/validate.sh ad-gomis-dev | cap-09-validation-script.png |

---

## 5. Conclusion de synthese

Le deploiement prouve une architecture 3-tiers hybride demonstrable en contexte OpenShift Sandbox.

Points valides par preuves:

- architecture deployee et observable de bout en bout
- disponibilite web publique maintenue via service HA
- tier donnees protege et interne (ClusterIP)
- processus de validation reproductible via script

Cette synthese est volontairement concise pour rester dans une enveloppe PDF inferieure ou egale a 10 pages.
