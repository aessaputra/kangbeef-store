/**
 * Jenkins Pipeline untuk Kangbeef Store - ARM64 Architecture
 * 
 * Cross-Platform Build Support:
 * - Jenkins Server: AMD64 (build machine)
 * - Deployment Server: ARM64 (target machine)
 * - Build Method: Docker Buildx dengan QEMU emulation
 * 
 * Best Practices Applied (berdasarkan Jenkins Documentation):
 * - Declarative Pipeline syntax untuk maintainability
 * - Parameterized builds untuk flexibility
 * - Parallel execution untuk optimasi waktu build
 * - Combined shell commands untuk mengurangi overhead
 * - Proper error handling dengan set -euxo pipefail
 * - Timeout handling untuk mencegah hanging builds
 * - Artifact archiving dengan fingerprinting
 * - Proper credential management dengan withCredentials
 * - Health checks dan validation sebelum deployment
 * - Cleanup di post section untuk resource management
 * - Cross-platform build (AMD64 -> ARM64) dengan QEMU emulation
 * 
 * Architecture:
 * - Build Platform: linux/amd64 (Jenkins server)
 * - Target Platform: linux/arm64 (deployment server)
 * 
 * Note: Build time mungkin lebih lama karena emulasi ARM64 pada AMD64
 */

