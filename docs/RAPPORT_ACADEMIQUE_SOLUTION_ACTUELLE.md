# Rapport de Demonstration

## Projet

Architecture 3-tiers hybride sur OpenShift Sandbox (KubeVirt + workloads conteneurises)

## Date de reference

30 mars 2026

## Auteur

ADONIS-IX (ad-gomis)

## 1. Objectif de la demonstration

Ce rapport est structure pour une soutenance de demonstration operationnelle.

Objectif principal:

- montrer une architecture 3-tiers fonctionnelle dans un contexte Sandbox contraint
- prouver la disponibilite web continue via un service HA
- prouver la securite minimale du tier donnees (MySQL interne, non expose)

## 2. Message cle a transmettre au jury

- L architecture est pedagogiquement complete (VM1, VM2, tier DB), mais adaptee au runtime Sandbox.
- La disponibilite est prioritaire: route publique stable meme si VM2 fluctue.
- La securite effective en Sandbox est orientee Zero Trust (identite, RBAC, controles), plus que micro-segmentation reseau fine.

## 3. Architecture demontree

### 3.1 Vue logique

```text
Internet
  -> Route OpenShift (route-web)
  -> Service web-service-ha (selector role=web)
  -> VM2 web et/ou pod web-fallback
  -> Service mysql-db (ClusterIP)
  -> Pod MySQL + PVC
```

### 3.2 Composants utilises

- Tier securite: VM1 firewall (KubeVirt, runStrategy Manual)
- Tier presentation: VM2 web (KubeVirt, containerDisk, cloud-init statique)
- Continuite: web-fallback (Deployment OpenShift)
- Tier donnees: mysql-db (Deployment + PVC + Service ClusterIP)

### 3.3 Fichiers de reference

- openshift/vms/vm1-firewall.yaml
- openshift/vms/vm2-web.yaml
- openshift/services/svc-web.yaml
- openshift/services/db-mysql.yaml
- deploy.sh
- scripts/validate.sh
- scripts/watch-vm1.sh
- scripts/watch-vm2.sh

## 4. Contraintes Sandbox confirmees

Limitations constatees par interrogation runtime:

- NAD/Multus: creation et listing refuses pour le compte utilisateur de l espace dev
- privileges cluster-scope limites: patch namespace, clusterrolebinding, SCC privileged refuses
- KubeVirt: runStrategy Always refuse par admission, Manual impose
- quotas/limites actifs sur CPU, memoire et stockage
- policies plateforme preinstallees (dont allow-same-namespace) qui limitent la finesse de micro-segmentation en self-service

Implication:

- architecture orientee disponibilite + controles identite/autorisation
- posture Zero Trust pragmatique en environnement multi-tenant

## 5. Choix VM2: mode secours stable

Le choix VM2 statique via cloud-init est volontaire.

Ce n est pas un manque d ambition technique.
C est une strategie tactique de survie operationnelle en Sandbox:

- eviter les pics de charge de chaines lourdes (apt update, git clone, npm install/build)
- reduire le temps au premier endpoint utile
- garantir l integration rapide au Service HA

Consequence positive:

- baisse du risque de VM Running mais applicativement indisponible
- meilleure probabilite de validation en soutenance dans un environnement instable

## 6. Scenario de demonstration (pas a pas)

### Etape 1 - Verifier le contexte

Commandes:

```bash
oc whoami
oc project -q
```

Attendu:

- utilisateur connecte
- namespace ad-gomis-dev actif

### Etape 2 - Deployer l architecture

Commandes:

```bash
./deploy.sh
```

Attendu:

- mysql-db deploye
- VM1 et VM2 creees (demarrage Manual pilote par script)
- web-service-ha, web-fallback et route-web operationnels

### Etape 3 - Verifier les ressources principales

Commandes:

```bash
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
```

Attendu:

- VM1 et VM2 presentes
- deployment mysql-db present
- service mysql-db en ClusterIP
- route-web presente

### Etape 4 - Verifier le tier donnees

Commandes:

```bash
oc rollout status deploy/mysql-db -n ad-gomis-dev
oc get deploy,pod,svc,pvc -n ad-gomis-dev | grep -E 'mysql-db|pvc-mysql-data'
```

Attendu:

- mysql-db pret
- pod DB Running
- PVC Bound

### Etape 5 - Verifier exposition web

Commandes:

```bash
oc get svc web-service-ha -n ad-gomis-dev
oc get endpoints web-service-ha -n ad-gomis-dev -o yaml
oc get route route-web -n ad-gomis-dev
```

Attendu:

- service web HA present
- endpoints actifs (VM2 et/ou fallback)
- route publique disponible

### Etape 6 - Tester endpoint health public

Commandes:

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
```

Attendu:

- HTTP 200
- reponse depuis vm2-web-containerdisk ou pod-fallback

### Etape 7 - Tester endpoint users public

Commandes:

```bash
curl -k "https://${ROUTE_URL}/api/users"
```

Attendu:

- HTTP 200
- JSON valide (souvent [] en mode sandbox/fallback)

### Etape 8 - Validation globale script

Commandes:

```bash
./scripts/validate.sh ad-gomis-dev
```

Attendu:

- 0 FAIL
- WARN possibles en sandbox (ex: VM temporairement stoppee avec fallback actif)

## 7. Resultats de reference observes

Exemples representatifs observes pendant les validations:

- deploiement termine avec succes
- route-web repond en HTTP 200
- alternance possible des reponses health entre pod-fallback et vm2-web-containerdisk
- validation globale acceptable avec reserves sandbox (0 FAIL, WARN eventuels)

Interpretation:

- la disponibilite du service web est maintenue
- le tier donnees reste interne
- l architecture est demonstrable de facon robuste malgre les contraintes de plateforme

## 8. Plan de repli en soutenance

Si une VM est stoppee pendant la demonstration:

```bash
virtctl start vm1-firewall -n ad-gomis-dev || true
virtctl start vm2-web -n ad-gomis-dev || true
```

Surveillance automatique recommandee:

```bash
./scripts/watch-vm1.sh ad-gomis-dev 15
./scripts/watch-vm2.sh ad-gomis-dev 20
```

Si VM2 n est pas disponible:

- poursuivre la demo via web-fallback
- montrer que la route reste operationnelle (preuve de resilience)

## 9. Criteres de reussite demo

- Critere 1: architecture visible (VM, VMI, deploy, pod, svc, route, pvc)
- Critere 2: health public en HTTP 200
- Critere 3: api/users public en HTTP 200
- Critere 4: mysql-db non expose publiquement (ClusterIP uniquement)
- Critere 5: script de validation sans FAIL

## 10. Conclusion de demonstration

La solution presentee est une architecture 3-tiers hybride, operationnelle et defendable en contexte OpenShift Sandbox.

La strategie retenue privilegie:

- la disponibilite applicative
- la simplicite de reprise
- la securite pragmatique orientee identite

Le resultat est adapte a une soutenance academique basee sur la preuve d execution reelle, et non sur des hypotheses de laboratoire ideal.
