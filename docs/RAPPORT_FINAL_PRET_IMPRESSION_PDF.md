# RAPPORT FINAL - PROJET D'ARCHITECTURE 3-TIERS HYBRIDE

## Page De Garde

Etablissement: ________________________________

Formation / Module: ___________________________

Intitule du projet: Architecture 3-tiers hybride sur OpenShift

Auteur: ADONIS-IX (ad-gomis)

Encadrant / Professeur: _______________________

Date de remise: ____ / ____ / 2026

Version du document: v1.0 (pret impression)

---

## Plan Du Rapport

1. Introduction
2. Objectifs pedagogiques
3. Contexte et contraintes d'execution
4. Architecture finale retenue
5. Description des composants techniques
6. Procedure de deploiement
7. Validation et resultats
8. Analyse critique
9. Conclusion academique formelle
10. Annexes (captures d'ecran)

---

## 1. Introduction

Ce rapport presente la mise en oeuvre d'une architecture 3-tiers sur OpenShift, dans un contexte pedagogique de virtualisation, d'administration systeme et de securisation de services.

La solution finale appliquee, validee par le professeur, adopte une architecture hybride resiliente:

- Tiers securite: VM Firewall (KubeVirt)
- Tiers presentation/metier: VM Web (KubeVirt, Nginx)
- Continuite de service: Pod fallback Web (Deployment OpenShift)
- Tiers donnees: Pod MySQL natif OpenShift (Deployment + Service + PVC)

Cette orientation permet de conserver les objectifs academiques majeurs tout en restant compatible avec les contraintes reelles de l'environnement sandbox.

## 2. Objectifs Pedagogiques

Les objectifs poursuivis dans ce projet sont les suivants:

- Concevoir une architecture 3-tiers claire et argumentee
- Deployer des ressources virtualisees et conteneurisees sur OpenShift
- Mettre en oeuvre la communication applicative Web -> DB
- Assurer la persistance des donnees avec stockage PVC
- Exposer le service web de maniere securisee via Route TLS
- Produire une documentation technique et de validation exploitable

## 3. Contexte Et Contraintes D'Execution

Le deploiement a ete realise dans un namespace sandbox (`ad-gomis-dev`) avec des restrictions de plateforme:

- quota de VMs limite
- restrictions reseau avancees (NAD/Multus non accessibles en self-service)
- politiques d'admission KubeVirt specifiques au sandbox

Dans ce contexte, l'adaptation hybride constitue une solution pedagogiquement robuste, techniquement deployable et explicitement acceptee par l'encadrement.

## 4. Architecture Finale Retenue

```text
Internet
  |
Route OpenShift (TLS edge)
  |
Service web-service-ha
  |
VM2 Web (Nginx) + Pod web-fallback
  |
Service mysql-db (ClusterIP)
  |
Pod MySQL (Deployment) + PVC

VM1 Firewall reste virtualisee comme composant critique de securite.
```

Logique de separation des tiers:

- Tier 1: securite et controle (VM1)
- Tier 2: presentation/API (VM2)
- Tier 3: persistance des donnees (MySQL Pod)

## 5. Description Des Composants Techniques

Composants OpenShift/KubeVirt:

- `openshift/vms/vm1-firewall.yaml`
- `openshift/vms/vm2-web.yaml`
- `openshift/services/db-mysql.yaml`
- `openshift/services/svc-web.yaml`
- `openshift/secrets/db-credentials.yaml`
- `openshift/kustomization.yaml`

Composants applicatifs:

- `app/src/db.js`
- `deploy.sh`

Details fonctionnels:

- MySQL initialise via ConfigMap SQL au premier demarrage
- Donnees persistees via PVC `pvc-mysql-data`
- Exposition publique uniquement du web via `route-web`
- Base de donnees non exposee publiquement (service interne ClusterIP)

## 6. Procedure De Deploiement

```bash
oc project ad-gomis-dev
oc apply -k openshift

virtctl start vm1-firewall -n ad-gomis-dev
virtctl start vm2-web -n ad-gomis-dev
```

Verification de base:

```bash
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
oc rollout status deploy/mysql-db -n ad-gomis-dev
```

## 7. Validation Et Resultats

Validation fonctionnelle recommandee:

```bash
ROUTE_URL=$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')
curl -k "https://${ROUTE_URL}/health"
curl -k "https://${ROUTE_URL}/api/users"
```

Resultats attendus:

- API accessible depuis la route publique
- disponibilite maintenue via VM2 ou fallback Pod
- base MySQL joignable en interne par le tier web
- endpoint `/api/users` retourne des donnees ou `[]` en fallback

## 8. Analyse Critique

Points forts:

- approche realiste et deployable en environnement contraint
- maintien de la logique 3-tiers
- separation claire entre exposition publique et stockage interne
- documentation et procedure de validation reproductibles

Points a ameliorer:

- reenabler une segmentation LAN/DMZ stricte en environnement non sandbox
- ajouter des NetworkPolicies pour filtrage intra-namespace fin
- ajouter des tests automatiques de non-regression applicative

## 9. Conclusion Academique Formelle

En conclusion, ce projet atteint les objectifs pedagogiques centraux attendus dans le module, en combinant virtualisation et orchestration cloud native.

La solution finale retenue (VM Firewall + VM Web + DB Pod OpenShift) demeure conforme a l'esprit d'une architecture 3-tiers, tout en tenant compte de contraintes techniques reelles imposees par l'environnement de laboratoire.

Le dispositif de deploiement, de validation et de documentation fourni permet une evaluation rigoureuse, reproductible et techniquement argumentee. Cette approche illustre une competence cle en ingenierie systeme: adapter l'architecture cible sans perdre la coherence fonctionnelle ni la qualite des livrables.

## 10. Annexes - Captures D'Ecran

### Annexe A - Contexte Cluster

Commande a capturer:

```bash
oc whoami
oc project -q
```

Espace pour capture:

[COLLER ICI LA CAPTURE A - CONTEXTE CLUSTER]

### Annexe B - Inventaire des Ressources

Commande a capturer:

```bash
oc get vm,vmi,deploy,pod,svc,route,pvc -n ad-gomis-dev
```

Espace pour capture:

[COLLER ICI LA CAPTURE B - INVENTAIRE RESSOURCES]

### Annexe C - Etat Des VMs

Commande a capturer:

```bash
oc get vm,vmi -n ad-gomis-dev
```

Espace pour capture:

[COLLER ICI LA CAPTURE C - ETAT VMS]

### Annexe D - Tier Base De Donnees

Commande a capturer:

```bash
oc get deploy,pod,svc,pvc -n ad-gomis-dev | grep -E 'mysql-db|pvc-mysql-data'
```

Espace pour capture:

[COLLER ICI LA CAPTURE D - DB POD/PVC/SVC]

### Annexe E - Route Web

Commande a capturer:

```bash
oc get route route-web -n ad-gomis-dev
```

Espace pour capture:

[COLLER ICI LA CAPTURE E - ROUTE WEB]

### Annexe F - Healthcheck

Commande a capturer:

```bash
curl -k "https://$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')/health"
```

Espace pour capture:

[COLLER ICI LA CAPTURE F - HEALTHCHECK]

### Annexe G - Test API /users

Commande a capturer:

```bash
curl -k "https://$(oc get route route-web -n ad-gomis-dev -o jsonpath='{.spec.host}')/api/users"
```

Espace pour capture:

[COLLER ICI LA CAPTURE G - API USERS]

---

## Export PDF (Recommande)

Depuis VS Code:

1. Ouvrir ce fichier Markdown
2. Lancer `Markdown: Open Preview to the Side`
3. Lancer `Markdown PDF: Export (pdf)` si extension installee
4. Nom du rendu conseille: `RAPPORT_FINAL_AD_GOMIS_2026.pdf`
