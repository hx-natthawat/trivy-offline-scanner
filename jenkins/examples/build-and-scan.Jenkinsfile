// Build Docker image and scan for vulnerabilities
pipeline {
    agent any
    
    environment {
        IMAGE_NAME = "myapp"
        IMAGE_TAG = "${BUILD_NUMBER}"
        REGISTRY = "localhost:5000" // Change to your registry
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build Image') {
            steps {
                script {
                    sh """
                        docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                    """
                }
            }
        }
        
        stage('Security Scan') {
            steps {
                script {
                    // Scan the newly built image
                    def scanResult = build job: 'container-security-scan', 
                        parameters: [
                            string(name: 'DOCKER_IMAGE', value: "${IMAGE_NAME}:${IMAGE_TAG}"),
                            string(name: 'SEVERITY_THRESHOLD', value: 'CRITICAL'),
                            string(name: 'OUTPUT_FORMAT', value: 'json'),
                            booleanParam(name: 'FAIL_ON_VULNERABILITIES', value: true)
                        ],
                        returnStatusCode: true
                    
                    if (scanResult != 0) {
                        error("Security scan failed! Critical vulnerabilities found.")
                    }
                }
            }
        }
        
        stage('Push to Registry') {
            when {
                // Only push if security scan passes
                expression { currentBuild.result != 'FAILURE' }
            }
            steps {
                script {
                    sh """
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
        }
    }
    
    post {
        always {
            sh """
                docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                docker rmi ${IMAGE_NAME}:latest || true
            """
        }
    }
}