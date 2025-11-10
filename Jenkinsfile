/**
 * Jenkins Pipeline untuk Kangbeef Store - ARM64 Architecture (Refactored)
 * 
 * Cross-Platform Build Support:
 * - Jenkins Server: AMD64 (build machine)
 * - Deployment Server: ARM64 (target machine)
 * - Build Method: Docker Buildx dengan QEMU emulation
 * 
 * Best Practices Applied (berdasarkan Jenkins Documentation):
 * - Declarative Pipeline syntax untuk maintainability
 * - Parameterized builds dengan validation
 * - Parallel execution untuk optimasi waktu build
 * - Combined shell commands untuk mengurangi overhead
 * - Proper error handling dengan catchError dan retry
 * - Timeout handling untuk mencegah hanging builds
 * - Artifact archiving dengan fingerprinting
 * - Proper credential management dengan withCredentials
 * - Health checks dan validation sebelum deployment
 * - Cleanup di post section untuk resource management
 * - Cross-platform build (AMD64 -> ARM64) dengan QEMU emulation
 * - Extracted complex scripts ke functions untuk readability
 * - Improved error handling dengan try-catch pattern
 * - Better resource management dengan cleanup blocks
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
        booleanParam(
            name: 'FORCE_DEPLOY',
            defaultValue: false,
            description: 'Force deployment even if health checks fail'
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
        
        // Build configuration
        BUILDER_NAME             = "kb-arm64-builder"
        DOCKER_CONTEXT           = "dind"
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
        
        // Pipeline timeout - increased for cross-platform build
        timeout(time: 1440, unit: 'MINUTES')
        
        // Timestamps in console output
        timestamps()
        
        // Skip stages after unstable
        skipStagesAfterUnstable()
        
        // Disable resume on controller restart
        disableResume()
    }

    triggers {
        // GitHub webhook trigger - akan diaktifkan melalui UI Jenkins
        // Ini akan memicu build otomatis saat ada push ke repository
        // Pastikan "GitHub hook trigger for GITScm polling" dicentang di job configuration
        
        // Fallback polling jika webhook tidak berfungsi (setiap 5 menit)
        pollSCM('H/5 * * * *')
        
        // Scheduled build setiap hari jam 2 pagi untuk build teratur
        cron('H 2 * * *')
    }

    // Validation function
    def validateParameters() {
        script {
            if (params.DEPLOY_ENV == 'production' && env.BRANCH_NAME != 'main' && !params.FORCE_DEPLOY) {
                error("Production deployment hanya diizinkan dari branch main. Gunakan FORCE_DEPLOY untuk override.")
            }
            
            if (params.IMAGE_TAG_SUFFIX && !params.IMAGE_TAG_SUFFIX.matches(/^-[a-zA-Z0-9._-]+$/)) {
                error("IMAGE_TAG_SUFFIX harus dimulai dengan '-' dan hanya mengandung alphanumeric, dot, underscore, atau dash.")
            }
        }
    }

    // Function to setup Docker buildx builder
    def setupBuildxBuilder() {
        script {
            return '''
                # Setup Docker context for DinD
                if ! docker context inspect ${DOCKER_CONTEXT} >/dev/null 2>&1; then
                    echo "Creating Docker context '${DOCKER_CONTEXT}'..."
                    docker context create ${DOCKER_CONTEXT} \\
                        --docker "host=tcp://docker:2376,ca=/certs/client/ca.pem,cert=/certs/client/cert.pem,key=/certs/client/key.pem"
                fi
                
                # Use DinD context
                docker context use ${DOCKER_CONTEXT}
                
                # Install QEMU/binfmt for cross-platform emulation
                echo "🔧 Installing QEMU/binfmt for ARM64 emulation..."
                docker --context ${DOCKER_CONTEXT} run --rm --privileged tonistiigi/binfmt --install linux/arm64 || {
                    echo "⚠️ QEMU/binfmt installation failed (may already be installed)"
                }
                
                # Setup buildx builder for cross-platform
                if ! docker buildx inspect ${BUILDER_NAME} >/dev/null 2>&1; then
                    echo "Creating buildx builder '${BUILDER_NAME}' for cross-platform build..."
                    docker buildx create \\
                        --name ${BUILDER_NAME} \\
                        --driver docker-container \\
                        --use \\
                        --platform linux/amd64,linux/arm64 \\
                        ${DOCKER_CONTEXT} || {
                        echo "⚠️ Failed to create builder with docker-container driver, trying default..."
                        docker buildx create \\
                            --name ${BUILDER_NAME} \\
                            --use \\
                            --platform linux/amd64,linux/arm64 \\
                            ${DOCKER_CONTEXT}
                    }
                else
                    echo "Using existing buildx builder '${BUILDER_NAME}'..."
                    docker buildx use ${BUILDER_NAME}
                fi
                
                # Inspect builder to verify cross-platform support
                echo "🔍 Inspecting buildx builder capabilities..."
                docker buildx inspect ${BUILDER_NAME}
            '''
        }
    }

    // Function to build Docker image with timeout protection
    def buildDockerImage() {
        script {
            return '''
                # Start keepalive background process
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
                
                # Build with timeout protection
                if command -v timeout >/dev/null 2>&1; then
                    echo "✅ Using timeout command for build protection"
                    timeout 72000 docker buildx build \\
                        --platform ${TARGET_PLATFORM} \\
                        --target production \\
                        --build-arg BUILDKIT_INLINE_CACHE=1 \\
                        --cache-from type=registry,ref="${LATEST_IMAGE_NAME}" \\
                        --push \\
                        --tag "${FULL_IMAGE_NAME}" \\
                        --tag "${LATEST_IMAGE_NAME}" \\
                        --progress=plain \\
                        --load=false \\
                        . || {
                        BUILD_EXIT_CODE=$?
                        echo "❌ Build failed or timed out after 20 hours (exit code: ${BUILD_EXIT_CODE})"
                        cleanup_keepalive
                        exit 1
                    }
                else
                    echo "⚠️ Timeout command not available, building without timeout wrapper"
                    docker buildx build \\
                        --platform ${TARGET_PLATFORM} \\
                        --target production \\
                        --build-arg BUILDKIT_INLINE_CACHE=1 \\
                        --cache-from type=registry,ref="${LATEST_IMAGE_NAME}" \\
                        --push \\
                        --tag "${FULL_IMAGE_NAME}" \\
                        --tag "${LATEST_IMAGE_NAME}" \\
                        --progress=plain \\
                        --load=false \\
                        . || {
                        BUILD_EXIT_CODE=$?
                        echo "❌ Build failed (exit code: ${BUILD_EXIT_CODE})"
                        cleanup_keepalive
                        exit 1
                    }
                fi
                
                # Stop keepalive process
                cleanup_keepalive
                echo "✅ Build process completed"
            '''
        }
    }

    // Function to verify image in registry
    def verifyImageInRegistry() {
        script {
            return '''
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
                        fi
                    fi
                done
                
                # Verify platform in manifest
                MANIFEST_OUTPUT=$(docker buildx imagetools inspect "${FULL_IMAGE_NAME}" 2>&1 || echo "")
                if echo "${MANIFEST_OUTPUT}" | grep -qiE "linux/arm64|arm64|aarch64"; then
                    echo "✅ ARM64 platform verified in manifest"
                else
                    echo "⚠️ ARM64 platform not found in manifest output"
                fi
            '''
        }
    }

    // Function to test Docker image
    def testDockerImage() {
        script {
            return '''
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
                
                # Required extensions
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

    stages {
        // Stage 1: Validate Parameters
        stage('Validate Parameters') {
            steps {
                script {
                    validateParameters()
                    echo "✅ Parameters validated successfully"
                }
            }
        }

        // Stage 2: Prepare Workspace
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

        // Stage 3: Preflight Checks
        stage('Preflight Checks') {
            parallel {
                stage('Check Docker') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                            script {
                                sh '''
                                    echo "Checking Docker installation..."
                                    docker version
                                    docker compose version || docker-compose version || echo "⚠️ Docker Compose not found"
                                '''
                            }
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
                            catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                                script {
                                    sh '''
                                        echo "Checking SSH connection to ${DEPLOY_HOST}..."
                                        ssh -i "$SSH_KEY" \\
                                            -o StrictHostKeyChecking=no \\
                                            -o ConnectTimeout=${SSH_TIMEOUT} \\
                                            -o BatchMode=yes \\
                                            "$SSH_USER@${DEPLOY_HOST}" \\
                                            "echo '✅ SSH connection successful' && (docker compose version || docker-compose version || echo '⚠️ Docker Compose not found on server')"
                                    '''
                                }
                            }
                        }
                    }
                }
            }
        }

        // Stage 4: Lint Dockerfile (optional)
        stage('Lint Dockerfile') {
            when {
                expression { !params.SKIP_LINT }
            }
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
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
        }

        // Stage 5: Build ARM64 Image
        stage('Build ARM64 Image') {
            options {
                timeout(time: 1200, unit: 'MINUTES')
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
                        
                        // Combine all build steps into a single sh block
                        sh '''
                            set -euxo pipefail
                            
                            # Login to Docker Hub
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin "$REGISTRY" || {
                                echo "❌ Docker login failed"
                                exit 1
                            }
                        '''
                        
                        // Setup buildx builder
                        sh(setupBuildxBuilder())
                        
                        // Build image
                        sh(buildDockerImage())
                        
                        // Verify image
                        sh(verifyImageInRegistry())
                        
                        // Logout
                        sh '''
                            docker logout "$REGISTRY" || true
                            echo "✅ ARM64 image build and verification completed"
                        '''
                    }
                }
            }
        }

        // Stage 6: Test Image
        stage('Test Image') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    script {
                        echo "🧪 Testing ARM64 Docker image..."
                        sh(testDockerImage())
                    }
                }
            }
        }

        // Stage 7: Determine Deployment Strategy
        stage('Determine Deployment Strategy') {
            steps {
                script {
                    // Set default deployment environment berdasarkan branch
                    if (params.DEPLOY_ENV == 'skip') {
                        echo "🚫 Deployment skipped by parameter"
                        return
                    }
                    
                    // Auto-determine environment jika tidak diset manual
                    if (params.DEPLOY_ENV == 'staging' || params.DEPLOY_ENV == 'production') {
                        echo "✅ Deployment environment set to: ${params.DEPLOY_ENV}"
                    } else {
                        // Auto-detect berdasarkan branch
                        if (env.BRANCH_NAME == 'main') {
                            env.AUTO_DEPLOY_ENV = 'production'
                            echo "🎯 Auto-detected production deployment for main branch"
                        } else if (env.BRANCH_NAME == 'develop' || env.BRANCH_NAME?.startsWith('release/')) {
                            env.AUTO_DEPLOY_ENV = 'staging'
                            echo "🎯 Auto-detected staging deployment for ${env.BRANCH_NAME} branch"
                        } else if (env.BRANCH_NAME?.startsWith('feature/') || env.BRANCH_NAME?.startsWith('hotfix/')) {
                            echo "🧪 Feature/hotfix branch detected: ${env.BRANCH_NAME}"
                            echo "📦 Build only, no deployment"
                            env.AUTO_DEPLOY_ENV = 'skip'
                        } else {
                            echo "ℹ️ Unknown branch: ${env.BRANCH_NAME}"
                            echo "📦 Build only, no deployment"
                            env.AUTO_DEPLOY_ENV = 'skip'
                        }
                    }
                }
            }
        }

        // Stage 8: Deploy to Server
        stage('Deploy') {
            when {
                anyOf {
                    expression {
                        params.DEPLOY_ENV == 'production' || params.DEPLOY_ENV == 'staging'
                    }
                    expression {
                        env.AUTO_DEPLOY_ENV == 'production' || env.AUTO_DEPLOY_ENV == 'staging'
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
                        def deployEnv = params.DEPLOY_ENV
                        if (deployEnv == 'skip' && env.AUTO_DEPLOY_ENV) {
                            deployEnv = env.AUTO_DEPLOY_ENV
                        }
                        echo "🚀 Deploying to ${deployEnv} environment..."
                        echo "🌿 Branch: ${env.BRANCH_NAME ?: 'N/A'}"
                        echo "👤 Triggered by: ${env.BUILD_USER ?: 'GitHub Webhook'}"
                        echo "🔗 Commit: ${env.GIT_COMMIT?.take(8) ?: 'N/A'}"
                        
                        sh '''
                            set -euxo pipefail
                            
                            echo "📋 Deployment Configuration:"
                            echo "  Image: ${FULL_IMAGE_NAME}"
                            echo "  Host: ${DEPLOY_HOST}"
                            echo "  Path: ${DEPLOY_PATH}"
                            echo "  Backup: ${BACKUP_PATH}"
                            
                            # Ensure deployment directory exists
                            echo "Creating deployment directory..."
                            ssh -i "$SSH_KEY" \\
                                -o StrictHostKeyChecking=no \\
                                -o ConnectTimeout=${SSH_TIMEOUT} \\
                                "$SSH_USER@${DEPLOY_HOST}" \\
                                "mkdir -p '${DEPLOY_PATH}' '${BACKUP_PATH}'"
                            
                            # Copy docker-compose.yml to server
                            echo "Copying docker-compose.yml to server..."
                            scp -i "$SSH_KEY" \\
                                -o StrictHostKeyChecking=no \\
                                docker-compose.yml \\
                                "$SSH_USER@${DEPLOY_HOST}:${DEPLOY_PATH}/docker-compose.yml"
                            
                            # Verify .env file exists on server
                            echo "Verifying .env file on server..."
                            ssh -i "$SSH_KEY" \\
                                -o StrictHostKeyChecking=no \\
                                -o ConnectTimeout=${SSH_TIMEOUT} \\
                                "$SSH_USER@${DEPLOY_HOST}" \\
                                "if [ ! -f '${DEPLOY_PATH}/.env' ]; then \\
                                    echo '❌ ERROR: .env file not found in ${DEPLOY_PATH} on server.'; \\
                                    echo 'Please create it manually before deploying.'; \\
                                    exit 1; \\
                                fi && echo '✅ .env file found'"
                            
                            # Login to Docker on server
                            echo "Logging in to Docker on server..."
                            ssh -i "$SSH_KEY" \\
                                -o StrictHostKeyChecking=no \\
                                -o ConnectTimeout=${SSH_TIMEOUT} \\
                                "$SSH_USER@${DEPLOY_HOST}" \\
                                "echo '$DOCKER_PASS' | docker login -u '$DOCKER_USER' --password-stdin '$REGISTRY'"
                        '''
                        
                        // Execute deployment script on server
                        sh(deployToServer())
                    }
                }
            }
        }

        // Stage 9: Deployment Info
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

// Function to deploy to server
def deployToServer() {
    return '''
        ssh -i "$SSH_KEY" \\
            -o StrictHostKeyChecking=no \\
            -o ConnectTimeout=${SSH_TIMEOUT} \\
            "$SSH_USER@${DEPLOY_HOST}" \\
            "REGISTRY='${REGISTRY}' \\
             IMAGE_NAME='${IMAGE_NAME}' \\
             IMAGE_TAG='${IMAGE_TAG}' \\
             TARGET_PLATFORM='${TARGET_PLATFORM}' \\
             DEPLOY_PATH='${DEPLOY_PATH}' \\
             BACKUP_PATH='${BACKUP_PATH}' \\
             DB_HEALTH_CHECK_TIMEOUT='${DB_HEALTH_CHECK_TIMEOUT}' \\
             APP_HEALTH_CHECK_TIMEOUT='${APP_HEALTH_CHECK_TIMEOUT}' \\
             FORCE_DEPLOY='${params.FORCE_DEPLOY}' \\
             bash -s" << 'DEPLOY_SCRIPT'
#!/bin/bash
set -euxo pipefail

echo "📋 Remote Deployment Environment (ARM64):"
echo "  REGISTRY=${REGISTRY}"
echo "  IMAGE_NAME=${IMAGE_NAME}"
echo "  IMAGE_TAG=${IMAGE_TAG}"
echo "  TARGET_PLATFORM=${TARGET_PLATFORM}"
echo "  DEPLOY_PATH=${DEPLOY_PATH}"
echo "  BACKUP_PATH=${BACKUP_PATH}"
echo "  FORCE_DEPLOY=${FORCE_DEPLOY}"

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
    exit 1
fi
echo "✅ Server architecture verified: ARM64"

# Cleanup old images and containers
echo "🧹 Cleaning up old images and containers..."
docker images "${APP_IMAGE}" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true
docker ps -a --filter "ancestor=${APP_IMAGE}" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true

# Pull ARM64 image
echo "⬇️ Pulling ARM64 image: ${APP_IMAGE}..."
docker pull --platform "${PLATFORM}" "${APP_IMAGE}" || {
    echo "❌ Failed to pull ARM64 image"
    exit 1
}

# Verify ARM64 image architecture
echo "🔍 Verifying ARM64 image architecture..."
IMAGE_ARCH=$(docker inspect "${APP_IMAGE}" --format='{{.Architecture}}' 2>/dev/null || echo "unknown")
echo "📦 Image architecture: ${IMAGE_ARCH}"

if [ "${IMAGE_ARCH}" != "arm64" ] && [ "${IMAGE_ARCH}" != "aarch64" ]; then
    echo "❌ ERROR: Image architecture (${IMAGE_ARCH}) is not ARM64"
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
    if [ "${FORCE_DEPLOY}" != "true" ]; then
        echo "❌ Database failed to become healthy within ${DB_HEALTH_CHECK_TIMEOUT}s"
        exit 1
    else
        echo "⚠️ Database not healthy but FORCE_DEPLOY is true, continuing..."
    fi
fi

# Start Redis, App, Queue, and Scheduler
echo "🚀 Starting Redis, App, Queue, and Scheduler..."
echo "   Using APP_IMAGE=${APP_IMAGE}"
echo "   Using DOCKER_DEFAULT_PLATFORM=${PLATFORM}"
APP_IMAGE="${APP_IMAGE}" docker compose up -d redis app queue scheduler

# Show current status
echo "📊 Current container status:"
docker compose ps

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
    if [ "${FORCE_DEPLOY}" != "true" ]; then
        echo "❌ App failed to become healthy within ${APP_HEALTH_CHECK_TIMEOUT}s"
        echo "📋 Last 100 lines of app logs:"
        docker compose logs --tail=100 app
        exit 1
    else
        echo "⚠️ App not healthy but FORCE_DEPLOY is true, continuing..."
    fi
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
        docker compose exec -T db sh -lc \\
            "mysqldump -u'${MYSQL_USER}' -p'${MYSQL_PASSWORD}' '${MYSQL_DATABASE}'" \\
            2>/dev/null | gzip > "${BACKUP_FILE}" && \\
            echo "✅ Backup created: ${BACKUP_FILE}" || \\
            echo "⚠️ Backup creation failed (non-blocking)"
    else
        echo "⚠️ DB_PASSWORD not set, skipping backup"
    fi
fi

# Run migrations and optimize caches
echo "🔄 Running migrations and optimizing caches..."
docker compose exec -T app php artisan migrate --force || {
    if [ "${FORCE_DEPLOY}" != "true" ]; then
        echo "❌ Migration failed"
        exit 1
    else
        echo "⚠️ Migration failed but FORCE_DEPLOY is true, continuing..."
    fi
}

docker compose exec -T app php artisan config:cache || echo "⚠️ Config cache failed"
docker compose exec -T app php artisan route:cache || echo "⚠️ Route cache failed"
docker compose exec -T app php artisan view:cache || echo "⚠️ View cache failed"

# Final health check
echo "🔍 Final health check..."
if ! docker compose exec -T app sh -lc "curl -fsS http://localhost:8080/ >/dev/null 2>&1"; then
    if [ "${FORCE_DEPLOY}" != "true" ]; then
        echo "❌ Final health check failed"
        exit 1
    else
        echo "⚠️ Final health check failed but FORCE_DEPLOY is true, deployment completed with warnings"
    fi
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
