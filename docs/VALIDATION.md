# Guide de Validation — Architecture 3-tiers

Ce document détaille comment démontrer le bon fonctionnement de chaque partie de l'architecture après déploiement.

---

## Prérequis de validation

```bash
# Se connecter à VM1 (point de contrôle central)
virtctl ssh admin@vm1-firewall -n projet-3tiers
```

---

## Partie 1 — Virtualisation

### Vérifier que les 3 VMs sont actives

```bash
# Depuis le poste de travail (oc CLI)
oc get vmi -n projet-3tiers

# Résultat attendu :
# NAME           AGE   PHASE     IP             NODENAME
# vm1-firewall   Xm    Running   10.128.x.x     node-1
# vm2-web        Xm    Running   10.128.x.x     node-2
# vm3-db         Xm    Running   10.128.x.x     node-3
```

### Vérifier les interfaces réseau de chaque VM

```bash
# Sur VM1 : doit afficher eth0 (WAN), eth1 (LAN 192.168.10.1), eth2 (DMZ 192.168.100.1)
ip addr show

# Sur VM2 : eth0 + eth1 (192.168.100.10)
virtctl ssh admin@vm2-web -n projet-3tiers -- ip addr show

# Sur VM3 : eth0 + eth1 (192.168.10.10)
virtctl ssh admin@vm3-db -n projet-3tiers -- ip addr show
```

---

## Partie 2 — Déploiement des services

### VM2 — Nginx + Node.js

```bash
# Sur VM2 : vérifier que Nginx est actif
virtctl ssh admin@vm2-web -n projet-3tiers -- systemctl status nginx

# Vérifier que Node.js tourne
virtctl ssh admin@vm2-web -n projet-3tiers -- systemctl status nodeapp

# Tester en local sur VM2
virtctl ssh admin@vm2-web -n projet-3tiers -- curl -s http://127.0.0.1/health
# Attendu : {"status":"OK","serveur":"vm2-web",...}

# Tester la connexion à MySQL (VM3) depuis VM2 via l'API
virtctl ssh admin@vm2-web -n projet-3tiers -- curl -s http://127.0.0.1/health/db
# Attendu : {"status":"OK","database":{...}}
```

### VM3 — MySQL

```bash
# Sur VM3 : vérifier que MySQL tourne
virtctl ssh admin@vm3-db -n projet-3tiers -- systemctl status mysql

# Vérifier que MySQL écoute sur l'IP LAN (pas sur 0.0.0.0)
virtctl ssh admin@vm3-db -n projet-3tiers -- ss -tlnp | grep 3306
# Attendu : 192.168.10.10:3306 (et non 0.0.0.0:3306)

# Tester une requête directe
virtctl ssh admin@vm3-db -n projet-3tiers -- \
  mysql -u webuser -p'WebPass@2024!' appdb -e "SELECT * FROM utilisateurs;"
```

### VM1 — iptables

```bash
# Sur VM1 : afficher toutes les règles iptables
sudo iptables -L -n -v --line-numbers

# Vérifier que le routage est activé
cat /proc/sys/net/ipv4/ip_forward
# Attendu : 1
```

---

## Partie 3 — Validation des règles réseau

### R4 : Accès Web depuis l'extérieur

```bash
# Récupérer l'URL de la Route OpenShift
ROUTE_URL=$(oc get route route-web -n projet-3tiers -o jsonpath='{.spec.host}')
echo "URL : https://$ROUTE_URL"

# Test HTTP depuis l'extérieur
curl -s "https://$ROUTE_URL/"
# Attendu : {"status":"OK","application":"TP Architecture 3-tiers",...}

# Test de l'API
curl -s "https://$ROUTE_URL/api/users"
# Attendu : {"status":"OK","total":3,"data":[...]}
```

### R1 : Internet N'accède PAS au LAN (VM3)

```bash
# Depuis l'extérieur : tenter d'atteindre directement VM3 (doit échouer)
# Vérifier que le port 3306 de VM3 n'est PAS exposé sur la Route
oc get svc -n projet-3tiers | grep 3306
# Attendu : aucune ligne (aucun service n'expose le port MySQL)

# Test direct (doit timeout ou refuser) :
curl --max-time 5 http://<IP_NOEUD_OPENSHIFT>:3306
# Attendu : Connection refused ou timeout
```

