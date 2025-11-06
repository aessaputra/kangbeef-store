pipeline {
    agent any
    
    environment {
        REGISTRY   = "docker.io"
        IMAGE_NAME = "aessaputra/kangbeef-store"
        DEPLOY_USER  = "kangbeef"
        DEPLOY_HOST  = "168.138.171.60"
        DOCKER_BUILDKIT = "1"
        COMPOSE_DOCKER_CLI_BUILD = "1"
        DEPLOY_PATH = "/home/kangbeef/web/kangbeef.com/docker_app"
        BACKUP_PATH = "/home/kangbeef/web/kangbeef.com/private"
    }
    
    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }
    
    stages {
        stage('Preflight') {
            steps {
                sh 'docker version && docker compose version'
                sshagent (credentials: ['prod-ssh']) {
                    sh 'ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${DEPLOY_USER}@${DEPLOY_HOST} "echo DEPLOY OK && docker compose version"'
                }
            }
        }
        
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Lint Dockerfile') {
            steps {
                sh 'docker pull hadolint/hadolint || true'
                sh 'docker run --rm -i hadolint/hadolint < Dockerfile || true'
            }
        }
        
        stage('Build') {
            steps {
                script {
                    // Pull latest image first for effective caching
                    sh 'docker pull ${REGISTRY}/${IMAGE_NAME}:latest || true'
                    // Build with BuildKit for better caching and performance
                    sh """
                        docker build \
                            --target production \
                            --cache-from ${REGISTRY}/${IMAGE_NAME}:latest \
                            --build-arg BUILDKIT_INLINE_CACHE=1 \
                            --label org.opencontainers.image.source=${env.GIT_URL} \
                            --label org.opencontainers.image.revision=${env.GIT_COMMIT} \
                            -f Dockerfile \
                            -t ${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER} \
                            -t ${REGISTRY}/${IMAGE_NAME}:latest \
                            .
                    """
                }
            }
        }
        
        stage('Test Image') {
            steps {
                script {
                    // Basic container tests and PHP extension verification
                    def imageTag = "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
                    sh """
                        docker run --rm \
                            -e APP_ENV=testing \
                            ${imageTag} \
                            php -v
                    """
                    // Check required PHP extensions
                    sh """
                        docker run --rm ${imageTag} php -m | tee /tmp/phpm.txt
                        grep -qiE '^intl\\\$' /tmp/phpm.txt
                        grep -qiE '^gd\\\$' /tmp/phpm.txt
                        grep -qiE '^imagick\\\$' /tmp/phpm.txt
                        grep -qiE '^pdo_mysql\\\$' /tmp/phpm.txt
                        grep -qiE '^bcmath\\\$' /tmp/phpm.txt
                        grep -qiE '^gmp\\\$' /tmp/phpm.txt
                        grep -qiE '^exif\\\$' /tmp/phpm.txt
                        grep -qiE '^zip\\\$' /tmp/phpm.txt
                    """
                }
            }
        }
        
        stage('Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'USER',
                    passwordVariable: 'PASS'
                )]) {
                    script {
                        def imageTag = "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
                        sh """
                            echo "\$PASS" | docker login -u "\$USER" --password-stdin ${REGISTRY}
                            docker push ${imageTag}
                            docker push ${REGISTRY}/${IMAGE_NAME}:latest
                            docker logout ${REGISTRY}
                        """
                    }
                }
            }
        }
        
        stage('Deploy') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'USER',
                    passwordVariable: 'PASS'
                )]) {
                    sshagent (credentials: ['prod-ssh']) {
                        sh """
                            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${DEPLOY_USER}@${DEPLOY_HOST} "mkdir -p ${DEPLOY_PATH}"
                            scp -o StrictHostKeyChecking=no docker-compose.yml ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/docker-compose.yml
                        """
                    }
                    
                    sshagent (credentials: ['prod-ssh']) {
                        script {
                            def imageTag = "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
                            sh """
                                ssh -o StrictHostKeyChecking=no \
                                    -o ConnectTimeout=10 \
                                    ${DEPLOY_USER}@${DEPLOY_HOST} bash -lc 'set -Eeuo pipefail
                                
                                echo "Starting deployment..."
                                cd '"${DEPLOY_PATH}"'
                                
                                # Login to Docker registry for private images
                                echo "\$PASS" | docker login -u "\$USER" --password-stdin ${REGISTRY}
                                
                                # Pull latest images
                                echo "Pulling latest images..."
                                docker compose pull app || true
                                # docker compose pull db || true
                                # docker compose pull redis || true
                                
                                # Backup current deployment
                                echo "Creating backup..."
                                docker compose exec -T app php artisan route:clear || true
                                docker compose exec -T app php artisan config:clear || true
                                docker compose exec -T app php artisan view:clear || true
                                
                                # Deploy new version
                                echo "Deploying new version..."
                                APP_IMAGE=${imageTag} \
                                docker compose up -d --no-deps --pull always --force-recreate app
                                
                                # Update worker & scheduler services as well
                                docker compose up -d queue scheduler
                                
                                # Wait for app health
                                echo "Waiting for app health..."
                                for i in {1..30}; do
                                  if docker compose exec -T app sh -lc 'curl -fsS http://localhost:8080/ >/dev/null'; then
                                    echo "App is responding."
                                    break
                                  fi
                                  sleep 2
                                done
                                
                                # Quick DB backup before migrating
                                echo "Creating database backup..."
                                mkdir -p '"${BACKUP_PATH}"'
                                DATE=$(date +%F-%H%M%S)
                                docker compose exec -T db sh -lc 'mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
                                  | gzip > '"${BACKUP_PATH}"'/store-${DATE}.sql.gz || true

                                # Run migrations and cache commands
                                echo "Running migrations..."
                                docker compose exec -T app php artisan migrate --force
                                
                                echo "Clearing and caching..."
                                docker compose exec -T app php artisan config:cache
                                docker compose exec -T app php artisan route:cache
                                docker compose exec -T app php artisan view:cache
                                
                                # Health check
                                echo "Performing health check..."
                                if ! docker compose exec -T app curl -f http://localhost:8080/; then
                                    echo "Health check failed!"
                                    exit 1
                                fi
                                
                                echo "Deployment completed successfully!"
                                
                                # Cleanup dangling images to minimize server load
                                docker image prune -f || true
                                
                                # Logout from Docker registry
                                docker logout ${REGISTRY}
                                '
                        """
                    }
                }
            }
        }
        
        stage('Promote/Rollback') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                }
            }
            parallel {
                stage('Promote to Staging') {
                    steps {
                        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'USER', passwordVariable: 'PASS')]) {
                            script {
                                def imageTag = "${REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
                                sh """
                                    echo "\$PASS" | docker login -u "\$USER" --password-stdin ${REGISTRY}
                                    docker pull ${imageTag}
                                    docker tag  ${imageTag} ${REGISTRY}/${IMAGE_NAME}:staging
                                    docker push ${REGISTRY}/${IMAGE_NAME}:staging
                                    docker logout ${REGISTRY}
                                """
                            }
                        }
                    }
                }
                stage('Rollback Options') {
                    steps {
                        script {
                            def currentBuild = "${BUILD_NUMBER}"
                            def prevBuild = "${BUILD_NUMBER-1}"
                            echo "Available rollback options:"
                            echo "Previous version: ${REGISTRY}/${IMAGE_NAME}:${prevBuild}"
                            echo "Staging version: ${REGISTRY}/${IMAGE_NAME}:staging"
                            echo ""
                            echo "To rollback, use one of these commands:"
                            echo "APP_IMAGE=${REGISTRY}/${IMAGE_NAME}:${prevBuild} docker compose up -d --no-deps app && docker compose up -d queue scheduler"
                            echo "APP_IMAGE=${REGISTRY}/${IMAGE_NAME}:staging docker compose up -d --no-deps app && docker compose up -d queue scheduler"
                        }
                    }
                }
            }
        }
    }
    
    post {
        always {
            sh 'docker image prune -f || true'
            cleanWs()
        }
        
        success {
            script {
                // Notify on success
                echo "✅ Pipeline completed successfully!"
                // Add notification logic here if needed
            }
        }
        
        failure {
            script {
                // Notify on failure
                echo "❌ Pipeline failed!"
                echo "Rolling back..."
                sshagent (credentials: ['prod-ssh']) {
                    script {
                        def currentBuild = "${BUILD_NUMBER}"
                        def prevBuild = "${BUILD_NUMBER-1}"
                        sh """
                            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${DEPLOY_USER}@${DEPLOY_HOST} bash -lc 'set -Eeuo pipefail
                              cd '"${DEPLOY_PATH}"'

                              # Tentukan target rollback: previous build jika ada, else staging
                              if [ -n "${currentBuild}" ] && [ "${currentBuild}" -gt 1 ]; then
                                PREV=$(( ${currentBuild} - 1 ))
                                echo "Rolling back to previous: ${REGISTRY}/${IMAGE_NAME}:\${PREV}"
                                APP_IMAGE=${REGISTRY}/${IMAGE_NAME}:\${PREV} docker compose up -d --no-deps --force-recreate app
                              else
                                echo "Rolling back to staging tag"
                                APP_IMAGE=${REGISTRY}/${IMAGE_NAME}:staging docker compose up -d --no-deps --force-recreate app
                              fi

                              # Update worker & scheduler services as well
                              docker compose up -d queue scheduler

                              # Tunggu sehat
                              for i in {1..30}; do
                                if docker compose exec -T app sh -lc 'curl -fsS http://localhost:8080/ >/dev/null'; then
                                  echo "Rollback healthy."
                                  break
                                fi
                                sleep 2
                              done
                            '
                        """
                    }
                }
            }
        }
        
        unstable {
            script {
                echo "⚠️ Pipeline completed with warnings!"
            }
        }
    }
}
