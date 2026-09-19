FROM php:8.2-apache-bookworm

# Concurrent HTTP (unlike `php artisan serve`) so /up health checks are not
# blocked by a slow Neon query on another request — that was flapping Render.
# FrankenPHP was tried first but Render's sandbox returns "Operation not permitted".
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev unzip git \
    && docker-php-ext-install pdo_pgsql bcmath \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && printf '%s\n' \
      '<Directory ${APACHE_DOCUMENT_ROOT}>' \
      '    AllowOverride All' \
      '    Require all granted' \
      '</Directory>' \
      > /etc/apache2/conf-available/laravel-override.conf \
    && a2enconf laravel-override

WORKDIR /var/www/html
COPY . .

RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwx storage bootstrap/cache

ENV PORT=8000
EXPOSE 8000

# Render injects PORT. Retarget Apache, migrate, then serve.
CMD sed -i "s/Listen 80/Listen ${PORT}/" /etc/apache2/ports.conf \
    && sed -i "s/:80>/:${PORT}>/" /etc/apache2/sites-available/000-default.conf \
    && php artisan migrate --force \
    && apache2-foreground
