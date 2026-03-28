#!/bin/bash
# =============================================================================
# VM3 — Script d'installation et configuration MySQL
# Réseau LAN : 192.168.10.10/24
# Accès autorisé : VM2 (192.168.100.10) uniquement sur MySQL/3306
# =============================================================================

set -euo pipefail

DB_ROOT_PASS="RootSecure@2024!"
DB_NAME="appdb"
DB_USER="webuser"
DB_PASS="WebPass@2024!"
# Seule VM2 (serveur web) peut se connecter à MySQL
ALLOWED_HOST="192.168.100.10"

echo "[*] Mise à jour du système..."
apt-get update -y && apt-get upgrade -y

echo "[*] Installation de MySQL Server..."
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

echo "[*] Démarrage de MySQL..."
systemctl start mysql
systemctl enable mysql

echo "[*] Sécurisation de MySQL..."
mysql -u root << MYSQL_SECURE
-- Définir le mot de passe root
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_ROOT_PASS}';

-- Supprimer les utilisateurs anonymes
DELETE FROM mysql.user WHERE User='';

-- Désactiver la connexion root distante
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Supprimer la base de test
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

FLUSH PRIVILEGES;
MYSQL_SECURE

echo "[*] Création de la base de données et de l'utilisateur applicatif..."
mysql -u root -p"${DB_ROOT_PASS}" << MYSQL_SETUP
-- Création de la base
CREATE DATABASE IF NOT EXISTS ${DB_NAME}
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Utilisateur applicatif (accessible uniquement depuis VM2)
CREATE USER IF NOT EXISTS '${DB_USER}'@'${ALLOWED_HOST}'
  IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';

-- Permissions limitées : SELECT, INSERT, UPDATE, DELETE uniquement
GRANT SELECT, INSERT, UPDATE, DELETE ON ${DB_NAME}.* TO '${DB_USER}'@'${ALLOWED_HOST}';

-- Utilisateur de monitoring (lecture seule depuis localhost)
CREATE USER IF NOT EXISTS 'monitor'@'localhost'
  IDENTIFIED WITH mysql_native_password BY 'MonitorPass@2024!';
GRANT SELECT ON ${DB_NAME}.* TO 'monitor'@'localhost';

FLUSH PRIVILEGES;

-- Création du schéma de la base de données
USE ${DB_NAME};

CREATE TABLE IF NOT EXISTS utilisateurs (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  nom        VARCHAR(100) NOT NULL,
  email      VARCHAR(150) UNIQUE NOT NULL,
  statut     ENUM('actif','inactif') DEFAULT 'actif',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_email (email),
  INDEX idx_statut (statut)
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS logs_acces (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT,
  action     VARCHAR(100),
  ip_source  VARCHAR(45),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES utilisateurs(id) ON DELETE SET NULL
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Données de test
INSERT INTO utilisateurs (nom, email) VALUES
  ('Alice Dupont',  'alice@example.com'),
  ('Bob Martin',    'bob@example.com'),
  ('Claire Leroy',  'claire@example.com')
ON DUPLICATE KEY UPDATE statut = statut;
MYSQL_SETUP

# =============================================================================
# CONFIGURATION MySQL — Écoute sur l'interface LAN uniquement
# =============================================================================
echo "[*] Configuration de MySQL pour écouter sur le réseau LAN..."

cat > /etc/mysql/mysql.conf.d/99-tp-3tiers.cnf << 'MYSQLCONF'
[mysqld]
# Écouter sur l'interface LAN uniquement (pas sur toutes les interfaces)
bind-address            = 192.168.10.10

# Performance
innodb_buffer_pool_size = 512M
max_connections         = 50
query_cache_type        = 0

# Sécurité
local_infile            = 0
skip_symbolic_links     = yes

# Logs
general_log             = 0
slow_query_log          = 1
slow_query_log_file     = /var/log/mysql/slow.log
long_query_time         = 2

# Charset
character_set_server    = utf8mb4
collation_server        = utf8mb4_unicode_ci
MYSQLCONF

systemctl restart mysql

# =============================================================================
# VÉRIFICATION
# =============================================================================
echo "[*] Vérification de la configuration..."
mysql -u root -p"${DB_ROOT_PASS}" -e "SHOW DATABASES;" 2>/dev/null
mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT user, host FROM mysql.user;" 2>/dev/null
mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT * FROM ${DB_NAME}.utilisateurs;" 2>/dev/null

echo ""
echo "========================================================"
echo " VM3 — MySQL configuré avec succès !"
echo " BD     : ${DB_NAME}"
echo " Écoute : 192.168.10.10:3306"
echo " User   : ${DB_USER}@${ALLOWED_HOST}"
echo "========================================================"
