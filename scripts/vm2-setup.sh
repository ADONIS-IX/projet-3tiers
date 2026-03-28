#!/bin/bash
# =============================================================================
# VM2 — Script d'installation et configuration Nginx + Node.js
# Réseau DMZ : 192.168.100.10/24
# =============================================================================

set -euo pipefail

APP_DIR="/var/www/nodeapp"
APP_USER="nodeapp"
STACK_ENV_PATH="${TP3_STACK_ENV_PATH:-/root/stack.env}"
REPO_URL="${TP3_REPO_URL:-https://github.com/ADONIS-IX/projet-3tiers.git}"
REPO_REF="${TP3_REPO_REF:-main}"

if [[ ! -f "$STACK_ENV_PATH" ]]; then
  echo "[ERREUR] Fichier de configuration manquant: $STACK_ENV_PATH"
  echo "[ERREUR] Ajoutez config/stack.env dans le repo GitHub avant le provisioning."
  exit 1
fi

set -a
source "$STACK_ENV_PATH"
set +a

DB_HOST="${DB_HOST:-192.168.10.10}"
DB_PORT="${DB_PORT:-3306}"

: "${DB_NAME:?DB_NAME doit etre defini dans $STACK_ENV_PATH}"
: "${DB_USER:?DB_USER doit etre defini dans $STACK_ENV_PATH}"
: "${DB_PASS:?DB_PASS doit etre defini dans $STACK_ENV_PATH}"

echo "[*] Mise à jour du système..."
apt-get update -y && apt-get upgrade -y

echo "[*] Installation des dépendances..."
apt-get install -y nginx nodejs npm curl git mysql-client

# Installation Node.js 20 LTS via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "[*] Création de l'utilisateur applicatif..."
id -u $APP_USER &>/dev/null || useradd -r -s /bin/false -d $APP_DIR $APP_USER

echo "[*] Clonage de l'application depuis GitHub..."
mkdir -p $APP_DIR
TMP_REPO_DIR="$(mktemp -d)"
git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$TMP_REPO_DIR"
cp -r "$TMP_REPO_DIR/app/." "$APP_DIR/"
rm -rf "$TMP_REPO_DIR"

cat > $APP_DIR/.env << ENVFILE
NODE_ENV=production
PORT=3000
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
ENVFILE

echo "[*] Installation des dépendances Node.js..."
cd $APP_DIR
if [[ -f package-lock.json ]]; then
  npm ci --omit=dev
else
  npm install --omit=dev
fi

chown -R $APP_USER:$APP_USER $APP_DIR

# =============================================================================
# SERVICE SYSTEMD pour Node.js
# =============================================================================
cat > /etc/systemd/system/nodeapp.service << SYSTEMD
[Unit]
Description=Application Node.js 3-tiers
After=network.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/node ${APP_DIR}/server.js
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=nodeapp
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable nodeapp
systemctl start nodeapp

# =============================================================================
# CONFIGURATION NGINX (reverse proxy vers Node.js)
# =============================================================================
echo "[*] Configuration de Nginx..."

cat > /etc/nginx/sites-available/tp-3tiers << 'NGINXCONF'
server {
    listen 80;
    server_name _;

    # Logs
    access_log /var/log/nginx/tp-3tiers-access.log;
    error_log  /var/log/nginx/tp-3tiers-error.log;

    # Sécurité — masquer la version Nginx
    server_tokens off;

    # Headers de sécurité
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 30s;
    }

    # Endpoint de santé direct
    location /nginx-status {
        stub_status on;
        allow 127.0.0.1;
        allow 192.168.10.0/24;
        deny all;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/tp-3tiers /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable nginx && systemctl restart nginx

echo ""
echo "========================================================"
echo " VM2 — Nginx + Node.js configurés avec succès !"
echo " Nginx  : http://192.168.100.10"
echo " Node.js: http://192.168.100.10:3000 (via reverse proxy)"
echo "========================================================"
