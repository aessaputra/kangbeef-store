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

        // --- 1. Sanity check Jenkins agent & SSH ke server deploy ---
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
                        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                            "$SSH_USER@$DEPLOY_HOST" \
                            "echo DEPLOY_OK && (docker compose version || docker-compose version || true)"
                    '''
                }
            }
        }

        // --- 2. Checkout source dari GitHub ---
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // --- 3. Lint Dockerfile ---
        stage('Lint Dockerfile') {
            steps {
                sh 'docker pull hadolint/hadolint || true'
                sh 'docker run --rm -i hadolint/hadolint < Dockerfile || true'
            }
        }

        // --- 4. Build image production ---
        stage('Build') {
            steps {
                sh '''
                    set -euxo pipefail

                    # Tarik cache jika ada
                    docker pull "$REGISTRY/$IMAGE_NAME:latest" || true

                    docker build \
                      --target production \
                      --cache-from "$REGISTRY/$IMAGE_NAME:latest" \
                      --build-arg BUILDKIT_INLINE_CACHE=1 \
                      --label org.opencontainers.image.source="$GIT_URL" \
                      --label org.opencontainers.image.revision="$GIT_COMMIT" \
                      -f Dockerfile \
                      -t "$REGISTRY/$IMAGE_NAME:$BUILD_NUMBER" \
                      -t "$REGISTRY/$IMAGE_NAME:latest" \
                      .
                '''
            }
        }

        // --- 5. Test image hasil build ---
        stage('Test Image') {
            steps {
                sh '''
                    set -euxo pipefail
                    IMAGE_TAG="$REGISTRY/$IMAGE_NAME:$BUILD_NUMBER"

                    # Cek PHP jalan
                    docker run --rm -e APP_ENV=testing "$IMAGE_TAG" php -v

                    # Cek ekstensi PHP wajib
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

        // --- 6. Push ke Docker Hub ---
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

        // --- 7. Deploy ke server Hestia (Hanya main/master) ---
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

                            # Pastikan folder dan compose ada di server
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" "mkdir -p '$DEPLOY_PATH'"
                            scp -i "$SSH_KEY" -o StrictHostKeyChecking=no docker-compose.yml \
                                "$SSH_USER@$DEPLOY_HOST:$DEPLOY_PATH/docker-compose.yml"

                            # Login Docker di server
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "echo '$PASS' | docker login -u '$USER' --password-stdin '$REGISTRY'"

                            # Jalankan deploy di server dengan env yang dikirim eksplisit
                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "cat > /tmp/deploy-script.sh << 'EOF'
#!/bin/bash
set -Eeuo pipefail

export REGISTRY=\"$REGISTRY\"
export IMAGE_NAME=\"$IMAGE_NAME\"
export BUILD_NUMBER=\"$BUILD_NUMBER\"
export DEPLOY_PATH=\"$DEPLOY_PATH\"
export BACKUP_PATH=\"$BACKUP_PATH\"

cd \"\$DEPLOY_PATH\"

APP_IMAGE=\"\$REGISTRY/\$IMAGE_NAME:\$BUILD_NUMBER\"

echo \"Pulling latest app image...\"
docker compose pull app || true

echo \"Deploying new app container...\"
APP_IMAGE=\"\$APP_IMAGE\" docker compose up -d --no-deps --pull always --force-recreate app

echo \"Ensuring queue & scheduler running...\"
docker compose up -d queue scheduler || true

echo \"Waiting for app health...\"
i=1
while [ \$i -le 30 ]; do
  if docker compose exec -T app sh -lc \"curl -fsS http://localhost:8080/ >/dev/null\"; then
    echo \"App is responding.\"; break
  fi
  sleep 2
  i=\$((i+1))
done

echo \"Creating DB backup (if db exists)...\"
mkdir -p \"\$BACKUP_PATH\"
if docker compose ps db >/dev/null 2>&1; then
  DATE=\$(date +%F-%H%M%S)
  docker compose exec -T db sh -lc \\
    \"mysqldump -u\\\"\$MYSQL_USER\\\" -p\\\"\$MYSQL_PASSWORD\\\" \\\"\$MYSQL_DATABASE\\\"\" \\
    | gzip > \"\$BACKUP_PATH/store-\${DATE}.sql.gz\" || true
fi

echo \"Running migrations & optimizing caches...\"
docker compose exec -T app php artisan migrate --force
docker compose exec -T app php artisan config:cache
docker compose exec -T app php artisan route:cache
docker compose exec -T app php artisan view:cache

echo \"Final health check...\"
docker compose exec -T app sh -lc \"curl -fsS http://localhost:8080/ >/dev/null\"

echo \"Cleanup...\"
docker image prune -f || true

docker logout \"\$REGISTRY\"
EOF"

                            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                                "$SSH_USER@$DEPLOY_HOST" \
                                "chmod +x /tmp/deploy-script.sh && /tmp/deploy-script.sh"
                        '''
                    }
                }
            }
        }

        // --- 8. Info rollback (tanpa eksekusi otomatis berbahaya) ---
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
                    echo "Manual rollback commands (run di server deploy):"
                    echo "APP_IMAGE=${env.REGISTRY}/${env.IMAGE_NAME}:${prevBuild} docker compose up -d --no-deps app && docker compose up -d queue scheduler"
                    echo "APP_IMAGE=${env.REGISTRY}/${env.IMAGE_NAME}:staging docker compose up -d --no-deps app && docker compose up -d queue scheduler"
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
            echo "❌ Pipeline failed. Check logs; rollback dilakukan manual pakai instruksi di stage Promote/Rollback Info."
        }

        unstable {
            echo "⚠️ Pipeline completed with warnings!"
        }
    }
}