pipeline {
    agent any

    parameters {
        choice(
            name: 'DEPLOY_ENV',
            choices: ['skip', 'staging', 'production'],
            description: 'Environment untuk deployment (skip = hanya build)'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip image testing stage'
        )
        booleanParam(
            name: 'SKIP_LINT',
            defaultValue: false,
            description: 'Skip Dockerfile linting'
        )
        string(
            name: 'IMAGE_TAG_SUFFIX',
            defaultValue: '',
            description: 'Suffix untuk image tag (optional, e.g., -rc1)'
        )
    }

    environment {
        // Registry configuration
        REGISTRY                 = "docker.io"
        IMAGE_NAME               = "aessaputra/kangbeef-store"
        
        // Deployment configuration
        DEPLOY_USER              = "kangbeef"
        DEPLOY_HOST              = "168.138.171.60"
        DEPLOY_PATH              = "/home/kangbeef/web/kangbeef.com/docker_app"
        BACKUP_PATH              = "/home/kangbeef/web/kangbeef.com/private"
        
        // Docker configuration
        DOCKER_BUILDKIT          = "1"
        COMPOSE_DOCKER_CLI_BUILD = "1"
        
        // Architecture configuration - ARM64 only
        TARGET_PLATFORM          = "linux/arm64"
        
        // Computed values
        IMAGE_TAG                = "${BUILD_NUMBER}${params.IMAGE_TAG_SUFFIX}"
        FULL_IMAGE_NAME          = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        LATEST_IMAGE_NAME        = "${REGISTRY}/${IMAGE_NAME}:latest"
        
        // Timeouts (in seconds)
        DB_HEALTH_CHECK_TIMEOUT  = "60"
        APP_HEALTH_CHECK_TIMEOUT = "60"
        SSH_TIMEOUT              = "10"
    }

    options {
        // Prevent concurrent builds
        disableConcurrentBuilds()
        
        // Build history retention
        buildDiscarder(
            logRotator(
                daysToKeepStr: '14',
                numToKeepStr: '10',
                artifactDaysToKeepStr: '7',
                artifactNumToKeepStr: '5'
            )
        )
        
        // Skip default checkout (we do it manually)
        skipDefaultCheckout(true)
        
        // Pipeline timeout - increased for cross-platform build (AMD64 -> ARM64)
        // Cross-platform build dengan emulasi memerlukan waktu lebih lama (60-90+ menit)
        // Timeout set to 24 hours (1440 minutes) untuk memastikan build selesai
        timeout(time: 1440, unit: 'MINUTES')
        
        // Timestamps in console output
        timestamps()
    }

    stages {
        // Stage 1: Prepare Workspace
        stage('Prepare Workspace') {
            steps {
                script {
                    echo "🚀 Starting build #${BUILD_NUMBER}"
                    echo "📦 Image: ${FULL_IMAGE_NAME}"
                    echo "🌿 Branch: ${env.BRANCH_NAME ?: 'N/A'}"
                    echo "👤 User: ${env.BUILD_USER ?: 'N/A'}"
                }
                
                // Clean workspace
                cleanWs(
                    deleteDirs: true,
                    disableDeferredWipeout: true
                )
                
                // Checkout source code
                checkout scm
                
                // Archive source code as artifact
                archiveArtifacts artifacts: '**/*', allowEmptyArchive: true, fingerprint: true
            }
        }

        // Stage 2: Preflight Checks
        stage('Preflight Checks') {
            parallel {
                stage('Check Docker') {
                    steps {
                        script {
                            sh '''
                                echo "Checking Docker installation..."
                                docker version
                                docker compose version || docker-compose version || echo "⚠️ Docker Compose not found"
                            '''
                        }
                    }
                }
                
                stage('Check SSH Connection') {
                    steps {
                        withCredentials([sshUserPrivateKey(
                            credentialsId: 'prod-ssh',
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        )]) {
                            script {
                                sh '''
                                    echo "Checking SSH connection to ${DEPLOY_HOST}..."
                                    ssh -i "$SSH_KEY" \
                                        -o StrictHostKeyChecking=no \
                                        -o ConnectTimeout=${SSH_TIMEOUT} \
                                        -o BatchMode=yes \
                                        "$SSH_USER@${DEPLOY_HOST}" \
                                        "echo '✅ SSH connection successful' && (docker compose version || docker-compose version || echo '⚠️ Docker Compose not found on server')"
                                '''
                            }
                        }
                    }
                }
            }
        }

        // Stage 3: Lint Dockerfile (optional)
        stage('Lint Dockerfile') {
            when {
                expression { !params.SKIP_LINT }
            }
            steps {
                script {
                    echo "🔍 Linting Dockerfile..."
                    sh '''
                        set +e  # Don't fail on lint errors
                        docker pull hadolint/hadolint:latest || true
                        docker run --rm -i hadolint/hadolint < Dockerfile || echo "⚠️ Hadolint found issues (non-blocking)"
                        set -e
                    '''
                }
            }
        }

        // Stage 4: Build ARM64 Image
        stage('Build ARM64 Image') {
            options {
                // Stage-specific timeout untuk cross-platform build dengan emulasi
                // Cross-platform build (AMD64 -> ARM64) memerlukan waktu 60-90+ menit
                // Timeout set to 20 hours (1200 minutes) untuk memastikan build selesai
                timeout(time: 1200, unit: 'MINUTES')
                // Retry build jika gagal karena timeout atau network issue
                retry(2)
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    script {
                        echo "🏗️ Building ARM64 Docker image..."
                        
                        // Best Practice: Combine multiple shell commands into single sh step
                        sh '''
                            set -euxo pipefail
                            
                            # Login to Docker Hub
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin "$REGISTRY" || {
                                echo "❌ Docker login failed"
                                exit 1
                            }
                            
                            # Setup Docker context for DinD (Docker-in-Docker)
                            if ! docker context inspect dind >/dev/null 2>&1; then
                                echo "Creating Docker context 'dind'..."
                                docker context create dind \
                                    --docker "host=tcp://docker:2376,ca=/certs/client/ca.pem,cert=/certs/client/cert.pem,key=/certs/client/key.pem"
                            fi
                            
                            # Use DinD context
                            docker context use dind
                            
                            # Install QEMU/binfmt for cross-platform emulation (AMD64 -> ARM64)
                            # This allows building ARM64 images on AMD64 Jenkins server
                            echo "🔧 Installing QEMU/binfmt for ARM64 emulation..."
                            docker --context dind run --rm --privileged tonistiigi/binfmt --install linux/arm64 || {
                                echo "⚠️ QEMU/binfmt installation failed (may already be installed)"
                            }
                            
                            # Setup buildx builder for cross-platform (AMD64 -> ARM64)
                            # Driver: docker-container supports cross-platform builds
                            if ! docker buildx inspect kb-arm64-builder >/dev/null 2>&1; then
                                echo "Creating buildx builder 'kb-arm64-builder' for cross-platform build..."
                                echo "  Build platform: AMD64 (Jenkins server)"
                                echo "  Target platform: ARM64 (deployment server)"
                                docker buildx create \
                                    --name kb-arm64-builder \
                                    --driver docker-container \
                                    --use \
                                    --platform linux/amd64,linux/arm64 \
                                    dind || {
                                    echo "⚠️ Failed to create builder with docker-container driver, trying default..."
                                    docker buildx create \
                                        --name kb-arm64-builder \
                                        --use \
                                        --platform linux/amd64,linux/arm64 \
                                        dind
                                }
                            else
                                echo "Using existing buildx builder 'kb-arm64-builder'..."
                                docker buildx use kb-arm64-builder
                            fi
                            
                            # Inspect builder to verify cross-platform support
                            echo "🔍 Inspecting buildx builder capabilities..."
                            docker buildx inspect kb-arm64-builder
                            
                            # Verify builder supports ARM64
                            BUILDER_PLATFORMS=$(docker buildx inspect kb-arm64-builder --bootstrap 2>&1 | grep -i "platforms:" || echo "")
                            echo "📋 Builder platforms: ${BUILDER_PLATFORMS}"
                            
                            # Build and push ARM64 image from AMD64 Jenkins server
                            echo "🏗️ Building ARM64 image on AMD64 Jenkins server..."
                            echo "  Build platform: AMD64 (Jenkins server)"
                            echo "  Target platform: ${TARGET_PLATFORM} (deployment server)"
                            echo "  Image: ${FULL_IMAGE_NAME} and ${LATEST_IMAGE_NAME}"
                            echo ""
                            echo "ℹ️  Note: Cross-platform build menggunakan QEMU emulation"
                            echo "   Build time mungkin lebih lama karena emulasi ARM64"
                            echo "   Estimated time: 60-90 minutes (dengan emulasi)"
                            echo "   Stage timeout: 20 hours (1200 minutes)"
                            echo "   Pipeline timeout: 24 hours (1440 minutes)"
                            
                            # Use timeout wrapper to prevent hanging builds
                            # Add periodic output to prevent Jenkins agent timeout
                            echo "⏱️  Starting build with timeout protection..."
                            echo "   Build timeout: 20 hours (72000 seconds)"
                            echo "   Progress will be shown in real-time"
                            echo "   Keepalive output will be sent every 30 seconds to prevent agent timeout"
                            
                            # Start keepalive background process to prevent Jenkins agent timeout
                            # This sends periodic output every 30 seconds to keep agent connection alive
                            (
                                while true; do
                                    sleep 30
                                    echo "💓 [KEEPALIVE] Build still running... $(date '+%Y-%m-%d %H:%M:%S')"
                                done
                            ) &
                            KEEPALIVE_PID=$!
                            
                            # Function to cleanup keepalive on exit
                            cleanup_keepalive() {
                                if [ -n "${KEEPALIVE_PID}" ]; then
                                    kill "${KEEPALIVE_PID}" 2>/dev/null || true
                                    wait "${KEEPALIVE_PID}" 2>/dev/null || true
                                fi
                            }
                            trap cleanup_keepalive EXIT INT TERM
                            
                            echo "✅ Keepalive process started (PID: ${KEEPALIVE_PID})"
                            
                            # Check if timeout command is available
                            if command -v timeout >/dev/null 2>&1; then
                                echo "✅ Using timeout command for build protection"
                                # Build with timeout (72000 seconds = 20 hours)
                                timeout 72000 docker buildx build \
                                    --platform ${TARGET_PLATFORM} \
                                    --target production \
                                    --build-arg BUILDKIT_INLINE_CACHE=1 \
                                    --cache-from type=registry,ref="${LATEST_IMAGE_NAME}" \
                                    --push \
                                    --tag "${FULL_IMAGE_NAME}" \
                                    --tag "${LATEST_IMAGE_NAME}" \
                                    --progress=plain \
                                    --load=false \
                                    . || {
                                    BUILD_EXIT_CODE=$?
                                    echo "❌ Build failed or timed out after 20 hours (exit code: ${BUILD_EXIT_CODE})"
                                    cleanup_keepalive
                                    exit 1
                                }
                            else
                                echo "⚠️  Timeout command not available, building without timeout wrapper"
                                echo "   Jenkins stage timeout (20 hours) will handle timeout"
                                # Build without timeout wrapper (rely on Jenkins stage timeout)
                                docker buildx build \
                                    --platform ${TARGET_PLATFORM} \
                                    --target production \
                                    --build-arg BUILDKIT_INLINE_CACHE=1 \
                                    --cache-from type=registry,ref="${LATEST_IMAGE_NAME}" \
                                    --push \
                                    --tag "${FULL_IMAGE_NAME}" \
                                    --tag "${LATEST_IMAGE_NAME}" \
                                    --progress=plain \
                                    --load=false \
                                    . || {
                                    BUILD_EXIT_CODE=$?
                                    echo "❌ Build failed (exit code: ${BUILD_EXIT_CODE})"
                                    echo "   This might be due to:"
                                    echo "   1. Build timeout (20 hours)"
                                    echo "   2. Network issues"
                                    echo "   3. QEMU emulation issues"
                                    echo "   4. Insufficient resources"
                                    echo "   5. Build masih memerlukan waktu lebih lama"
                                    echo "   💡 Note: Pipeline timeout adalah 24 jam (1440 menit)"
                                    cleanup_keepalive
                                    exit 1
                                }
                            fi
                            
                            # Stop keepalive process after successful build
                            cleanup_keepalive
                            
                            # Verify build completed successfully
                            echo "✅ Build process completed"
                            
                            echo "✅ ARM64 image built and pushed successfully"
                            
                            # Wait a bit for registry to sync
                            echo "⏳ Waiting for registry to sync (10 seconds)..."
                            sleep 10
                            
                            # Verify ARM64 image
                            echo "🔍 Verifying ARM64 image..."
                            MAX_RETRIES=3
                            RETRY_COUNT=0
                            
                            while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                                if docker buildx imagetools inspect "${FULL_IMAGE_NAME}" 2>&1; then
                                    echo "✅ Image found in registry"
                                    break
                                else
                                    RETRY_COUNT=$((RETRY_COUNT + 1))
                                    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                                        echo "⚠️ Image not found yet, retrying in 10 seconds... (${RETRY_COUNT}/${MAX_RETRIES})"
                                        sleep 10
                                    else
                                        echo "❌ Failed to verify image after ${MAX_RETRIES} attempts"
                                        echo "   Image might still be syncing to registry"
                                        echo "   Will verify during deployment"
                                    fi
                                fi
                            done
                            
                            # Verify platform in manifest
                            MANIFEST_OUTPUT=$(docker buildx imagetools inspect "${FULL_IMAGE_NAME}" 2>&1 || echo "")
                            if echo "${MANIFEST_OUTPUT}" | grep -qiE "linux/arm64|arm64|aarch64"; then
                                echo "✅ ARM64 platform verified in manifest"
                            else
                                echo "⚠️ ARM64 platform not found in manifest output"
                                echo "   Will verify during deployment"
                            fi
                            
                            # Logout
                            docker logout "$REGISTRY" || true
                            
                            echo "✅ ARM64 image build and verification completed"
                        '''
                    }
                }
            }
        }

        // Stage 5: Test Image
        stage('Test Image') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    echo "🧪 Testing ARM64 Docker image..."
                    
                    // Best Practice: Combine shell commands to reduce overhead
                    sh '''
                        set -euxo pipefail
                        
                        IMAGE_TAG="${FULL_IMAGE_NAME}"
                        echo "Testing ARM64 image: ${IMAGE_TAG}"
                        
                        # Pull ARM64 image from registry
                        echo "Pulling ARM64 image from registry..."
                        docker pull --platform ${TARGET_PLATFORM} "${IMAGE_TAG}" || {
                            echo "❌ Failed to pull ARM64 image"
                            exit 1
                        }
                        
                        # Verify image architecture
                        IMAGE_ARCH=$(docker inspect "${IMAGE_TAG}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
                        echo "📦 Image architecture: ${IMAGE_ARCH}"
                        
                        if [ "${IMAGE_ARCH}" != "arm64" ] && [ "${IMAGE_ARCH}" != "aarch64" ]; then
                            echo "❌ Image is not ARM64 (got ${IMAGE_ARCH})"
                            exit 1
                        fi
                        echo "✅ Image architecture verified: ARM64"
                        
                        # Test PHP version
                        echo "Testing PHP version..."
                        docker run --rm --platform ${TARGET_PLATFORM} -e APP_ENV=testing "${IMAGE_TAG}" php -v || {
                            echo "❌ PHP version check failed"
                            exit 1
                        }
                        
                        # Test PHP extensions
                        echo "Testing PHP extensions..."
                        docker run --rm --platform ${TARGET_PLATFORM} "${IMAGE_TAG}" php -m > /tmp/phpm.txt || {
                            echo "❌ Failed to list PHP modules"
                            exit 1
                        }
                        
                        # Required extensions (using space-separated string for sh compatibility)
                        REQUIRED_EXTENSIONS="intl gd imagick pdo_mysql bcmath gmp exif zip"
                        MISSING_EXTENSIONS=""
                        
                        for ext in ${REQUIRED_EXTENSIONS}; do
                            if ! grep -qiE "^${ext}$" /tmp/phpm.txt; then
                                if [ -z "${MISSING_EXTENSIONS}" ]; then
                                    MISSING_EXTENSIONS="${ext}"
                                else
                                    MISSING_EXTENSIONS="${MISSING_EXTENSIONS} ${ext}"
                                fi
                            fi
                        done
                        
                        if [ -n "${MISSING_EXTENSIONS}" ]; then
                            echo "❌ Missing required PHP extensions: ${MISSING_EXTENSIONS}"
                            exit 1
                        fi
                        
                        echo "✅ All required PHP extensions are present"
                        echo "✅ ARM64 image testing completed successfully"
                        
                        # Cleanup test image
                        docker rmi "${IMAGE_TAG}" 2>/dev/null || true
                    '''
                }
            }
        }

        // Stage 6: Deploy to Server
        stage('Deploy') {
            when {
                anyOf {
                    expression { 
                        params.DEPLOY_ENV == 'production' || params.DEPLOY_ENV == 'staging'
                    }
                    expression {
                        (env.BRANCH_NAME == null || env.BRANCH_NAME == '' || env.BRANCH_NAME == 'main') && 
                        params.DEPLOY_ENV != 'skip'
                    }
                }
            }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    ),
                    sshUserPrivateKey(
                        credentialsId: 'prod-ssh',
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {
                    script {
                        echo "🚀 Deploying to ${params.DEPLOY_ENV} environment..."
                        
                        sh '''
                            set -euxo pipefail
                            
                            echo "📋 Deployment Configuration:"
                            echo "  Image: ${FULL_IMAGE_NAME}"
                            echo "  Host: ${DEPLOY_HOST}"
                            echo "  Path: ${DEPLOY_PATH}"
                            echo "  Backup: ${BACKUP_PATH}"
                            
                            # Ensure deployment directory exists
                            echo "Creating deployment directory..."
                            ssh -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=${SSH_TIMEOUT} \
                                "$SSH_USER@${DEPLOY_HOST}" \
                                "mkdir -p '${DEPLOY_PATH}' '${BACKUP_PATH}'"
                            
                            # Copy docker-compose.yml to server
                            echo "Copying docker-compose.yml to server..."
                            scp -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=no \
                                docker-compose.yml \
                                "$SSH_USER@${DEPLOY_HOST}:${DEPLOY_PATH}/docker-compose.yml"
                            
                            # Verify .env file exists on server
                            echo "Verifying .env file on server..."
                            ssh -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=${SSH_TIMEOUT} \
                                "$SSH_USER@${DEPLOY_HOST}" \
                                "if [ ! -f '${DEPLOY_PATH}/.env' ]; then \
                                    echo '❌ ERROR: .env file not found in ${DEPLOY_PATH} on server.'; \
                                    echo 'Please create it manually before deploying.'; \
                                    exit 1; \
                                fi && echo '✅ .env file found'"
                            
                            # Login to Docker on server
                            echo "Logging in to Docker on server..."
                            ssh -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=${SSH_TIMEOUT} \
                                "$SSH_USER@${DEPLOY_HOST}" \
                                "echo '$DOCKER_PASS' | docker login -u '$DOCKER_USER' --password-stdin '$REGISTRY'"
                            
                            # Execute deployment script on server (ARM64 only)
                            echo "Executing ARM64 deployment script on server..."
                            ssh -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=${SSH_TIMEOUT} \
                                "$SSH_USER@${DEPLOY_HOST}" \
                                "REGISTRY='${REGISTRY}' \
                                 IMAGE_NAME='${IMAGE_NAME}' \
                                 IMAGE_TAG='${IMAGE_TAG}' \
                                 TARGET_PLATFORM='${TARGET_PLATFORM}' \
                                 DEPLOY_PATH='${DEPLOY_PATH}' \
                                 BACKUP_PATH='${BACKUP_PATH}' \
                                 DB_HEALTH_CHECK_TIMEOUT='${DB_HEALTH_CHECK_TIMEOUT}' \
                                 APP_HEALTH_CHECK_TIMEOUT='${APP_HEALTH_CHECK_TIMEOUT}' \
                                 bash -s" << 'DEPLOY_SCRIPT'
#!/bin/bash
# Best Practice: Use set -euxo pipefail for better error handling
set -euxo pipefail

echo "📋 Remote Deployment Environment (ARM64):"
echo "  REGISTRY=${REGISTRY}"
echo "  IMAGE_NAME=${IMAGE_NAME}"
echo "  IMAGE_TAG=${IMAGE_TAG}"
echo "  TARGET_PLATFORM=${TARGET_PLATFORM}"
echo "  DEPLOY_PATH=${DEPLOY_PATH}"
echo "  BACKUP_PATH=${BACKUP_PATH}"

cd "${DEPLOY_PATH}"

APP_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
PLATFORM="${TARGET_PLATFORM}"
echo "📦 Using APP_IMAGE=${APP_IMAGE}"
echo "📱 Target Platform: ${PLATFORM} (ARM64 only)"

# Verify server architecture is ARM64
SERVER_ARCH=$(uname -m)
echo "🖥️  Server architecture: ${SERVER_ARCH}"

if [ "${SERVER_ARCH}" != "aarch64" ] && [ "${SERVER_ARCH}" != "arm64" ]; then
    echo "❌ ERROR: Server architecture (${SERVER_ARCH}) is not ARM64"
    echo "   This pipeline is configured for ARM64 only."
    echo "   Please use a different pipeline for other architectures."
    exit 1
fi
echo "✅ Server architecture verified: ARM64"

# Best Practice: Combine shell commands to reduce overhead
# Cleanup old images and containers
echo "🧹 Cleaning up old images and containers..."
docker images "${APP_IMAGE}" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true
docker ps -a --filter "ancestor=${APP_IMAGE}" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true

# Pull ARM64 image
echo "⬇️ Pulling ARM64 image: ${APP_IMAGE}..."
docker pull --platform "${PLATFORM}" "${APP_IMAGE}" || {
    echo "❌ Failed to pull ARM64 image"
    echo "   This will cause 'exec format error'. Aborting."
    exit 1
}

# Verify ARM64 image architecture
echo "🔍 Verifying ARM64 image architecture..."
IMAGE_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Image architecture: ${IMAGE_ARCH}"

if [ "${IMAGE_ARCH}" != "arm64" ] && [ "${IMAGE_ARCH}" != "aarch64" ]; then
    echo "❌ ERROR: Image architecture (${IMAGE_ARCH}) is not ARM64"
    echo "   This will cause 'exec format error'. Aborting."
    exit 1
fi
echo "✅ Verified: Image is ARM64"

# Set platform for docker compose
export DOCKER_DEFAULT_PLATFORM="${PLATFORM}"
echo "🔧 Set DOCKER_DEFAULT_PLATFORM=${PLATFORM}"

# Pull with docker compose
echo "⬇️ Pulling images with docker compose..."
docker compose pull app queue scheduler || echo "⚠️ Some image pulls failed, will use existing images"

# Stop existing stack gracefully
echo "🛑 Stopping existing stack..."
docker compose down --timeout 30 || true

# Start database first
echo "🗄️ Starting database container..."
docker compose up -d db

# Wait for database to be healthy
echo "⏳ Waiting for database to be healthy (max ${DB_HEALTH_CHECK_TIMEOUT}s)..."
DB_READY=false
for i in $(seq 1 ${DB_HEALTH_CHECK_TIMEOUT}); do
    if docker compose exec -T db mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "✅ Database is healthy"
        DB_READY=true
        break
    fi
    echo "  Waiting for database... (${i}/${DB_HEALTH_CHECK_TIMEOUT})"
    sleep 2
done

if [ "$DB_READY" != "true" ]; then
    echo "❌ Database failed to become healthy within ${DB_HEALTH_CHECK_TIMEOUT}s"
    exit 1
fi

# Final verification before starting containers
echo "🔍 Final verification before starting containers..."
FINAL_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
if [ "${FINAL_ARCH}" != "arm64" ] && [ "${FINAL_ARCH}" != "aarch64" ]; then
    echo "❌ CRITICAL: Image architecture (${FINAL_ARCH}) is not ARM64"
    echo "   This will cause 'exec format error'. Aborting."
    exit 1
fi
echo "✅ Verified: Image is ARM64, safe to start containers"

# Start Redis, App, Queue, and Scheduler
echo "🚀 Starting Redis, App, Queue, and Scheduler..."
echo "   Using APP_IMAGE=${APP_IMAGE}"
echo "   Using DOCKER_DEFAULT_PLATFORM=${PLATFORM}"
APP_IMAGE="${APP_IMAGE}" docker compose up -d redis app queue scheduler

# Verify containers started with ARM64 architecture
echo "🔍 Verifying container architectures..."
for service in app queue scheduler; do
    CONTAINER_ID=$(docker compose ps -q "${service}" 2>/dev/null || echo "")
    if [ -n "${CONTAINER_ID}" ]; then
        CONTAINER_IMAGE_ID=$(docker inspect "${CONTAINER_ID}" --format='{{.Image}}' 2>/dev/null || echo "")
        if [ -n "${CONTAINER_IMAGE_ID}" ]; then
            CONTAINER_ARCH=$(docker inspect "${CONTAINER_IMAGE_ID}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
            echo "   ${service}: ${CONTAINER_ARCH} (image ID: ${CONTAINER_IMAGE_ID:0:12})"
            
            if [ "${CONTAINER_ARCH}" != "arm64" ] && [ "${CONTAINER_ARCH}" != "aarch64" ]; then
                echo "   ❌ ERROR: ${service} container is using ${CONTAINER_ARCH} image, not ARM64!"
                echo "      This will cause 'exec format error'."
            else
                echo "   ✅ ${service} container is using ARM64 image"
            fi
        fi
    fi
done

# Show current status
echo "📊 Current container status:"
docker compose ps

# Show app logs
echo "📋 App logs (last 50 lines):"
docker compose logs --tail=50 app || echo "⚠️ No app logs available yet"

# Wait for app to be healthy
echo "⏳ Waiting for app to be healthy (max ${APP_HEALTH_CHECK_TIMEOUT}s)..."
APP_READY=false
for i in $(seq 1 ${APP_HEALTH_CHECK_TIMEOUT}); do
    if docker compose exec -T app sh -lc "curl -fsS http://localhost:8080/ >/dev/null 2>&1"; then
        echo "✅ App is responding"
        APP_READY=true
        break
    fi
    echo "  Health check attempt ${i}/${APP_HEALTH_CHECK_TIMEOUT}..."
    sleep 2
done

if [ "$APP_READY" != "true" ]; then
    echo "❌ App failed to become healthy within ${APP_HEALTH_CHECK_TIMEOUT}s"
    echo "📋 Last 100 lines of app logs:"
    docker compose logs --tail=100 app
    exit 1
fi

# Create database backup before migrations
echo "💾 Creating database backup..."
mkdir -p "${BACKUP_PATH}"
if docker compose ps db >/dev/null 2>&1; then
    DATE=$(date +%F-%H%M%S)
    BACKUP_FILE="${BACKUP_PATH}/store-${DATE}.sql.gz"
    
    # Get DB credentials from .env or use defaults
    source "${DEPLOY_PATH}/.env" 2>/dev/null || true
    MYSQL_USER="${DB_USERNAME:-store}"
    MYSQL_PASSWORD="${DB_PASSWORD:-}"
    MYSQL_DATABASE="${DB_DATABASE:-store}"
    
    if [ -n "$MYSQL_PASSWORD" ]; then
        docker compose exec -T db sh -lc \
            "mysqldump -u'${MYSQL_USER}' -p'${MYSQL_PASSWORD}' '${MYSQL_DATABASE}'" \
            2>/dev/null | gzip > "${BACKUP_FILE}" && \
            echo "✅ Backup created: ${BACKUP_FILE}" || \
            echo "⚠️ Backup creation failed (non-blocking)"
    else
        echo "⚠️ DB_PASSWORD not set, skipping backup"
    fi
fi

# Run migrations and optimize caches
echo "🔄 Running migrations and optimizing caches..."
docker compose exec -T app php artisan migrate --force || {
    echo "❌ Migration failed"
    exit 1
}

docker compose exec -T app php artisan config:cache || echo "⚠️ Config cache failed"
docker compose exec -T app php artisan route:cache || echo "⚠️ Route cache failed"
docker compose exec -T app php artisan view:cache || echo "⚠️ View cache failed"

# Final health check
echo "🔍 Final health check..."
if ! docker compose exec -T app sh -lc "curl -fsS http://localhost:8080/ >/dev/null 2>&1"; then
    echo "❌ Final health check failed"
    exit 1
fi

echo "✅ Deployment completed successfully!"

# Cleanup old images
echo "🧹 Cleaning up old Docker images..."
docker image prune -f || true

# Logout from Docker
docker logout "${REGISTRY}" || true
DEPLOY_SCRIPT
                        '''
                    }
                }
            }
        }

        // Stage 7: Deployment Info
        stage('Deployment Info') {
            when {
                anyOf {
                    expression { 
                        params.DEPLOY_ENV == 'production' || params.DEPLOY_ENV == 'staging'
                    }
                    expression {
                        (env.BRANCH_NAME == null || env.BRANCH_NAME == '' || env.BRANCH_NAME == 'main') && 
                        params.DEPLOY_ENV != 'skip'
                    }
                }
            }
            steps {
                script {
                    def prevBuild = (env.BUILD_NUMBER as Integer) - 1
                    def prevImageTag = "${prevBuild}${params.IMAGE_TAG_SUFFIX}"
                    
                    echo """
                    📋 Deployment Information:
                    
                    ✅ Current Deployment:
                       Image: ${FULL_IMAGE_NAME}
                       Build: #${BUILD_NUMBER}
                       Environment: ${params.DEPLOY_ENV}
                    
                    🔄 Rollback Options:
                       Previous Build: ${env.REGISTRY}/${env.IMAGE_NAME}:${prevImageTag}
                       Latest Tag: ${LATEST_IMAGE_NAME}
                    
                    🔧 Manual Rollback Command:
                       ssh ${DEPLOY_USER}@${DEPLOY_HOST} \\
                         "cd ${DEPLOY_PATH} && \\
                          APP_IMAGE=${env.REGISTRY}/${env.IMAGE_NAME}:${prevImageTag} \\
                          docker compose up -d --no-deps app queue scheduler"
                    """
                }
            }
        }
    }

    post {
        always {
            script {
                echo "🧹 Cleaning up workspace..."
            }
            
            // Cleanup Docker images
            sh 'docker image prune -f || true'
            
            // Clean workspace
            cleanWs(
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true
            )
        }
        
        success {
            script {
                echo """
                ✅ Pipeline completed successfully!
                
                📦 Image: ${FULL_IMAGE_NAME}
                🏷️  Latest: ${LATEST_IMAGE_NAME}
                🔢 Build: #${BUILD_NUMBER}
                """
            }
        }
        
        failure {
            script {
                echo """
                ❌ Pipeline failed!
                
                🔍 Check the logs above for details.
                📋 Failed stage: ${env.STAGE_NAME ?: 'Unknown'}
                """
            }
        }
        
        unstable {
            script {
                echo """
                ⚠️ Pipeline completed with warnings!
                
                Some stages may have failed but were marked as non-blocking.
                """
            }
        }
        
        cleanup {
            script {
                // Final cleanup
                echo "🧹 Final cleanup..."
            }
        }
    }
}
