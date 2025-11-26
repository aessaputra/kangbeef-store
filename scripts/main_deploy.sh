#!/usr/bin/env bash
# ==============================================================================
# Kangbeef Deployment Script
# Location: /home/kangbeef/web/kangbeef.com/private/main_deploy.sh
# ==============================================================================
# This script handles zero-downtime deployments with automatic cleanup of old
# releases. It supports both production (main) and staging (dev) environments.
# ==============================================================================
set -euo pipefail
# ==============================================================================
# ARGUMENTS
# ==============================================================================
TIMESTAMP=${1:-$(date +%Y%m%d%H%M%S)}
BRANCH=${2:-main}
# ==============================================================================
# ENVIRONMENT CONFIGURATION
# ==============================================================================
# Determine domain based on branch
if [ "$BRANCH" == "main" ]; then
  DOMAIN="kangbeef.com"
elif [ "$BRANCH" == "dev" ]; then
  DOMAIN="staging.kangbeef.com"
else
  echo "ERROR: Unknown branch '$BRANCH'. Only 'main' and 'dev' are supported."
  exit 1
fi
# ==============================================================================
# PATH CONFIGURATION
# ==============================================================================
HESTIA_USER="kangbeef"
RELEASES_DIR="/home/kangbeef/web/${DOMAIN}/private/releases"
SHARED_DIR="/home/kangbeef/web/${DOMAIN}/private/shared"
CURRENT_LINK="/home/kangbeef/web/${DOMAIN}/private/current"
PUBLIC_HTML="/home/kangbeef/web/${DOMAIN}/public_html"
# User and group for file permissions
WEB_USER="kangbeef"
WEB_GROUP="www-data"
# ==============================================================================
# BINARY PATHS
# ==============================================================================
PHP_CLI="/usr/bin/php8.3"
COMPOSER="${COMPOSER:-$(command -v composer || true)}"
NPM_CMD="${NPM_CMD:-$(command -v npm || true)}"
# ==============================================================================
# CLEANUP CONFIGURATION
# ==============================================================================
KEEP_RELEASES=5  # Number of releases to keep (older ones will be deleted)
# ==============================================================================
# VALIDATION: REQUIRED DIRECTORIES
# ==============================================================================
if [ ! -d "${RELEASES_DIR}" ]; then
  echo "ERROR: RELEASES_DIR (${RELEASES_DIR}) does not exist."
  exit 1
fi
if [ ! -d "${SHARED_DIR}" ]; then
  echo "ERROR: SHARED_DIR (${SHARED_DIR}) does not exist."
  exit 1
fi
# Create PUBLIC_HTML directory if it doesn't exist (will be replaced with symlink later)
if [ ! -d "${PUBLIC_HTML}" ] && [ ! -L "${PUBLIC_HTML}" ]; then
  echo "Creating PUBLIC_HTML directory: ${PUBLIC_HTML}"
  mkdir -p "${PUBLIC_HTML}"
fi
# ==============================================================================
# RELEASE DIRECTORY SETUP
# ==============================================================================
# RELEASE_DIR can be passed as environment variable from GitHub Actions
# If not provided, construct it from RELEASES_DIR and TIMESTAMP
if [ -z "${RELEASE_DIR:-}" ]; then
  RELEASE_DIR="${RELEASES_DIR}/${TIMESTAMP}"
fi
# ==============================================================================
# DEPLOYMENT START
# ==============================================================================
echo "========================================================================"
echo "  DEPLOYMENT START"
echo "========================================================================"
echo "Timestamp    : ${TIMESTAMP}"
echo "Branch       : ${BRANCH}"
echo "Domain       : ${DOMAIN}"
echo "Release Dir  : ${RELEASE_DIR}"
echo "========================================================================"
# Ensure required directories exist
mkdir -p "${RELEASES_DIR}" "${SHARED_DIR}"
# ==============================================================================
# SHARED ENVIRONMENT FILE (.env)
# ==============================================================================
# Validate that shared .env exists
if [ ! -f "${SHARED_DIR}/.env" ]; then
  echo "ERROR: Shared .env file not found at ${SHARED_DIR}/.env"
  echo "Please create the .env file before deploying."
  exit 1
fi
# Symlink shared .env to release directory
echo "Linking shared .env to release..."
ln -sfn "${SHARED_DIR}/.env" "${RELEASE_DIR}/.env"
# ==============================================================================
# SHARED STORAGE
# ==============================================================================
# Link shared storage directory if it exists
if [ -d "${SHARED_DIR}/storage" ]; then
  echo "Linking shared storage..."
  rm -rf "${RELEASE_DIR}/public/storage" || true
  ln -sfn "${SHARED_DIR}/storage" "${RELEASE_DIR}/public/storage" || true
fi
# ==============================================================================
# DEPENDENCIES INSTALLATION
# ==============================================================================
cd "${RELEASE_DIR}"
# Install Composer dependencies
echo "Installing Composer dependencies..."
if command -v composer >/dev/null 2>&1; then
  # For staging (dev branch), install WITH dev dependencies to include debugbar
  if [ "$BRANCH" == "dev" ]; then
    echo "→ Installing WITH dev dependencies (staging - includes debugbar)..."
    composer install \
      --prefer-dist \
      --optimize-autoloader \
      --no-interaction \
      --no-progress
  else
    # For production (main branch), install WITHOUT dev dependencies
    echo "→ Installing WITHOUT dev dependencies (production - no debugbar)..."
    composer install \
      --no-dev \
      --prefer-dist \
      --optimize-autoloader \
      --no-interaction \
      --no-progress
  fi
