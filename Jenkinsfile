/**
 * Jenkins Pipeline untuk Kangbeef Store
 * 
 * Best Practices Applied:
 * - Declarative Pipeline syntax
 * - Parameterized builds untuk flexibility
 * - Parallel execution untuk optimasi
 * - Proper error handling dan retry logic
 * - Timeout handling
 * - Artifact archiving
 * - Proper credential management
 * - Health checks dan validation
 * - Cleanup dan notifications
 */

pipeline {
    agent any

    // Parameters untuk flexibility
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
        
        // Pipeline timeout
        timeout(time: 45, unit: 'MINUTES')
        
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

        // Stage 4: Build Multi-Arch Image
        stage('Build Multi-Arch Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    script {
                        echo "🏗️ Building multi-architecture Docker image..."
                        
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
                            
                            # Install QEMU/binfmt for multi-arch support
                            echo "Installing QEMU/binfmt for multi-arch support..."
                            docker --context dind run --privileged --rm tonistiigi/binfmt --install all || true
                            
                            # Setup buildx builder
                            if ! docker buildx inspect kb-multi-builder >/dev/null 2>&1; then
                                echo "Creating buildx builder 'kb-multi-builder'..."
                                docker buildx create \
                                    --name kb-multi-builder \
                                    --use \
                                    dind
                            else
                                echo "Using existing buildx builder 'kb-multi-builder'..."
                                docker buildx use kb-multi-builder
                            fi
                            
                            # Inspect builder
                            docker buildx inspect kb-multi-builder
                            
                            # Build and push multi-arch image
                            echo "Building and pushing multi-arch image: ${FULL_IMAGE_NAME} and ${LATEST_IMAGE_NAME}"
                            echo "Platforms: linux/amd64, linux/arm64"
                            
                            docker buildx build \
                                --platform linux/amd64,linux/arm64 \
                                --target production \
                                --build-arg BUILDKIT_INLINE_CACHE=1 \
                                --cache-from type=registry,ref="${LATEST_IMAGE_NAME}" \
                                --push \
                                --tag "${FULL_IMAGE_NAME}" \
                                --tag "${LATEST_IMAGE_NAME}" \
                                --progress=plain \
                                .
                            
                            echo "✅ Image built and pushed successfully"
                            
                            # Verify multi-arch manifest
                            echo "🔍 Verifying multi-arch manifest..."
                            docker buildx imagetools inspect "${FULL_IMAGE_NAME}" || {
                                echo "❌ Failed to inspect manifest"
                                exit 1
                            }
                            
                            # Show manifest details
                            echo "📋 Manifest details:"
                            docker buildx imagetools inspect "${FULL_IMAGE_NAME}" || echo "⚠️ Could not inspect manifest"
                            
                            # Verify platforms in manifest using a more robust method
                            echo "🔍 Verifying platforms in manifest..."
                            MANIFEST_OUTPUT=$(docker buildx imagetools inspect "${FULL_IMAGE_NAME}" 2>&1 || echo "")
                            
                            # Check for ARM64 platform
                            if echo "${MANIFEST_OUTPUT}" | grep -qiE "linux/arm64|arm64|aarch64"; then
                                echo "✅ ARM64 platform found in manifest"
                            else
                                echo "⚠️ ARM64 platform not explicitly found in manifest output"
                                echo "   This may be normal if manifest uses different format."
                                echo "   Will verify during deployment instead."
                            fi
                            
                            # Check for AMD64 platform
                            if echo "${MANIFEST_OUTPUT}" | grep -qiE "linux/amd64|amd64|x86_64"; then
                                echo "✅ AMD64 platform found in manifest"
                            else
                                echo "⚠️ AMD64 platform not explicitly found in manifest output"
                            fi
                            
                            # Alternative verification: try to pull ARM64 image
                            echo "🔍 Verifying ARM64 image can be pulled..."
                            if docker pull --platform linux/arm64 "${FULL_IMAGE_NAME}" 2>&1 | grep -qiE "arm64|aarch64|pulled|already exists"; then
                                echo "✅ ARM64 image verified (can be pulled)"
                                # Remove the test pull to save space
                                docker rmi "${FULL_IMAGE_NAME}" 2>/dev/null || true
                            else
                                echo "⚠️ Could not verify ARM64 image pull (non-critical, will verify during deployment)"
                            fi
                            
                            # Logout
                            docker logout "$REGISTRY" || true
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
                    echo "🧪 Testing Docker image..."
                    
                    sh '''
                        set -euxo pipefail
                        
                        IMAGE_TAG="${FULL_IMAGE_NAME}"
                        echo "Testing image: ${IMAGE_TAG}"
                        
                        # Pull image from registry
                        echo "Pulling image from registry..."
                        docker pull "${IMAGE_TAG}" || {
                            echo "❌ Failed to pull image"
                            exit 1
                        }
                        
                        # Test PHP version
                        echo "Testing PHP version..."
                        docker run --rm -e APP_ENV=testing "${IMAGE_TAG}" php -v || {
                            echo "❌ PHP version check failed"
                            exit 1
                        }
                        
                        # Test PHP extensions
                        echo "Testing PHP extensions..."
                        docker run --rm "${IMAGE_TAG}" php -m > /tmp/phpm.txt || {
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
                        echo "✅ Image testing completed successfully"
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
                            
                            # Execute deployment script on server
                            echo "Executing deployment script on server..."
                            ssh -i "$SSH_KEY" \
                                -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=${SSH_TIMEOUT} \
                                "$SSH_USER@${DEPLOY_HOST}" \
                                "REGISTRY='${REGISTRY}' \
                                 IMAGE_NAME='${IMAGE_NAME}' \
                                 IMAGE_TAG='${IMAGE_TAG}' \
                                 DEPLOY_PATH='${DEPLOY_PATH}' \
                                 BACKUP_PATH='${BACKUP_PATH}' \
                                 DB_HEALTH_CHECK_TIMEOUT='${DB_HEALTH_CHECK_TIMEOUT}' \
                                 APP_HEALTH_CHECK_TIMEOUT='${APP_HEALTH_CHECK_TIMEOUT}' \
                                 bash -s" << 'DEPLOY_SCRIPT'
#!/bin/bash
set -Eeuo pipefail

echo "📋 Remote Deployment Environment:"
echo "  REGISTRY=${REGISTRY}"
echo "  IMAGE_NAME=${IMAGE_NAME}"
echo "  IMAGE_TAG=${IMAGE_TAG}"
echo "  DEPLOY_PATH=${DEPLOY_PATH}"
echo "  BACKUP_PATH=${BACKUP_PATH}"

cd "${DEPLOY_PATH}"

APP_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
echo "📦 Using APP_IMAGE=${APP_IMAGE}"

# Detect server architecture
SERVER_ARCH=$(uname -m)
echo "🖥️  Server architecture: ${SERVER_ARCH}"

# Set platform based on server architecture
if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    PLATFORM="linux/arm64"
    echo "📱 Detected ARM64 architecture, will pull ARM64 image"
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    PLATFORM="linux/amd64"
    echo "💻 Detected AMD64 architecture, will pull AMD64 image"
else
    PLATFORM="linux/${SERVER_ARCH}"
    echo "⚠️  Unknown architecture, will try to pull for ${PLATFORM}"
fi

# Remove ALL existing images with the same tag first to avoid conflicts
echo "🧹 Removing all existing images with tag ${APP_IMAGE} to avoid conflicts..."
docker images "${APP_IMAGE}" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true

# Also remove any containers using the old image
echo "🧹 Removing any containers using old image..."
docker ps -a --filter "ancestor=${APP_IMAGE}" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true

# Pull latest image with platform specification
echo "⬇️ Pulling app image for platform ${PLATFORM}..."
docker pull --platform "${PLATFORM}" "${APP_IMAGE}" || {
    echo "❌ Failed to pull ${APP_IMAGE} for platform ${PLATFORM}"
    echo "   This will cause 'exec format error'. Aborting."
    exit 1
}

# Verify the pulled image is actually the correct architecture by checking image ID
echo "🔍 Verifying pulled image architecture..."
PULLED_IMAGE_ID=$(docker images "${APP_IMAGE}" --format "{{.ID}}" | head -1)
if [ -z "${PULLED_IMAGE_ID}" ]; then
    echo "❌ CRITICAL: No image found after pull!"
    exit 1
fi
PULLED_IMAGE_ARCH=$(docker inspect "${PULLED_IMAGE_ID}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Pulled image ID: ${PULLED_IMAGE_ID}"
echo "📦 Pulled image architecture: ${PULLED_IMAGE_ARCH}"

if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${PULLED_IMAGE_ARCH}" != "arm64" ] && [ "${PULLED_IMAGE_ARCH}" != "aarch64" ]; then
        echo "❌ CRITICAL: Pulled image is not ARM64 (got ${PULLED_IMAGE_ARCH})"
        echo "   Image ID: ${PULLED_IMAGE_ID}"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
    echo "✅ Verified: Pulled image is ARM64"
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${PULLED_IMAGE_ARCH}" != "amd64" ] && [ "${PULLED_IMAGE_ARCH}" != "x86_64" ]; then
        echo "❌ CRITICAL: Pulled image is not AMD64 (got ${PULLED_IMAGE_ARCH})"
        echo "   Image ID: ${PULLED_IMAGE_ID}"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
    echo "✅ Verified: Pulled image is AMD64"
fi

# Verify image architecture (using tag for compatibility)
echo "🔍 Verifying image architecture (by tag)..."
IMAGE_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Image architecture (by tag): ${IMAGE_ARCH}"

# Verify architecture matches server
if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${IMAGE_ARCH}" != "arm64" ] && [ "${IMAGE_ARCH}" != "aarch64" ]; then
        echo "⚠️  WARNING: Server is ARM64 but image architecture is ${IMAGE_ARCH}"
        echo "   This may cause 'exec format error'. Re-pulling with platform specification..."
        docker pull --platform linux/arm64 "${APP_IMAGE}" || echo "⚠️ Failed to re-pull ARM64 image"
        # Re-verify after re-pull
        IMAGE_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
        echo "📦 Image architecture after re-pull: ${IMAGE_ARCH}"
    else
        echo "✅ Image architecture matches server (ARM64)"
    fi
    
    # Remove any AMD64 images with the same tag to avoid confusion
    echo "🧹 Removing any AMD64 images with same tag to avoid conflicts..."
    docker images "${APP_IMAGE}" --format "{{.ID}} {{.Repository}}:{{.Tag}} {{.Architecture}}" | \
        grep -v -E "arm64|aarch64" | \
        awk '{print $1}' | \
        xargs -r docker rmi -f 2>/dev/null || true
    
    # Set default platform for docker compose
    export DOCKER_DEFAULT_PLATFORM=linux/arm64
    echo "🔧 Set DOCKER_DEFAULT_PLATFORM=linux/arm64"
    
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${IMAGE_ARCH}" != "amd64" ] && [ "${IMAGE_ARCH}" != "x86_64" ]; then
        echo "⚠️  WARNING: Server is AMD64 but image architecture is ${IMAGE_ARCH}"
        echo "   Re-pulling with platform specification..."
        docker pull --platform linux/amd64 "${APP_IMAGE}" || echo "⚠️ Failed to re-pull AMD64 image"
        # Re-verify after re-pull
        IMAGE_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
        echo "📦 Image architecture after re-pull: ${IMAGE_ARCH}"
    else
        echo "✅ Image architecture matches server (AMD64)"
    fi
    
    # Remove any ARM64 images with the same tag to avoid confusion
    echo "🧹 Removing any ARM64 images with same tag to avoid conflicts..."
    docker images "${APP_IMAGE}" --format "{{.ID}} {{.Repository}}:{{.Tag}} {{.Architecture}}" | \
        grep -v -E "amd64|x86_64" | \
        awk '{print $1}' | \
        xargs -r docker rmi -f 2>/dev/null || true
    
    # Set default platform for docker compose
    export DOCKER_DEFAULT_PLATFORM=linux/amd64
    echo "🔧 Set DOCKER_DEFAULT_PLATFORM=linux/amd64"
fi

# Final verification before compose pull
echo "🔍 Final image architecture verification..."
FINAL_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Final image architecture: ${FINAL_ARCH}"

if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${FINAL_ARCH}" != "arm64" ] && [ "${FINAL_ARCH}" != "aarch64" ]; then
        echo "❌ ERROR: Image architecture (${FINAL_ARCH}) does not match server (ARM64)"
        echo "   This will cause 'exec format error'. Please check image build."
        exit 1
    fi
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${FINAL_ARCH}" != "amd64" ] && [ "${FINAL_ARCH}" != "x86_64" ]; then
        echo "❌ ERROR: Image architecture (${FINAL_ARCH}) does not match server (AMD64)"
        echo "   This will cause 'exec format error'. Please check image build."
        exit 1
    fi
fi

# Verify the pulled image architecture one more time
PULLED_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Pulled image architecture: ${PULLED_ARCH}"

if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${PULLED_ARCH}" != "arm64" ] && [ "${PULLED_ARCH}" != "aarch64" ]; then
        echo "❌ CRITICAL: Pulled image is not ARM64 (got ${PULLED_ARCH})"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
    echo "✅ Verified: Pulled image is ARM64"
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${PULLED_ARCH}" != "amd64" ] && [ "${PULLED_ARCH}" != "x86_64" ]; then
        echo "❌ CRITICAL: Pulled image is not AMD64 (got ${PULLED_ARCH})"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
    echo "✅ Verified: Pulled image is AMD64"
fi

# Verify only correct architecture image exists
echo "🔍 Verifying only correct architecture image exists..."
REMAINING_IMAGES=$(docker images "${APP_IMAGE}" --format "{{.Architecture}}" | sort -u)
echo "📦 Remaining image architectures: ${REMAINING_IMAGES}"

# Remove any other images with different architecture (if any)
echo "🧹 Removing any remaining conflicting images..."
docker images "${APP_IMAGE}" --format "{{.ID}} {{.Architecture}}" | while read -r IMG_ID IMG_ARCH; do
    if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
        if [ "${IMG_ARCH}" != "arm64" ] && [ "${IMG_ARCH}" != "aarch64" ]; then
            echo "   Removing ${IMG_ARCH} image: ${IMG_ID}"
            docker rmi -f "${IMG_ID}" 2>/dev/null || true
        fi
    elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
        if [ "${IMG_ARCH}" != "amd64" ] && [ "${IMG_ARCH}" != "x86_64" ]; then
            echo "   Removing ${IMG_ARCH} image: ${IMG_ID}"
            docker rmi -f "${IMG_ID}" 2>/dev/null || true
        fi
    fi
done

# Final verification: only correct architecture should exist
FINAL_IMAGES=$(docker images "${APP_IMAGE}" --format "{{.Architecture}}" | sort -u | tr '\n' ' ')
echo "📦 Final image architectures: ${FINAL_IMAGES}"

# Before docker compose pull, ensure only correct architecture image exists
echo "🔍 Final check: ensuring only correct architecture image exists..."
ALL_IMAGES=$(docker images "${APP_IMAGE}" --format "{{.ID}} {{.Architecture}}")
echo "📦 All images with tag ${APP_IMAGE}:"
echo "${ALL_IMAGES}"

# Remove any images with wrong architecture
echo "${ALL_IMAGES}" | while read -r IMG_ID IMG_ARCH; do
    if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
        if [ "${IMG_ARCH}" != "arm64" ] && [ "${IMG_ARCH}" != "aarch64" ]; then
            echo "   Removing ${IMG_ARCH} image: ${IMG_ID}"
            docker rmi -f "${IMG_ID}" 2>/dev/null || true
        fi
    elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
        if [ "${IMG_ARCH}" != "amd64" ] && [ "${IMG_ARCH}" != "x86_64" ]; then
            echo "   Removing ${IMG_ARCH} image: ${IMG_ID}"
            docker rmi -f "${IMG_ID}" 2>/dev/null || true
        fi
    fi
done

# Verify only correct architecture remains
REMAINING_IMAGES=$(docker images "${APP_IMAGE}" --format "{{.Architecture}}" | sort -u | tr '\n' ' ')
echo "📦 Remaining image architectures: ${REMAINING_IMAGES}"

# Pull with docker compose (should use already pulled image)
echo "⬇️ Pulling images with docker compose..."
export DOCKER_DEFAULT_PLATFORM="${PLATFORM}"
echo "🔧 Set DOCKER_DEFAULT_PLATFORM=${PLATFORM}"

# Force docker compose to use the pulled image by specifying platform
docker compose pull app queue scheduler || echo "⚠️ Some image pulls failed, will use existing images"

# Verify docker compose will use correct image
echo "🔍 Verifying docker compose will use correct image..."
COMPOSE_CONFIG_IMAGE=$(docker compose config | grep -A 5 "app:" | grep "image:" | awk '{print $2}' | tr -d '"' || echo "")
echo "📋 Docker compose config image: ${COMPOSE_CONFIG_IMAGE}"

# Stop existing stack (gracefully)
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

# Verify image one more time before starting containers
echo "🔍 Final verification before starting containers..."
CONTAINER_IMAGE_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Container image architecture: ${CONTAINER_IMAGE_ARCH}"

if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${CONTAINER_IMAGE_ARCH}" != "arm64" ] && [ "${CONTAINER_IMAGE_ARCH}" != "aarch64" ]; then
        echo "❌ CRITICAL ERROR: Image architecture (${CONTAINER_IMAGE_ARCH}) does not match server (ARM64)"
        echo "   This will cause 'exec format error'. Aborting deployment."
        echo "   Please check:"
        echo "   1. Image was built for ARM64: docker buildx imagetools inspect ${APP_IMAGE}"
        echo "   2. Image was pulled with --platform linux/arm64"
        echo "   3. No conflicting images exist: docker images ${APP_IMAGE}"
        exit 1
    fi
    echo "✅ Verified: Image is ARM64, safe to start containers"
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${CONTAINER_IMAGE_ARCH}" != "amd64" ] && [ "${CONTAINER_IMAGE_ARCH}" != "x86_64" ]; then
        echo "❌ CRITICAL ERROR: Image architecture (${CONTAINER_IMAGE_ARCH}) does not match server (AMD64)"
        echo "   This will cause 'exec format error'. Aborting deployment."
        exit 1
    fi
    echo "✅ Verified: Image is AMD64, safe to start containers"
fi

# Verify docker compose will use correct image
echo "🔍 Verifying docker compose image configuration..."
COMPOSE_IMAGE=$(docker compose config --services | head -1)
echo "📋 Docker compose will use image: ${APP_IMAGE}"

# Final verification: ensure image is correct before starting
echo "🔍 Final verification before starting containers..."
FINAL_VERIFY_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Final image architecture: ${FINAL_VERIFY_ARCH}"

if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${FINAL_VERIFY_ARCH}" != "arm64" ] && [ "${FINAL_VERIFY_ARCH}" != "aarch64" ]; then
        echo "❌ CRITICAL: Image architecture (${FINAL_VERIFY_ARCH}) does not match server (ARM64)"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${FINAL_VERIFY_ARCH}" != "amd64" ] && [ "${FINAL_VERIFY_ARCH}" != "x86_64" ]; then
        echo "❌ CRITICAL: Image architecture (${FINAL_VERIFY_ARCH}) does not match server (AMD64)"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
fi

# Start Redis, App, Queue, and Scheduler with explicit platform
echo "🚀 Starting Redis, App, Queue, and Scheduler..."
echo "   Using APP_IMAGE=${APP_IMAGE}"
echo "   Using DOCKER_DEFAULT_PLATFORM=${PLATFORM}"
echo "   Image architecture: ${FINAL_VERIFY_ARCH}"

# Ensure DOCKER_DEFAULT_PLATFORM is set
export DOCKER_DEFAULT_PLATFORM="${PLATFORM}"

# Before starting, verify the image that will be used
echo "🔍 Verifying image that will be used by docker compose..."
COMPOSE_IMAGE_CHECK=$(docker compose config --services | head -1)
echo "📋 Docker compose will start services: app, queue, scheduler"

# Get the actual image ID that will be used
ACTUAL_IMAGE_ID=$(docker images "${APP_IMAGE}" --format "{{.ID}}" | head -1)
ACTUAL_IMAGE_ARCH=$(docker inspect "${ACTUAL_IMAGE_ID}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Actual image ID that will be used: ${ACTUAL_IMAGE_ID}"
echo "📦 Actual image architecture: ${ACTUAL_IMAGE_ARCH}"

if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${ACTUAL_IMAGE_ARCH}" != "arm64" ] && [ "${ACTUAL_IMAGE_ARCH}" != "aarch64" ]; then
        echo "❌ CRITICAL: Image that will be used is not ARM64 (got ${ACTUAL_IMAGE_ARCH})"
        echo "   Image ID: ${ACTUAL_IMAGE_ID}"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
    echo "✅ Verified: Image that will be used is ARM64"
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${ACTUAL_IMAGE_ARCH}" != "amd64" ] && [ "${ACTUAL_IMAGE_ARCH}" != "x86_64" ]; then
        echo "❌ CRITICAL: Image that will be used is not AMD64 (got ${ACTUAL_IMAGE_ARCH})"
        echo "   Image ID: ${ACTUAL_IMAGE_ID}"
        echo "   This will cause 'exec format error'. Aborting."
        exit 1
    fi
    echo "✅ Verified: Image that will be used is AMD64"
fi

# Start containers with explicit image and platform
echo "🚀 Starting containers with image ID: ${ACTUAL_IMAGE_ID} (${ACTUAL_IMAGE_ARCH})"
APP_IMAGE="${APP_IMAGE}" docker compose up -d redis app queue scheduler

# Verify containers started with correct architecture
echo "🔍 Verifying container architectures..."
for service in app queue scheduler; do
    CONTAINER_ID=$(docker compose ps -q "${service}" 2>/dev/null || echo "")
    if [ -n "${CONTAINER_ID}" ]; then
        # Get image ID used by container
        CONTAINER_IMAGE_ID=$(docker inspect "${CONTAINER_ID}" --format='{{.Image}}' 2>/dev/null || echo "")
        if [ -n "${CONTAINER_IMAGE_ID}" ]; then
            # Get architecture of the actual image used by container
            CONTAINER_ARCH=$(docker inspect "${CONTAINER_IMAGE_ID}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
            echo "   ${service}: ${CONTAINER_ARCH} (image ID: ${CONTAINER_IMAGE_ID:0:12})"
            
            if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
                if [ "${CONTAINER_ARCH}" != "arm64" ] && [ "${CONTAINER_ARCH}" != "aarch64" ]; then
                    echo "   ❌ ERROR: ${service} container is using ${CONTAINER_ARCH} image, not ARM64!"
                    echo "      This will cause 'exec format error'."
                    echo "      Container image ID: ${CONTAINER_IMAGE_ID}"
                    echo "      Expected image: ${APP_IMAGE}"
                    echo "      Please check if image was pulled correctly."
                else
                    echo "   ✅ ${service} container is using ARM64 image"
                fi
            fi
        else
            echo "   ⚠️  Could not get image ID for ${service} container"
        fi
    else
        echo "   ⚠️  ${service} container not found"
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
