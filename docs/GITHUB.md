# Guide GitHub — Intégration et versioning

## Initialisation du dépôt

```bash
cd projet-3tiers

# Initialiser Git
git init
git branch -M main

# Ajouter le remote (remplacer VOTRE_USER)
git remote add origin https://github.com/VOTRE_USER/projet-3tiers.git

# Premier commit
git add .
git commit -m "feat: architecture 3-tiers initiale (OpenShift + iptables + Node.js + MySQL)"
git push -u origin main
```

## Structure des branches recommandée

```
main          ← code stable, déployé
develop       ← intégration en cours
  ├── feature/vm1-iptables
  ├── feature/vm2-nginx-nodejs
  ├── feature/vm3-mysql
  └── feature/validation-scripts
```

## Convention de commits (Conventional Commits)

```
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
oc create secret generic db-credentials \
  --from-literal=DB_USER=webuser \
  --from-literal=DB_PASS=admin123 \
  -n projet-3tiers
```
