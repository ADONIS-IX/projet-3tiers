# Guide GitHub — Intégration et versioning

## Initialisation du dépôt

```bash
cd projet-3tiers

# Initialiser Git
git init
git branch -M main

# Ajouter le remote
git remote add origin https://github.com/ADONIS-IX/projet-3tiers.git

# Premier commit
git add .
git commit -m "feat: architecture 3-tiers initiale (OpenShift + iptables + Node.js + MySQL)"
git push -u origin main
```

## Structure des branches recommandée

```text
main          ← code stable, déployé
develop       ← intégration en cours
  ├── feature/vm1-iptables
  ├── feature/vm2-nginx-nodejs
  ├── feature/vm3-mysql
  └── feature/validation-scripts
```

## Convention de commits (Conventional Commits)

```text
feat(vm1): ajouter règle iptables R2 isolation Web/BD
fix(vm2): corriger le timeout Nginx sur proxy Node.js
docs: ajouter guide de validation VALIDATION.md
chore(ci): ajouter lint ShellCheck dans GitHub Actions
refactor(app): extraire la logique DB dans src/db.js
test: ajouter tests de connectivité réseau dans validate.sh
```

## Workflow de contribution

```bash
# Créer une branche pour une nouvelle feature
git checkout -b feature/vm1-iptables

# Travailler, committer
git add scripts/vm1-iptables.sh
git commit -m "feat(vm1): configurer les règles iptables R1 à R5"

# Pousser et ouvrir une Pull Request
git push origin feature/vm1-iptables
# → Ouvrir la PR sur GitHub vers la branche develop

# Après merge, mettre à jour develop localement
git checkout develop
git pull origin develop
```

## Secrets et sécurité

```bash
# Ne JAMAIS committer :
#   - .env (mots de passe)
#   - Clés SSH privées
#   - Tokens ou certificats

# Vérifier avant de committer :
git diff --staged | grep -i "password\|secret\|token\|ssh-rsa"

# Utiliser les Secrets OpenShift pour les mots de passe en production :
oc apply -f openshift/secrets/db-credentials.yaml

# Ou en ligne de commande (toutes les cles necessaires) :
oc create secret generic db-credentials \
  --from-literal=DB_HOST=mysql-db.ad-gomis-dev.svc.cluster.local \
  --from-literal=DB_PORT=3306 \
  --from-literal=DB_NAME=appdb \
  --from-literal=DB_USER=webuser \
  --from-literal=DB_PASS='<mot_de_passe_fort>' \
  --from-literal=DB_ROOT_PASS='<mot_de_passe_root_fort>' \
  --from-literal=DB_MONITOR_PASS='<mot_de_passe_monitor_fort>' \
  --from-literal=DB_ALLOWED_HOST=% \
  --from-literal=MYSQL_BIND_ADDRESS=0.0.0.0 \
  -n ad-gomis-dev
```
