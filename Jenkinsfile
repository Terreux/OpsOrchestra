pipeline {
    agent {
        label 'provisioner'
    }

    environment {
        TF_DIR = 'terraform/providers/digitalocean/smoke-test'
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