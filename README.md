# Projet 3-tiers Hybride sur OpenShift

## Vue d'ensemble

Architecture retenue et validee:

- Tier 1: VM1 Firewall (KubeVirt)
- Tier 2: VM2 Web (KubeVirt, containerDisk)
- Tier 2 bis: Pod fallback Web (Deployment OpenShift)
- Tier 3: Base MySQL en Pod OpenShift (Deployment + PVC)

Schema logique:

```text
Internet
    |
Route OpenShift (TLS edge)
    |
Service web-service-ha (selector: role=web)
    |
+---------------------------+
| VM2 Web | Pod fallback    |
+---------------------------+
    |
Service mysql-db (ClusterIP)
    |
Pod MySQL + PVC
```

Le service web reste disponible meme si la VM2 est arretee par les contraintes du sandbox.

### Positionnement securite en Sandbox

L'infrastructure est prete pour une segmentation de type perimetre (NAD et scripts disponibles dans le depot), mais le runtime OpenShift Sandbox multi-tenant limite l'usage de ces mecanismes en execution.

Dans ce contexte, le modele retenu est une approche Zero Trust orientee identite et autorisation (identite des workloads, RBAC, secrets, controles applicatifs), plutot qu'une micro-segmentation fine basee uniquement sur le perimetre reseau.

## Structure essentielle du depot

```text
projet-3tiers/
├── deploy.sh
├── openshift/
│   ├── namespace.yaml
│   ├── secrets/
│   │   └── db-credentials.yaml
│   ├── services/
│   │   ├── db-mysql.yaml
│   │   └── svc-web.yaml
│   └── vms/
│       ├── vm1-firewall.yaml
│       └── vm2-web.yaml
├── docs/
│   ├── GUIDE_EXECUTION_MISE_EN_OEUVRE.md
│   ├── VALIDATION.md
│   └── RAPPORT_FINAL_PRET_IMPRESSION_PDF.md
└── scripts/
    ├── vm1-iptables.sh
    ├── watch-vm1.sh
    ├── watch-vm2.sh
    └── validate.sh
```

## Deploiement rapide

```bash
oc get namespace ad-gomis-dev >/dev/null 2>&1 || oc create namespace ad-gomis-dev
oc project ad-gomis-dev
oc apply -k openshift

virtctl start vm1-firewall -n ad-gomis-dev || true
virtctl start vm2-web -n ad-gomis-dev || true
```

Le namespace est gere hors `kustomization` pour eviter les erreurs RBAC de type `cannot patch namespaces` dans les environnements sandbox.

## Verification

```bash
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev

ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
curl -k "https://${ROUTE_URL}/api/users"
```

## Tolerance aux pannes (sandbox)

Face aux restrictions strictes du sandbox (extinction automatique de VMs containerDisk), le trafic web est gere par un Service Kubernetes unique (`web-service-ha`) qui englobe:

- la VM2 (validation KubeVirt)
- un Pod fallback leger

Ainsi, lorsque VM2 est evincee, la route publique continue de repondre en HTTP 200 sans interruption utilisateur.
Note sandbox: VM1 et VM2 peuvent s'arreter de facon intermittente (runStrategy Manual).
Redemarrage a la demande:

- `virtctl start vm1-firewall -n ad-gomis-dev`
- `virtctl start vm2-web -n ad-gomis-dev`

Pour une surveillance automatique en soutenance:

- `./scripts/watch-vm1.sh ad-gomis-dev 15`
- `./scripts/watch-vm2.sh ad-gomis-dev 20`
