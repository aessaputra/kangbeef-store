# syntax=docker/dockerfile:1

# -------- Stage 1: Composer dependencies --------
# Note: Platform akan di-handle oleh buildx dengan --platform flag saat build
FROM php:8.3-cli AS vendor_stage

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN set -eux; \
    buildDeps=(zlib1g-dev libzip-dev libicu-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev libgmp-dev autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c libmagickwand-dev); \
    runtimeDeps=(libzip5 libpng16-16 libjpeg62-turbo libwebp7 libfreetype6 libgmp10 libicu76 libgomp1 imagemagick curl); \
    apt-get update; \
    apt-get install -y --no-install-recommends "${buildDeps[@]}" "${runtimeDeps[@]}"; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd intl bcmath gmp exif pdo_mysql zip calendar; \
    docker-php-ext-enable gd intl bcmath gmp exif pdo_mysql zip calendar; \
    pecl install imagick; docker-php-ext-enable imagick; \
    apt-get purge -y --auto-remove $buildDeps; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*; \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /app

COPY composer.json composer.lock ./

RUN --mount=type=cache,target=/tmp/cache \
    COMPOSER_CACHE_DIR=/tmp/cache \
    composer install --no-dev --prefer-dist --no-interaction --no-ansi --no-progress --no-scripts

COPY . .

RUN composer run-script post-autoload-dump && composer dump-autoload --optimize --classmap-authoritative

# -------- Stage 2: Frontend (Vite) --------
# Note: Platform akan di-handle oleh buildx dengan --platform flag saat build
FROM node:20-alpine AS frontend_stage

WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=2048

COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --fund=false

COPY . .
RUN npm run build

# -------- Stage 3: Runtime Apache + PHP 8.3 --------
# Note: Platform akan di-handle oleh buildx dengan --platform flag saat build
# Base images (php:8.3-apache, php:8.3-cli, node:20-alpine) sudah support ARM64
FROM php:8.3-apache AS production

ARG PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install PHP extensions & Imagick
# hadolint ignore=DL3008
RUN set -eux; \
    buildDeps=(zlib1g-dev libzip-dev libicu-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev libgmp-dev $PHPIZE_DEPS libmagickwand-dev); \
    runtimeDeps=(libzip5 libpng16-16 libjpeg62-turbo libwebp7 libfreetype6 libgmp10 libicu76 libgomp1 imagemagick curl gosu); \
    apt-get update; \
    apt-get install -y --no-install-recommends "${buildDeps[@]}" "${runtimeDeps[@]}"; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd intl bcmath gmp exif pdo_mysql zip; \
    pecl install imagick redis; \
    docker-php-ext-enable imagick redis; \
    apt-get purge -y --auto-remove autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c libmagickwand-dev; \
    rm -rf /var/lib/apt/lists/*

# OPcache production
RUN { \
      echo "opcache.enable=1"; \
      echo "opcache.enable_cli=1"; \
      echo "opcache.validate_timestamps=0"; \
      echo "opcache.jit=disable"; \
      echo "opcache.memory_consumption=192"; \
      echo "opcache.interned_strings_buffer=16"; \
      echo "opcache.max_accelerated_files=100000"; \
     } > /usr/local/etc/php/conf.d/opcache.ini

# php.ini override
COPY docker/php.ini /usr/local/etc/php/conf.d/zz-app.ini

# Apache: serve /public on 8080
RUN a2enmod rewrite headers expires remoteip
COPY docker/apache-vhost.conf /etc/apache2/sites-available/000-default.conf
RUN sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/ports.conf \
  && echo "ServerName localhost" >> /etc/apache2/apache2.conf \
  && echo "ErrorLog /proc/self/fd/2" >> /etc/apache2/apache2.conf \
  && a2ensite 000-default \
  && mkdir -p /var/log/apache2 \
  && chown -R www-data:www-data /var/log/apache2 \
  && chmod -R 755 /var/log/apache2

WORKDIR /var/www/html

# Copy source
COPY --chown=www-data:www-data . .

# Override dengan hasil build dari stage
COPY --from=vendor_stage   --chown=www-data:www-data /app/vendor            /var/www/html/vendor
COPY --from=vendor_stage   --chown=www-data:www-data /app/bootstrap/cache   /var/www/html/bootstrap/cache
COPY --from=frontend_stage --chown=www-data:www-data /app/public/build      /var/www/html/public/build

# Permissions
RUN chmod -R 775 storage bootstrap/cache

# Copy entrypoint script
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

# Bersihkan cache Laravel (tanpa DB)
RUN php artisan config:clear 2>/dev/null || echo "Config clear failed" \
  && php artisan route:clear 2>/dev/null || echo "Route clear failed" \
  && php artisan view:clear 2>/dev/null || echo "View clear failed"

VOLUME ["/var/www/html/storage", "/var/www/html/bootstrap/cache"]

EXPOSE 8080
CMD ["apache2-foreground"]
