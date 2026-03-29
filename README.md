# Projet 3-tiers Hybride sur OpenShift

## Vue d'ensemble

Architecture retenue et validee:

- Tier 1: VM1 Firewall (KubeVirt)
- Tier 2: VM2 Web persistante (KubeVirt + DataVolume/PVC, Nginx)
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
La VM2 conserve son etat disque entre redemarrages grace au DataVolume `vm2-web-rootdisk`.

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
    └── validate.sh
```

## Deploiement rapide

```bash
oc project ad-gomis-dev
oc apply -k openshift

virtctl start vm1-firewall -n ad-gomis-dev || true
virtctl start vm2-web -n ad-gomis-dev || true
```

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
Quand VM2 redemarre, le disque persistant evite de reperdre la couche systeme configuree.

Note sandbox: selon la fenetre de charge du cluster, l'import DataVolume de VM2 peut rester en `Provisioning` (restriction platforme). La route publique reste operationnelle grace au Pod fallback.
