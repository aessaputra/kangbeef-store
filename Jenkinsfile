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
                            docker buildx imagetools inspect "${FULL_IMAGE_NAME}" || echo "⚠️ Could not inspect manifest"
                            
                            # Show manifest details
                            echo "📋 Manifest details:"
                            docker buildx imagetools inspect "${FULL_IMAGE_NAME}" --format '{{json .}}' | grep -o '"architecture":"[^"]*"' || echo "⚠️ Could not get manifest details"
                            
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

# Pull latest image with platform specification
echo "⬇️ Pulling app image for platform ${PLATFORM}..."
docker pull --platform "${PLATFORM}" "${APP_IMAGE}" || {
    echo "⚠️ Failed to pull ${APP_IMAGE} for ${PLATFORM}, trying without platform..."
    docker pull "${APP_IMAGE}" || echo "⚠️ Image pull failed, will use existing image"
}

# Verify image architecture
echo "🔍 Verifying image architecture..."
IMAGE_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Image architecture: ${IMAGE_ARCH}"

# Verify architecture matches server
if [ "${SERVER_ARCH}" = "aarch64" ] || [ "${SERVER_ARCH}" = "arm64" ]; then
    if [ "${IMAGE_ARCH}" != "arm64" ] && [ "${IMAGE_ARCH}" != "aarch64" ]; then
        echo "⚠️  WARNING: Server is ARM64 but image architecture is ${IMAGE_ARCH}"
        echo "   This may cause 'exec format error'. Re-pulling with platform specification..."
        docker pull --platform linux/arm64 "${APP_IMAGE}" || echo "⚠️ Failed to re-pull ARM64 image"
    else
        echo "✅ Image architecture matches server (ARM64)"
    fi
elif [ "${SERVER_ARCH}" = "x86_64" ] || [ "${SERVER_ARCH}" = "amd64" ]; then
    if [ "${IMAGE_ARCH}" != "amd64" ] && [ "${IMAGE_ARCH}" != "x86_64" ]; then
        echo "⚠️  WARNING: Server is AMD64 but image architecture is ${IMAGE_ARCH}"
        echo "   Re-pulling with platform specification..."
        docker pull --platform linux/amd64 "${APP_IMAGE}" || echo "⚠️ Failed to re-pull AMD64 image"
    else
        echo "✅ Image architecture matches server (AMD64)"
    fi
fi

# Pull image for compose (will use already pulled image if platform matches)
echo "⬇️ Pulling images for docker compose..."
docker compose pull app queue scheduler || echo "⚠️ Some image pulls failed, will use existing images"

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

# Start Redis, App, Queue, and Scheduler
echo "🚀 Starting Redis, App, Queue, and Scheduler..."
APP_IMAGE="${APP_IMAGE}" docker compose up -d redis app queue scheduler

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
