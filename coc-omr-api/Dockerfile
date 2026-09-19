FROM dunglas/frankenphp:1-php8.2-bookworm

# Concurrent HTTP (unlike `php artisan serve`) so /up health checks are not
# blocked by a slow Neon query on another request — that was flapping Render.
# zip is required for `composer install` (FrankenPHP base has neither zip nor unzip).
RUN install-php-extensions pdo_pgsql bcmath zip \
    && apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY . .

RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwx storage bootstrap/cache

ENV PORT=8000
EXPOSE 8000

# Render injects PORT. Migrate then serve Laravel's public/ with FrankenPHP.
CMD php artisan migrate --force \
    && frankenphp php-server --listen ":${PORT}" --root public
