# Guide de Validation - Architecture Hybride

Ce guide valide l'architecture retenue et approuvee:

- VM1 Firewall (KubeVirt)
- VM2 Web (KubeVirt)
- Base MySQL en Pod OpenShift

## 1. Verification du contexte

```bash
oc whoami
oc project -q
```

Resultat attendu:

- utilisateur: ad-gomis
- namespace: ad-gomis-dev

## 2. Verification des ressources de base

```bash
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
```

Resultat attendu:

- VM1 et VM2 presentes
- deployment mysql-db present
- service mysql-db (ClusterIP)
- service svc-web et route route-web
- PVC pvc-mysql-data present

## 3. Verification des VMs critiques

```bash
# runStrategy=Manual en sandbox
virtctl start vm1-firewall -n ad-gomis-dev || true
virtctl start vm2-web -n ad-gomis-dev || true

oc get vm,vmi -n ad-gomis-dev
```

Resultat attendu:

- vm1-firewall: Running
- vm2-web: Running

## 4. Verification du tier base de donnees (Pod OpenShift)

```bash
oc rollout status deploy/mysql-db -n ad-gomis-dev
oc get pod -l role=db -n ad-gomis-dev
oc get svc mysql-db -n ad-gomis-dev
```

Resultat attendu:

- deployment/mysql-db: successfully rolled out
- pod mysql: Running/Ready
- service mysql-db: type ClusterIP, port 3306

## 5. Verification applicative Web -> DB

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')

curl -k "https://${ROUTE_URL}/health"
curl -k "https://${ROUTE_URL}/api/users"
```

Resultat attendu:

- /health retourne un statut OK
- /api/users retourne une liste d'utilisateurs issue de MySQL

## 6. Verification securite minimale

```bash
# La base ne doit pas etre exposee publiquement
oc get svc mysql-db -n ad-gomis-dev -o wide
oc get route -n ad-gomis-dev | grep -i mysql || true
```

Resultat attendu:

- mysql-db est uniquement ClusterIP
- aucune route publique vers MySQL

## 7. Checkup final rapide

```bash
./deploy.sh --status
```

Resultat attendu:

- VMs visibles
- ressources DB visibles (deploy,pod,svc,pvc)
- services et route web visibles

## 8. Troubleshooting express

- Si VM bloquee en Pending: `oc describe vmi <vm-name> -n ad-gomis-dev`
- Si DB non disponible: `oc logs deploy/mysql-db -n ad-gomis-dev`
- Si API ne répond pas: `virtctl ssh admin@vm2-web -n ad-gomis-dev -- systemctl status nodeapp`
- Si route KO: `oc get endpoints svc-web -n ad-gomis-dev`
