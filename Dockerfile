# -------- Stage 3: Runtime Apache + PHP 8.3 --------
FROM php:8.3-apache AS production

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
    runtimeDeps="curl gosu imagemagick libwebp7 libgomp1 libicu76"; \
    apt-get update; \
    apt-get install -y --no-install-recommends $buildDeps $runtimeDeps; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd intl bcmath gmp exif pdo_mysql zip; \
    pecl install imagick; \
    docker-php-ext-enable imagick; \
    apt-get purge -y --auto-remove $PHPIZE_DEPS libmagickwand-dev; \
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

# Apache config (serve /public via port 8080)
RUN a2enmod rewrite headers expires remoteip
COPY docker/apache-vhost.conf /etc/apache2/sites-available/000-default.conf
RUN sed -i 's#/var/www/html#/var/www/html/public#g' /etc/apache2/sites-available/000-default.conf \
 && sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/ports.conf \
 && echo "ServerName localhost" >> /etc/apache2/apache2.conf

WORKDIR /var/www/html

# Copy code dasar (pastikan ini SETELAH semua stage build)
COPY --chown=www-data:www-data . .

# Override dengan hasil build vendor & frontend
COPY --from=vendor   --chown=www-data:www-data /app/vendor            /var/www/html/vendor
COPY --from=vendor   --chown=www-data:www-data /app/bootstrap/cache   /var/www/html/bootstrap/cache
COPY --from=frontend --chown=www-data:www-data /app/public/build      /var/www/html/public/build

# Permission minimal
RUN chmod -R 775 storage bootstrap/cache

# Entrypoint: pastikan LF + executable (fix CRLF di dalam image)
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

# Bersihkan cache Laravel (tanpa butuh DB)
RUN php artisan config:clear 2>/dev/null || echo "Config clear failed" \
 && php artisan route:clear 2>/dev/null || echo "Route clear failed" \
 && php artisan view:clear 2>/dev/null || echo "View clear failed"

VOLUME ["/var/www/html/storage", "/var/www/html/bootstrap/cache"]

EXPOSE 8080
CMD ["apache2-foreground"]
