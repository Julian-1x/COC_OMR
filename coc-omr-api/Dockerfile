FROM php:8.2-cli-bookworm

# Proven Render setup for this repo (previously Live for months).
# Do not switch to FrankenPHP on Render — its binary is blocked (exit 126).
# Desk stuck-loop is fixed on the web side (/me retry + warming checks /me).
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev unzip git \
    && docker-php-ext-install pdo_pgsql bcmath \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY . .

RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwx storage bootstrap/cache

ENV PORT=8000
EXPOSE 8000

# Render injects PORT. Keep this CMD — it is the known-working start path.
CMD php artisan migrate --force && \
    php artisan serve --host=0.0.0.0 --port=${PORT}