### R2 : VM2 (Web) accède à VM3 (BD) uniquement sur MySQL/3306

```bash
# Depuis VM2 : accès MySQL vers VM3 autorisé
virtctl ssh admin@vm2-web -n projet-3tiers -- \
  nc -zv -w 3 192.168.10.10 3306
# Attendu : succès (connexion TCP ouverte)

# Depuis VM2 : tout autre port vers VM3 doit rester bloqué
virtctl ssh admin@vm2-web -n projet-3tiers -- \
  nc -zv -w 3 192.168.10.10 22
# Attendu : Connection refused / timed out (bloqué par iptables)

# Vérifier aussi la connexion applicative via l'API :
virtctl ssh admin@vm2-web -n projet-3tiers -- curl -s http://127.0.0.1/health/db
# Attendu : OK (la connexion arrive via VM1 qui route le trafic)
```

### R3 : VM3 (BD) peut accéder à VM2 et Internet

```bash
# Depuis VM3 : ping VM2
virtctl ssh admin@vm3-db -n projet-3tiers -- ping -c 3 192.168.100.10
# Attendu : 3 packets transmitted, 3 received

# Depuis VM3 : accès HTTP vers VM2
virtctl ssh admin@vm3-db -n projet-3tiers -- curl -s http://192.168.100.10/health
# Attendu : {"status":"OK",...}

# Depuis VM3 : accès Internet
virtctl ssh admin@vm3-db -n projet-3tiers -- curl -s --max-time 5 https://example.com | head -5
# Attendu : contenu HTML de example.com
```

### R5 : VM2 peut accéder à Internet

```bash
# Depuis VM2 : accès Internet
virtctl ssh admin@vm2-web -n projet-3tiers -- curl -s --max-time 5 https://example.com | head -5
# Attendu : contenu HTML de example.com

# Depuis VM2 : résolution DNS
virtctl ssh admin@vm2-web -n projet-3tiers -- nslookup google.com
# Attendu : réponse DNS valide
```

---

## Script de validation automatique

```bash
# Exécuter le script de validation complet depuis VM1
virtctl ssh admin@vm1-firewall -n projet-3tiers -- bash /root/validate.sh

# Résultat attendu :
# [TEST] Ping VM2 (Web) depuis VM1                ... ✓ PASS
# [TEST] Ping VM3 (BD)  depuis VM1                ... ✓ PASS
# [TEST] HTTP vers VM2 (port 80)                  ... ✓ PASS
# [TEST] API /health/db sur VM2                   ... ✓ PASS
# [TEST] VM2 (DMZ) -> VM3 (LAN) sur 3306 autorisé ... ✓ PASS
# [TEST] VM2 (DMZ) -> VM3 (LAN) sur 22 bloqué     ... ✓ PASS
# [TEST] VM2 (DMZ) -> Internet                    ... ✓ PASS
# [TEST] VM3 (LAN) -> Internet                    ... ✓ PASS
# Résultats : 8 PASS / 0 FAIL
```

---

## Dépannage fréquent

| Symptôme | Commande de diagnostic | Solution probable |
|----------|----------------------|-------------------|
| VM bloquée en Pending | `oc describe vmi vm1-firewall -n projet-3tiers` | Vérifier les ressources nœud disponibles |
| Réseau LAN/DMZ absent | `oc get nad -n projet-3tiers` | Réappliquer les NAD, vérifier Multus |
| Nginx ne démarre pas | `journalctl -u nginx -n 50` sur VM2 | Vérifier la config avec `nginx -t` |
| MySQL inaccessible | `ss -tlnp` sur VM3 | Vérifier que `bind-address=192.168.10.10` |
| iptables ne persiste pas | `systemctl status netfilter-persistent` | `netfilter-persistent save` sur VM1 |
| Route OpenShift 503 | `oc get endpoints svc-web -n projet-3tiers` | Vérifier que VM2 répond sur port 80 |
