pipeline {
    agent {
        label 'provisioner'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Verify Repository') {
            steps {
                sh '''
                    echo "=== OpsOrchestra Repository ==="
                    pwd
                    git remote -v
                    git rev-parse --short HEAD
                    find . -maxdepth 2 -type f | sort
                '''
            }
        }

        stage('Verify Tooling') {
            steps {
                sh '''
                    echo "=== Terraform ==="
                    terraform version

                    echo "=== doctl ==="
                    doctl version
                '''
            }
        }
    }
}