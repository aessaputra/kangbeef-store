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
    
    # Create log files if they don't exist to avoid permission issues
    touch /var/log/apache2/error.log /var/log/apache2/access.log
    chown www-data:www-data /var/log/apache2/error.log /var/log/apache2/access.log
    chmod 644 /var/log/apache2/error.log /var/log/apache2/access.log
    
    # Debug: Check if we can access /proc/self/fd/2
    echo "DEBUG: Checking /proc/self/fd/2 access..."
    ls -la /proc/self/fd/ || echo "DEBUG: Cannot list /proc/self/fd"
    test -w /proc/self/fd/2 && echo "DEBUG: /proc/self/fd/2 is writable" || echo "DEBUG: /proc/self/fd/2 is NOT writable"
    
    # Debug: Show current user and groups
    echo "DEBUG: Current user: $(id)"
    echo "DEBUG: Current user groups: $(groups)"
    
    # Debug: Check log files permissions
    echo "DEBUG: Log files permissions:"
    ls -la /var/log/apache2/
fi

# Execute the main command as www-data
exec gosu www-data "$@"