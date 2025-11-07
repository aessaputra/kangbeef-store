pipeline {
    agent any

    environment {
        REGISTRY                 = "docker.io"
        IMAGE_NAME               = "aessaputra/kangbeef-store"
        DEPLOY_USER              = "kangbeef"
        DEPLOY_HOST              = "168.138.171.60"
        DOCKER_BUILDKIT          = "1"
        COMPOSE_DOCKER_CLI_BUILD = "1"
        DEPLOY_PATH              = "/home/kangbeef/web/kangbeef.com/docker_app"
        BACKUP_PATH              = "/home/kangbeef/web/kangbeef.com/private"
    }

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }

    stages {

        // 1. Cek Jenkins agent & koneksi SSH ke server
        stage('Preflight') {
            steps {
                sh 'docker version'
                sh 'docker compose version || docker-compose version || true'

                withCredentials([sshUserPrivateKey(
                    credentialsId: 'prod-ssh',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                )]) {
                    sh '''
                        set -euxo pipefail
                        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                            "$SSH_USER@$DEPLOY_HOST" \
                            "echo DEPLOY_OK && (docker compose version || docker-compose version || true)"
                        '''
                }
            }
        }

        // 2. Checkout dari Git
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // 3. Lint Dockerfile (opsional, tidak nge-fail pipeline)
        stage('Lint Dockerfile') {
            steps {
                sh '''
                    set -euxo pipefail
                    docker pull hadolint/hadolint || true
                    docker run --rm -i hadolint/hadolint < Dockerfile || true
                '''
            }
        }

        // 4. Build image production
    stage('Build') {
        steps {
            sh '''
                set -euxo pipefail

                # Setup multi-platform build support
                docker run --privileged --rm tonistiigi/binfmt --install all

                # Create a Docker context for unix socket to avoid TLS issues
                docker context create unix-context --docker host=unix:///var/run/docker.sock || true

                # Create buildx builder with docker-container driver for multi-platform support
                # Use unix context and network=host for proper daemon connection
                docker buildx create --use --driver docker-container --driver-opt network=host --name multiplatform-builder unix-context || docker buildx use multiplatform-builder

                # Tarik cache kalau ada
                docker pull "$REGISTRY/$IMAGE_NAME:latest" || true

                # Build image multi-platform (amd64 & arm64)
                docker buildx build \
                --platform=linux/amd64,linux/arm64 \
                --target production \
                --cache-from "$REGISTRY/$IMAGE_NAME:latest" \
                --build-arg BUILDKIT_INLINE_CACHE=1 \
                --label org.opencontainers.image.source="$GIT_URL" \
                --label org.opencontainers.image.revision="$GIT_COMMIT" \
                -f Dockerfile \
                -t "$REGISTRY/$IMAGE_NAME:$BUILD_NUMBER" \
                -t "$REGISTRY/$IMAGE_NAME:latest" \
                --push \
                .
            '''
        }
    }

        // 5. Test image hasil build
        stage('Test Image') {
            steps {
                sh '''
                    set -euxo pipefail
                    IMAGE_TAG="$REGISTRY/$IMAGE_NAME:$BUILD_NUMBER"

                    # PHP jalan?
                    docker run --rm -e APP_ENV=testing "$IMAGE_TAG" php -v

                    # Ekstensi penting ada?
                    docker run --rm "$IMAGE_TAG" php -m | tee /tmp/phpm.txt

                    grep -qiE '^intl$'      /tmp/phpm.txt
                    grep -qiE '^gd$'        /tmp/phpm.txt
                    grep -qiE '^imagick$'   /tmp/phpm.txt
                    grep -qiE '^pdo_mysql$' /tmp/phpm.txt
                    grep -qiE '^bcmath$'    /tmp/phpm.txt
                    grep -qiE '^gmp$'       /tmp/phpm.txt
                    grep -qiE '^exif$'      /tmp/phpm.txt
                    grep -qiE '^zip$'       /tmp/phpm.txt
                '''
            }
        }

        // 6. Push ke Docker Hub
        stage('Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'USER',
                    passwordVariable: 'PASS'
                )]) {
                    sh '''
                        set -euxo pipefail
                        echo "$PASS" | docker login -u "$USER" --password-stdin "$REGISTRY"

                        docker push "$REGISTRY/$IMAGE_NAME:$BUILD_NUMBER"
                        docker push "$REGISTRY/$IMAGE_NAME:latest"

                        docker logout "$REGISTRY"
                    '''
                }
            }
        }

        // 7. Deploy ke server (hanya main / freestyle)
        stage('Deploy') {
            when {
                expression {
                    return env.BRANCH_NAME == null || env.BRANCH_NAME == '' || env.BRANCH_NAME == 'main'
                }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'USER',
                    passwordVariable: 'PASS'
                )]) {
                    withCredentials([sshUserPrivateKey(
                        credentialsId: 'prod-ssh',
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )]) {
                        sh '''
                            set -euxo pipefail

                            echo "DEBUG: local env:"
                            echo "REGISTRY=$REGISTRY"
                            echo "IMAGE_NAME=$IMAGE_NAME"
                            echo "BUILD_NUMBER=$BUILD_NUMBER"
                            echo "DEPLOY_PATH=$DEPLOY_PATH"
                            echo "BACKUP_PATH=$BACKUP_PATH"

                            # Pastikan folder ada di server
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" "mkdir -p '$DEPLOY_PATH'"

                            # Kirim docker-compose.yml ke server
                            scp -i "$SSH_KEY" -o StrictHostKeyChecking=no docker-compose.yml \
                                "$SSH_USER@$DEPLOY_HOST:$DEPLOY_PATH/docker-compose.yml"

                            # Pastikan .env DI SERVER sudah ada (manual, tidak dioverwrite Jenkins)
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "if [ ! -f '$DEPLOY_PATH/.env' ]; then echo 'ERROR: .env not found in $DEPLOY_PATH on server. Please create it manually.'; exit 1; fi"

                            # Login Docker di server
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "echo '$PASS' | docker login -u '$USER' --password-stdin '$REGISTRY'"

                            # Jalankan script deploy di server
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "REGISTRY='$REGISTRY' IMAGE_NAME='$IMAGE_NAME' BUILD_NUMBER='$BUILD_NUMBER' DEPLOY_PATH='$DEPLOY_PATH' BACKUP_PATH='$BACKUP_PATH' bash -s" << 'EOF'
#!/bin/bash
set -Eeuo pipefail

echo "DEBUG: Remote env:"
echo "REGISTRY=$REGISTRY"
echo "IMAGE_NAME=$IMAGE_NAME"
echo "BUILD_NUMBER=$BUILD_NUMBER"
echo "DEPLOY_PATH=$DEPLOY_PATH"
echo "BACKUP_PATH=$BACKUP_PATH"

cd "$DEPLOY_PATH"

APP_IMAGE="$REGISTRY/$IMAGE_NAME:$BUILD_NUMBER"
echo "Using APP_IMAGE=$APP_IMAGE"

echo "Pulling app image..."
docker compose pull app || true

echo "Stopping existing stack..."
docker compose down || true

echo "Starting database container..."
docker compose up -d db

echo "Waiting for database to be healthy..."
for i in {1..30}; do
  if docker compose exec -T db mysqladmin ping -h localhost --silent; then
    echo "Database is healthy."
    break
  fi
  echo "Waiting for database to be ready... ($i/30)"
  sleep 2
done

echo "Starting Redis, App, Queue, Scheduler..."
APP_IMAGE="$APP_IMAGE" docker compose up -d redis app queue scheduler

echo "Current status:"
docker compose ps

echo "Checking app logs (last 40 lines)..."
docker compose logs --tail=40 app || echo "No app logs yet"

echo "Checking app health..."
for i in {1..30}; do
  if docker compose exec -T app sh -lc "curl -fsS http://localhost:8080/ >/dev/null"; then
    echo "App is responding."
    break
  fi
  echo "Health check attempt $i/30..."
  sleep 2
done

echo "Creating DB backup (if db exists)..."
mkdir -p "$BACKUP_PATH"
if docker compose ps db >/dev/null 2>&1; then
  DATE=$(date +%F-%H%M%S)

  MYSQL_USER="${MYSQL_USER:-store}"
  MYSQL_PASSWORD="${MYSQL_PASSWORD:-secure_password_here}"
  MYSQL_DATABASE="${MYSQL_DATABASE:-store}"

  docker compose exec -T db sh -lc \
    "mysqldump -u\"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\"" \
    | gzip > "$BACKUP_PATH/store-${DATE}.sql.gz" || true
fi

echo "Running migrations & optimizing caches..."
docker compose exec -T app php artisan migrate --force
docker compose exec -T app php artisan config:cache
docker compose exec -T app php artisan route:cache
docker compose exec -T app php artisan view:cache

echo "Final health check..."
docker compose exec -T app sh -lc "curl -fsS http://localhost:8080/ >/dev/null"

echo "Cleanup..."
docker image prune -f || true

docker logout "$REGISTRY" || true
EOF
                        '''
                    }
                }
            }
        }

        // 8. Info rollback
        stage('Promote/Rollback Info') {
            when {
                expression {
                    return env.BRANCH_NAME == null || env.BRANCH_NAME == '' || env.BRANCH_NAME == 'main'
                }
            }
            steps {
                script {
                    def prevBuild = (env.BUILD_NUMBER as Integer) - 1
                    echo "Rollback options:"
                    echo "- Previous: ${env.REGISTRY}/${env.IMAGE_NAME}:${prevBuild}"
                    echo "- Staging : ${env.REGISTRY}/${env.IMAGE_NAME}:staging"
                    echo "Manual rollback:"
                    echo "APP_IMAGE=${env.REGISTRY}/${env.IMAGE_NAME}:${prevBuild} docker compose up -d --no-deps app && docker compose up -d queue scheduler"
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
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Cek log di stage di atas."
        }
        unstable {
            echo "⚠️ Pipeline completed with warnings!"
        }
    }
}
