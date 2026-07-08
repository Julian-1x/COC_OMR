FROM php:8.2-cli-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev unzip git \
    && docker-php-ext-install pdo_pgsql bcmath \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY . .

RUN composer install --no-dev --optimize-autoloader --no-interaction

ENV PORT=8000
EXPOSE 8000

# Render sets DATABASE_URL; Laravel reads it via config/database.php when configured.
CMD php artisan migrate --force && \
    php artisan serve --host=0.0.0.0 --port=${PORT}
