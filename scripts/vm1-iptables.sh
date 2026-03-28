#!/bin/bash
# =============================================================================
# VM1 — Script de configuration iptables (Passerelle / Firewall)
# Architecture : Internet (NAT) <-> VM1 <-> DMZ (VM2) | LAN (VM3)
#
# Interfaces :
#   eth0 = Interface WAN (vers Internet via NAT OpenShift)
#   eth1 = Interface LAN (192.168.10.0/24) — Serveur BD (VM3)
#   eth2 = Interface DMZ (192.168.100.0/24) — Serveur Web (VM2)
#
# Règles appliquées :
#   R1 : Internet N'accède PAS au LAN (VM3 - BD)
#   R2 : VM2 (Web) accède à VM3 (BD) uniquement sur TCP/3306
#   R3 : VM3 (BD) PEUT accéder à VM2 (Web) et Internet
#   R4 : Internet PEUT accéder à VM2 (Web) sur port 80/443
#   R5 : VM2 (Web) PEUT accéder à Internet
# =============================================================================

set -euo pipefail

WAN="eth0"
LAN="eth1"
DMZ="eth2"

IP_LAN="192.168.10.0/24"
IP_DMZ="192.168.100.0/24"
IP_VM2="192.168.100.10"
IP_VM3="192.168.10.10"

echo "[*] Activation du routage IP..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-routing.conf

echo "[*] Nettoyage des règles existantes..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# =============================================================================
# POLITIQUES PAR DÉFAUT (tout bloquer, autoriser sélectivement)
# =============================================================================
echo "[*] Application des politiques par défaut..."
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT

# =============================================================================
# CHAÎNE INPUT — Trafic à destination de VM1 elle-même
# =============================================================================
# Autoriser les connexions établies/relatives
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Autoriser le loopback
iptables -A INPUT -i lo -j ACCEPT

# Autoriser SSH depuis LAN et DMZ uniquement (pas depuis Internet)
iptables -A INPUT -i $LAN -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i $DMZ -p tcp --dport 22 -j ACCEPT

# Autoriser ICMP (ping) depuis LAN et DMZ pour la maintenance
iptables -A INPUT -i $LAN -p icmp -j ACCEPT
iptables -A INPUT -i $DMZ -p icmp -j ACCEPT

# =============================================================================
# CHAÎNE FORWARD — Trafic routé entre les interfaces
# =============================================================================
# Autoriser les connexions établies/relatives dans les deux sens
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# --- R1 : Internet N'accède PAS au LAN (VM3 - Serveur BD) ---
iptables -A FORWARD -i $WAN -o $LAN -j DROP
echo "[+] R1 appliquée : Internet -> LAN (BD) BLOQUÉ"

# --- R2 : VM2 (Web/DMZ) -> VM3 (BD/LAN) uniquement sur 3306 ---
iptables -A FORWARD -i $DMZ -o $LAN \
  -s $IP_VM2 -d $IP_VM3 \
  -p tcp --dport 3306 \
  -m state --state NEW,ESTABLISHED \
  -j ACCEPT
# Bloquer tout autre trafic DMZ -> LAN
iptables -A FORWARD -i $DMZ -o $LAN -j DROP
echo "[+] R2 appliquée : DMZ (Web) -> LAN (BD) autorisé uniquement sur 3306"

# --- R3 : VM3 (BD/LAN) PEUT accéder à VM2 (Web/DMZ) et Internet ---
# VM3 -> VM2 (Web) : accès HTTP/HTTPS uniquement
iptables -A FORWARD -i $LAN -o $DMZ \
  -s $IP_VM3 -d $IP_VM2 \
  -p tcp -m multiport --dports 80,443,3000 \
  -m state --state NEW,ESTABLISHED \
  -j ACCEPT
# VM3 -> Internet
iptables -A FORWARD -i $LAN -o $WAN \
  -s $IP_VM3 \
  -m state --state NEW,ESTABLISHED \
  -j ACCEPT
echo "[+] R3 appliquée : LAN (BD) -> DMZ (Web) et Internet AUTORISÉ"

# --- R4 : Internet PEUT accéder à VM2 (Web) sur port 80 et 443 ---
iptables -A FORWARD -i $WAN -o $DMZ \
  -d $IP_VM2 \
  -p tcp -m multiport --dports 80,443 \
  -m state --state NEW,ESTABLISHED \
  -j ACCEPT
echo "[+] R4 appliquée : Internet -> DMZ (Web) port 80/443 AUTORISÉ"

# --- R5 : VM2 (Web/DMZ) PEUT accéder à Internet ---
iptables -A FORWARD -i $DMZ -o $WAN \
  -s $IP_VM2 \
  -m state --state NEW,ESTABLISHED \
  -j ACCEPT
echo "[+] R5 appliquée : DMZ (Web) -> Internet AUTORISÉ"

# =============================================================================
# NAT MASQUERADE — Sortie Internet pour VM2 et VM3
# =============================================================================
iptables -t nat -A POSTROUTING -o $WAN -s $IP_LAN -j MASQUERADE
iptables -t nat -A POSTROUTING -o $WAN -s $IP_DMZ -j MASQUERADE

# DNAT — Rediriger le trafic Internet entrant (port 80/443) vers VM2
iptables -t nat -A PREROUTING -i $WAN \
  -p tcp -m multiport --dports 80,443 \
  -j DNAT --to-destination $IP_VM2

echo "[*] Sauvegarde des règles iptables..."
netfilter-persistent save

echo ""
echo "========================================================"
echo " Configuration iptables terminée avec succès !"
echo "========================================================"
iptables -L -n -v --line-numbers
