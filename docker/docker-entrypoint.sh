#!/bin/sh

set -e

# Check if storage and cache directories have correct permissions
# Fix ownership if running as root (first run with named volumes)
if [ "$(id -u)" = '0' ]; then
    # Ensure storage and cache directories are owned by www-data
    chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
    # Ensure proper permissions
    chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache
    
    # Ensure Apache log directory exists and has correct permissions
    mkdir -p /var/log/apache2
    chown -R www-data:www-data /var/log/apache2
    chmod -R 755 /var/log/apache2
fi

# Execute the main command as www-data
exec gosu www-data "$@"