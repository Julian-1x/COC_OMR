#!/usr/bin/env bash
# Bootstrap COC OMR Laravel API on Ubuntu 22.04 (Oracle Cloud Always Free VM).
# Run on the server: sudo bash deploy/setup_oracle_api.sh
set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/coc-omr-api}"
API_DOMAIN="${API_DOMAIN:-}"
DB_NAME="${DB_NAME:-coc_omr}"
DB_USER="${DB_USER:-coc_omr}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)}"

if [[ "${EUID:-}" -ne 0 ]]; then
  echo "Run as root: sudo bash deploy/setup_oracle_api.sh"
  exit 1
fi

if [[ ! -f "$APP_DIR/artisan" ]]; then
  echo "Laravel app not found at $APP_DIR — copy coc-omr-api/ there first."
  exit 1
fi

echo "==> Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx postgresql php8.2-fpm php8.2-cli php8.2-{mbstring,xml,curl,zip,bcmath,pgsql} \
  composer certbot python3-certbot-nginx ufw

echo "==> PostgreSQL database..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo "==> Composer install..."
cd "$APP_DIR"
export COMPOSER_ALLOW_SUPERUSER=1
sudo -u www-data composer install --no-dev --optimize-autoloader --no-interaction

if [[ ! -f .env ]]; then
  sudo -u www-data cp .env.example .env
fi

echo "==> Writing production .env values..."
sudo -u www-data php artisan key:generate --force 2>/dev/null || sudo -u www-data php artisan key:generate

set_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${val}|" .env
  else
    echo "${key}=${val}" >> .env
  fi
}

set_env APP_ENV production
set_env APP_DEBUG false
set_env LOG_LEVEL warning
set_env DB_CONNECTION pgsql
set_env DB_HOST 127.0.0.1
set_env DB_PORT 5432
set_env DB_DATABASE "$DB_NAME"
set_env DB_USERNAME "$DB_USER"
set_env DB_PASSWORD "$DB_PASS"
set_env AUTO_VERIFY_EMAIL false
set_env MAIL_MAILER log

if [[ -n "$API_DOMAIN" ]]; then
  set_env APP_URL "https://${API_DOMAIN}"
fi

sudo -u www-data php artisan migrate --force
chown -R www-data:www-data storage bootstrap/cache
chmod -R ug+rwx storage bootstrap/cache

echo "==> Nginx site..."
if [[ -n "$API_DOMAIN" ]]; then
  sed "s/__API_DOMAIN__/${API_DOMAIN}/g" "$APP_DIR/deploy/nginx-coc-omr-api.conf" \
    > /etc/nginx/sites-available/coc-omr-api
else
  sed "s/__API_DOMAIN__/_/g" "$APP_DIR/deploy/nginx-coc-omr-api.conf" \
    | sed 's/server_name _;/server_name _ default_server;/' \
    > /etc/nginx/sites-available/coc-omr-api
fi

ln -sf /etc/nginx/sites-available/coc-omr-api /etc/nginx/sites-enabled/coc-omr-api
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now php8.2-fpm nginx
systemctl reload nginx

echo "==> Firewall (ufw)..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable || true

echo ""
echo "=============================================="
echo " COC OMR API installed at $APP_DIR"
echo "=============================================="
echo "Database: $DB_NAME / user $DB_USER"
echo "Password: $DB_PASS"
echo "(Save this password — also in $APP_DIR/.env)"
echo ""
if [[ -n "$API_DOMAIN" ]]; then
  echo "Run certbot:"
  echo "  certbot --nginx -d $API_DOMAIN"
else
  echo "Set API_DOMAIN and point DNS to this VM, then:"
  echo "  export API_DOMAIN=api.your-subdomain.example"
  echo "  certbot --nginx -d \$API_DOMAIN"
fi
echo ""
echo "Then edit $APP_DIR/.env:"
echo "  FRONTEND_URL=https://YOUR-APP.vercel.app"
echo "  SANCTUM_STATEFUL_DOMAINS=YOUR-APP.vercel.app,\$API_DOMAIN"
echo "  php artisan config:cache"
echo ""
echo "Health: curl http://localhost/up"
