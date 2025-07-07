// Scan multiple images in parallel
pipeline {
    agent any
    
    parameters {
        text(name: 'IMAGES_TO_SCAN', 
             defaultValue: 'nginx:latest\nredis:alpine\npostgres:13', 
             description: 'List of images to scan (one per line)')
    }
    
    stages {
        stage('Parallel Scans') {
            steps {
                script {
                    def images = params.IMAGES_TO_SCAN.split('\n').findAll { it.trim() }
                    def parallelSteps = [:]
                    
                    images.each { image ->
                        def sanitizedName = image.replace(':', '_').replace('/', '_')
                        parallelSteps["Scan ${image}"] = {
                            build job: 'container-security-scan', parameters: [
                                string(name: 'DOCKER_IMAGE', value: image.trim()),
                                string(name: 'SEVERITY_THRESHOLD', value: 'HIGH'),
                                string(name: 'OUTPUT_FORMAT', value: 'json'),
                                booleanParam(name: 'FAIL_ON_VULNERABILITIES', value: false)
                            ]
                        }
                    }
                    
                    // Execute all scans in parallel
                    parallel parallelSteps
                }
            }
        }
    }
    
    post {
        always {
            echo "Completed scanning ${params.IMAGES_TO_SCAN.split('\n').size()} images"
        }
    }
}