// Simple Trivy scan example
pipeline {
    agent any
    
    parameters {
        string(name: 'IMAGE_TO_SCAN', defaultValue: 'nginx:latest', description: 'Docker image to scan')
    }
    
    stages {
        stage('Scan Image') {
            steps {
                script {
                    // Simple scan using the main pipeline
                    build job: 'container-security-scan', parameters: [
                        string(name: 'DOCKER_IMAGE', value: params.IMAGE_TO_SCAN),
                        string(name: 'SEVERITY_THRESHOLD', value: 'HIGH'),
                        string(name: 'OUTPUT_FORMAT', value: 'table'),
                        booleanParam(name: 'FAIL_ON_VULNERABILITIES', value: false)
                    ]
                }
            }
        }
    }
}