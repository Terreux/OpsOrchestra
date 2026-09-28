pipeline {
    agent {
        label 'provisioner'
    }

    environment {
        TF_DIR = 'terraform/providers/digitalocean/smoke-test'
    }

    parameters {
        string(name: 'TARGET_HOST', defaultValue: '', trim: true,
            description: 'Existing target hostname or IP; leave blank to skip the SSH smoke test.')
        string(name: 'TARGET_SSH_PORT', defaultValue: '22', trim: true,
            description: 'Target SSH port.')
        string(name: 'TARGET_SSH_CREDENTIAL_ID', defaultValue: '', trim: true,
            description: 'SSH Username with private key credential for the target ops account.')
        string(name: 'TARGET_KNOWN_HOSTS_CREDENTIAL_ID', defaultValue: '', trim: true,
            description: 'Secret file credential containing verified known_hosts entries for the target.')
    }

    stages {
        stage('Verify Provisioner') {
            steps {
                sh '''
                    echo "=== OpsOrchestra Provisioner ==="
                    hostname
                    whoami
                    terraform version
                    doctl version
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                dir("${TF_DIR}") {
                    sh '''
                        terraform init
                        terraform validate
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'digitalocean-api-token',
                        variable: 'DIGITALOCEAN_TOKEN'
                    )
                ]) {
                    dir("${TF_DIR}") {
                        sh '''
                            set +x
                            terraform plan -out=tfplan
                        '''
                    }
                }
            }
        }

        stage('Create Droplet') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'digitalocean-api-token',
                        variable: 'DIGITALOCEAN_TOKEN'
                    )
                ]) {
                    dir("${TF_DIR}") {
                        sh '''
                            set +x

                            terraform apply \
                              -auto-approve \
                              tfplan

                            echo
                            echo "=== OpsOrchestra Smoke Test ==="
                            terraform output
                        '''
                    }
                }
            }
        }

        stage('Verify Droplet') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'digitalocean-api-token',
                        variable: 'DIGITALOCEAN_TOKEN'
                    )
                ]) {
                    dir("${TF_DIR}") {
                        sh '''
                            set +x

                            DROPLET_ID=$(terraform output -raw droplet_id)

                            echo "Verifying Droplet ID: $DROPLET_ID"

                            doctl \
                              --access-token "$DIGITALOCEAN_TOKEN" \
                              compute droplet get "$DROPLET_ID"
                        '''
                    }
                }
            }
        }

        stage('Target SSH Smoke Test') {
            when {
                expression { return params.TARGET_HOST?.trim() }
            }
            options {
                timeout(time: 2, unit: 'MINUTES')
            }
            steps {
                // Avoid archiving a previous build's report if credentials fail.
                dir('reports/target-smoke-test') {
                    deleteDir()
                }
                script {
                    if (!params.TARGET_SSH_CREDENTIAL_ID?.trim() ||
                        !params.TARGET_KNOWN_HOSTS_CREDENTIAL_ID?.trim()) {
                        error('Set both target credential IDs when TARGET_HOST is supplied.')
                    }
                }
                withCredentials([
                    file(credentialsId: params.TARGET_KNOWN_HOSTS_CREDENTIAL_ID,
                        variable: 'TARGET_KNOWN_HOSTS_FILE')
                ]) {
                    sshagent(credentials: [params.TARGET_SSH_CREDENTIAL_ID]) {
                        sh 'bash scripts/target-smoke-test.sh'
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'reports/target-smoke-test/*.txt',
                        allowEmptyArchive: true
                }
            }
        }
    }

    post {
        always {
            echo '=== OpsOrchestra Cleanup ==='

            withCredentials([
                string(
                    credentialsId: 'digitalocean-api-token',
                    variable: 'DIGITALOCEAN_TOKEN'
                )
            ]) {
                dir("${TF_DIR}") {
                    sh '''
                        set +x

                        terraform destroy \
                          -auto-approve
                    '''
                }
            }
        }
    }
}
