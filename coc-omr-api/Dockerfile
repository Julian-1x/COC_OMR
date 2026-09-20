FROM php:8.2-apache-bookworm

# Why Apache (not artisan serve / FrankenPHP):
# - artisan serve is single-threaded: a slow /api/me (~3–4s) blocks /up,
#   Render's health check times out (~5s), the instance restarts → public 502.
# - FrankenPHP is blocked on Render (Operation not permitted / exit 126).
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
      '    Options FollowSymLinks' \
      '    AllowOverride All' \
      '    Require all granted' \
      '    CGIPassAuth On' \
      '</Directory>' \
      > /etc/apache2/conf-available/laravel-override.conf \
    && a2enconf laravel-override \
    && echo 'ServerName localhost' >> /etc/apache2/apache2.conf

WORKDIR /var/www/html
COPY . .

RUN composer install --no-dev --optimize-autoloader --no-interaction \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwx storage bootstrap/cache

# Render sets PORT at runtime (often 10000). Do not bake a fixed Listen port.
ENV PORT=10000
EXPOSE 10000

COPY docker/render-apache-start.sh /usr/local/bin/render-apache-start.sh
RUN chmod +x /usr/local/bin/render-apache-start.sh

CMD ["render-apache-start.sh"]
