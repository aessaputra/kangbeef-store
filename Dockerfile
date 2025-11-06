# syntax=docker/dockerfile:1

# -------- Stage 1: Composer dependencies --------
FROM php:8.3-cli AS vendor
# Install Composer and required PHP extensions
RUN set -eux; \
    buildDeps="zlib1g-dev libzip-dev libicu-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev libgmp-dev $PHPIZE_DEPS libmagickwand-dev"; \
    apt-get update; \
    apt-get install -y --no-install-recommends $buildDeps curl; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd intl bcmath gmp exif pdo_mysql zip calendar; \
    pecl install imagick; docker-php-ext-enable imagick; \
    apt-get purge -y --auto-remove $buildDeps; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*; \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /app
# Copy composer files first to leverage Docker cache
COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/cache \
    COMPOSER_CACHE_DIR=/tmp/cache \
    composer install --no-dev --prefer-dist --no-interaction --no-ansi --no-progress
# Copy application code and optimize autoloader
COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative

# -------- Stage 2: Frontend (Vite) --------
FROM node:20-alpine AS frontend
WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=2048
# Copy package files first to leverage Docker cache
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --fund=false
# Copy application code and build
COPY . .
RUN npm run build

# -------- Stage 3: Runtime Apache + PHP 8.3 --------
FROM php:8.3-apache AS production

# One block: install build dependencies + runtime utilities, build extensions, then purge build dependencies
# Install PHP extensions & Imagick
RUN set -eux; \
    buildDeps=" \
        zlib1g-dev \
        libzip-dev \
        libicu-dev \
        libjpeg-dev \
        libpng-dev \
        libwebp-dev \
        libfreetype6-dev \
        libgmp-dev \
        $PHPIZE_DEPS \
        libmagickwand-dev \
    "; \
    runtimeDeps="curl gosu imagemagick"; \
    apt-get update; \
    apt-get install -y --no-install-recommends $buildDeps $runtimeDeps; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd intl bcmath gmp exif pdo_mysql zip; \
    pecl install imagick; \
    docker-php-ext-enable imagick; \
    apt-get purge -y --auto-remove $PHPIZE_DEPS libmagickwand-dev; \
    rm -rf /var/lib/apt/lists/*

# Production OPcache configuration
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

# Apache: modules & vhost configuration for /public
RUN a2enmod rewrite headers expires remoteip
COPY docker/apache-vhost.conf /etc/apache2/sites-available/000-default.conf
RUN sed -i 's#/var/www/html#/var/www/html/public#g' /etc/apache2/sites-available/000-default.conf \
 && sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/ports.conf \
 && echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Copy application + build results with proper ownership
WORKDIR /var/www/html
COPY --chown=www-data:www-data . .
COPY --from=vendor   --chown=www-data:www-data /app/vendor            /var/www/html/vendor
COPY --from=vendor   --chown=www-data:www-data /app/bootstrap/cache   /var/www/html/bootstrap/cache
COPY --from=frontend --chown=www-data:www-data /app/public/build      /var/www/html/public/build

# Set minimum permissions for writable directories
RUN chmod -R 775 storage bootstrap/cache

# Create entrypoint script to handle volume permissions
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

# Clean build-time cache (without DB)
RUN php artisan config:clear 2>/dev/null || echo "Config clear failed" \
 && php artisan route:clear 2>/dev/null || echo "Route clear failed" \
 && php artisan view:clear 2>/dev/null || echo "View clear failed"

# Declare volumes for persistent data
VOLUME ["/var/www/html/storage", "/var/www/html/bootstrap/cache"]

EXPOSE 8080
CMD ["apache2-foreground"]
