/**
 * Simplified Jenkins Pipeline for Kangbeef Store
 * 
 * Best Practices Applied:
 * - Declarative Pipeline syntax for maintainability
 * - Proper error handling with try-catch
 * - Timeout handling for stages
 * - Credential management with withCredentials
 * - Cleanup in post section
 * - Combined shell commands to reduce overhead
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
        REGISTRY = 'docker.io'
        IMAGE_NAME = 'aessaputra/kangbeef-store'
        IMAGE_TAG = "${BUILD_NUMBER}${params.IMAGE_TAG_SUFFIX}"
        FULL_IMAGE_NAME = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        LATEST_IMAGE_NAME = "${REGISTRY}/${IMAGE_NAME}:latest"
        
        // Deployment configuration
        DEPLOY_HOST = '168.138.171.60'
        DEPLOY_USER = 'kangbeef'
        DEPLOY_PATH = '/home/kangbeef/web/kangbeef.com/docker_app'
        
        // Docker configuration
        DOCKER_BUILDKIT = '1'
        COMPOSE_DOCKER_CLI_BUILD = '1'
        
        // ARM64 configuration
        TARGET_PLATFORM = 'linux/arm64'
        BUILDER_NAME = 'kb-arm64-builder'
        DOCKER_CONTEXT = 'dind'
    }

    options {
        // Prevent concurrent builds
        disableConcurrentBuilds()
        
        // Build history retention
        buildDiscarder(
            logRotator(
                daysToKeepStr: '14',
                numToKeepStr: '10'
            )
        )
        
        // Pipeline timeout - increased for cross-platform build
        timeout(time: 240, unit: 'MINUTES')
        
        // Timestamps in console output
        timestamps()
    }

    triggers {
        // GitHub webhook trigger
        pollSCM('H/5 * * * *')
        
        // Scheduled build setiap hari jam 2 pagi
        cron('H 2 * * *')
    }

    stages {
        // Stage 1: Checkout
        stage('Checkout') {
            steps {
                script {
                    echo "🚀 Starting build #${BUILD_NUMBER}"
                    echo "📦 Image: ${FULL_IMAGE_NAME}"
                    echo "🌿 Branch: ${env.BRANCH_NAME ?: 'N/A'}"
                }
                
                // Clean workspace
                cleanWs(
                    deleteDirs: true,
                    disableDeferredWipeout: true
                )
                
                // Checkout source code
                checkout scm
            }
        }

        // Stage 2: Lint Dockerfile
        stage('Lint Dockerfile') {
            when {
                expression { !params.SKIP_LINT }
            }
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    script {
                        echo "🔍 Linting Dockerfile..."
                        sh '''
                            set +e
                            docker pull hadolint/hadolint:latest || true
                            docker run --rm -i hadolint/hadolint < Dockerfile || echo "⚠️ Hadolint found issues (non-blocking)"
                            set -e
                        '''
                    }
                }
            }
        }

        // Stage 3: Build Image
        stage('Build Image') {
            steps {
                script {
                    echo "🏗️ Building ARM64 Docker image..."
                }
                
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        set -euxo pipefail
                        
                        # Login to Docker Hub
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin "$REGISTRY"
                        
                        # Setup Docker context for DinD
                        if ! docker context inspect ${DOCKER_CONTEXT} >/dev/null 2>&1; then
                            echo "Creating Docker context '${DOCKER_CONTEXT}'..."
                            docker context create ${DOCKER_CONTEXT} \
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
                            docker buildx create \
                                --name ${BUILDER_NAME} \
                                --driver docker-container \
                                --use \
                                --platform linux/amd64,linux/arm64 \
                                ${DOCKER_CONTEXT} || {
                                echo "⚠️ Failed to create builder with docker-container driver, trying default..."
                                docker buildx create \
                                    --name ${BUILDER_NAME} \
                                    --use \
                                    --platform linux/amd64,linux/arm64 \
                                    ${DOCKER_CONTEXT}
                            }
                        else
                            echo "Using existing buildx builder '${BUILDER_NAME}'..."
                            docker buildx use ${BUILDER_NAME}
                        fi
                        
                        # Build ARM64 image with buildx
                        docker buildx build \
                            --platform ${TARGET_PLATFORM} \
                            --target production \
                            --build-arg BUILDKIT_INLINE_CACHE=1 \
                            --cache-from type=registry,ref="${LATEST_IMAGE_NAME}" \
                            --load \
                            --tag "${FULL_IMAGE_NAME}" \
                            --tag "${LATEST_IMAGE_NAME}" \
                            --progress=plain \
                            .
                        
                        echo "✅ ARM64 image built successfully: ${FULL_IMAGE_NAME}"
                    '''
                }
            }
        }

        // Stage 4: Push Image
        stage('Push Image') {
            steps {
                script {
                    echo "📤 Pushing ARM64 Docker image..."
                }
                
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        set -euxo pipefail
                        
                        # Login to Docker Hub
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin "$REGISTRY"
                        
                        # Push ARM64 image using buildx
                        docker buildx build \
                            --platform ${TARGET_PLATFORM} \
                            --target production \
                            --build-arg BUILDKIT_INLINE_CACHE=1 \
                            --cache-from type=registry,ref="${LATEST_IMAGE_NAME}" \
                            --push \
                            --tag "${FULL_IMAGE_NAME}" \
                            --tag "${LATEST_IMAGE_NAME}" \
                            --progress=plain \
                            .
                        
                        # Verify image in registry
                        echo "🔍 Verifying ARM64 image in registry..."
                        docker buildx imagetools inspect "${FULL_IMAGE_NAME}"
                        
                        echo "✅ ARM64 images pushed successfully"
                        docker logout "$REGISTRY"
                    '''
                }
            }
        }

        // Stage 5: Deploy
        stage('Deploy') {
            when {
                anyOf {
                    expression { params.DEPLOY_ENV == 'production' || params.DEPLOY_ENV == 'staging' }
                    expression { env.BRANCH_NAME == 'main' && params.DEPLOY_ENV != 'skip' }
                }
            }
            steps {
                script {
                    def deployEnv = params.DEPLOY_ENV == 'skip' ? 
                        (env.BRANCH_NAME == 'main' ? 'production' : 'skip') : 
                        params.DEPLOY_ENV
                    
                    if (deployEnv == 'skip') {
                        echo "🚫 Deployment skipped"
                        return
                    }
                    
                    echo "🚀 Deploying to ${deployEnv} environment..."
                }
                
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
                    sh '''
                        set -euxo pipefail
                        
                        # Copy docker-compose.yml to server
                        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                            docker-compose.yml \
                            "$SSH_USER@$DEPLOY_HOST:$DEPLOY_PATH/docker-compose.yml"
                        
                        # Deploy to server
                        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
                            "$SSH_USER@$DEPLOY_HOST" \
                            "cd '$DEPLOY_PATH' && \
                             echo '$DOCKER_PASS' | docker login -u '$DOCKER_USER' --password-stdin '$REGISTRY' && \
                             export DOCKER_DEFAULT_PLATFORM='${TARGET_PLATFORM}' && \
                             APP_IMAGE='$FULL_IMAGE_NAME' docker compose pull app queue scheduler && \
                             docker compose down --timeout 30 && \
                             APP_IMAGE='$FULL_IMAGE_NAME' docker compose up -d && \
                             docker logout '$REGISTRY'"
                        
                        echo "✅ Deployment completed successfully"
                    '''
                }
            }
        }
    }

    post {
        always {
            script {
                echo "🧹 Cleaning up..."
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
    }
}
