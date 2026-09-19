#!/bin/bash
set -euo pipefail

PORT="${PORT:-10000}"

# Point Apache at Render's assigned port (default image listens on 80).
sed -i "s/^Listen .*/Listen ${PORT}/" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:.*>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

php artisan migrate --force
php artisan config:cache || true
php artisan route:cache || true

exec apache2-foreground