else
  echo "ERROR: Composer not found in PATH."
  exit 1
fi
# Build frontend assets if npm and package.json exist
if command -v npm >/dev/null 2>&1 && [ -f package.json ]; then
  echo "Building frontend assets..."
  npm ci --silent
  npm run build
else
  echo "Skipping asset build (npm or package.json not found)"
fi
# ==============================================================================
# MAINTENANCE MODE & DATABASE MIGRATION
# ==============================================================================
echo "Enabling maintenance mode..."
${PHP_CLI} artisan down --no-interaction || true
echo "Running database migrations..."
${PHP_CLI} artisan migrate --force
# ==============================================================================
# CACHE OPTIMIZATION
# ==============================================================================
echo "Optimizing cache..."
${PHP_CLI} artisan cache:clear    || true
${PHP_CLI} artisan config:cache   || true
${PHP_CLI} artisan route:cache    || true
${PHP_CLI} artisan view:cache     || true
# ==============================================================================
# SYMLINK SWITCHING (ATOMIC DEPLOYMENT)
# ==============================================================================
echo "Switching to new release..."

# This prevents the issue where ln -sfn creates a link inside the directory
if [ -d "${CURRENT_LINK}" ] && [ ! -L "${CURRENT_LINK}" ]; then
  echo "WARNING: ${CURRENT_LINK} is a directory, not a symlink. Removing it..."
  rm -rf "${CURRENT_LINK}"
fi

# Use RELATIVE path to prevent staging from linking to production
# Extract just the release timestamp from RELEASE_DIR
RELEASE_NAME=$(basename "${RELEASE_DIR}")
cd "$(dirname "${CURRENT_LINK}")" || exit 1
ln -sfn "releases/${RELEASE_NAME}" "$(basename "${CURRENT_LINK}")"
cd - > /dev/null || true

echo "Updating public_html symlink..."
# Remove default public_html directory if it exists and is not a symlink
if [ -d "${PUBLIC_HTML}" ] && [ ! -L "${PUBLIC_HTML}" ]; then
  echo "Removing default public_html directory..."
  rm -rf "${PUBLIC_HTML}"
fi

# Link public_html to current release public directory
ln -sfn "${CURRENT_LINK}/public" "${PUBLIC_HTML}"
# ==============================================================================
# SET PERMISSIONS
# ==============================================================================
echo "Setting correct permissions..."

# Set base permissions for all files and directories
find "${RELEASE_DIR}" -type d -exec chmod 755 {} \; || true
find "${RELEASE_DIR}" -type f -exec chmod 644 {} \; || true

# Make artisan executable
chmod 755 "${RELEASE_DIR}/artisan" || true

# Laravel requires writable storage and bootstrap/cache
chmod -R 775 "${RELEASE_DIR}/storage" || true
chmod -R 775 "${RELEASE_DIR}/bootstrap/cache" || true

# If using shared storage, also set permissions there
if [ -d "${SHARED_DIR}/storage" ]; then
  chmod -R 775 "${SHARED_DIR}/storage" || true
fi

echo "✓ Permissions set"

# ==============================================================================
# DISABLE MAINTENANCE MODE
# ==============================================================================
echo "Disabling maintenance mode..."
${PHP_CLI} artisan up --no-interaction || true
# ==============================================================================
# CLEANUP OLD RELEASES
# ==============================================================================
echo "Cleaning up old releases (keeping ${KEEP_RELEASES} most recent)..."
cd "${RELEASES_DIR}" || {
  echo "ERROR: Cannot access releases directory ${RELEASES_DIR}"
  exit 1
}
# Count total releases
TOTAL_RELEASES=$(ls -1 | wc -l)
echo "Total releases found: ${TOTAL_RELEASES}"
# Only cleanup if we have more than KEEP_RELEASES
if [ "${TOTAL_RELEASES}" -gt "${KEEP_RELEASES}" ]; then
  TO_DELETE=$((TOTAL_RELEASES - KEEP_RELEASES))
  echo "Removing ${TO_DELETE} old release(s)..."

  # List releases sorted by time (newest first), skip the newest ones, and delete the rest
  ls -t | tail -n +"$((KEEP_RELEASES + 1))" | while read -r old_release; do
    echo "  → Removing: ${old_release}"
    rm -rf "${old_release}"
  done

  echo "✓ Cleanup completed. ${KEEP_RELEASES} releases retained."
else
  echo "✓ No cleanup needed (${TOTAL_RELEASES} <= ${KEEP_RELEASES})"
fi
# Return to release directory
cd - > /dev/null || true
# ==============================================================================
# DEPLOYMENT COMPLETE
# ==============================================================================
echo "========================================================================"
echo "  DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "========================================================================"
echo "Timestamp    : ${TIMESTAMP}"
echo "Branch       : ${BRANCH}"
echo "Domain       : ${DOMAIN}"
echo "Active       : ${CURRENT_LINK} → ${RELEASE_DIR}"
echo "========================================================================"
