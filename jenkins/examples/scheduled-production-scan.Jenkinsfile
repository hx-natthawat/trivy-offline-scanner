// Scheduled scan of production images
pipeline {
    agent any
    
    triggers {
        // Run every night at 2 AM
        cron('0 2 * * *')
    }
    
    environment {
        PRODUCTION_REGISTRY = "production-registry.company.com"
        SLACK_CHANNEL = "#security-alerts"
    }
    
    stages {
        stage('Get Production Images') {
            steps {
                script {
                    // Get list of production images from registry or config
                    env.PRODUCTION_IMAGES = sh(
                        script: '''
                            # Example: Query your registry or read from config file
                            echo "nginx:latest
                            myapp:v1.2.3
                            postgres:13
                            redis:6-alpine"
                        ''',
                        returnStdout: true
                    ).trim()
                }
            }
        }
        
        stage('Scan Production Images') {
            steps {
                script {
                    def images = env.PRODUCTION_IMAGES.split('\n')
                    def results = []
                    
                    images.each { image ->
                        if (image.trim()) {
                            try {
                                def scanResult = build job: 'container-security-scan',
                                    parameters: [
                                        string(name: 'DOCKER_IMAGE', value: "${PRODUCTION_REGISTRY}/${image.trim()}"),
                                        string(name: 'SEVERITY_THRESHOLD', value: 'MEDIUM'),
                                        string(name: 'OUTPUT_FORMAT', value: 'json'),
                                        booleanParam(name: 'FAIL_ON_VULNERABILITIES', value: false)
                                    ],
                                    returnStatusCode: true
                                
                                results << [
                                    image: image.trim(),
                                    status: scanResult == 0 ? 'PASS' : 'FAIL',
                                    build: scanResult
                                ]
                            } catch (Exception e) {
                                results << [
                                    image: image.trim(),
                                    status: 'ERROR',
                                    error: e.message
                                ]
                            }
                        }
                    }
                    
                    // Store results for reporting
                    env.SCAN_RESULTS = results.collect { 
                        "${it.image}: ${it.status}" 
                    }.join('\n')
                }
            }
        }
        
        stage('Generate Report') {
            steps {
                script {
                    def reportContent = """
                    # Production Security Scan Report
                    Date: ${new Date()}
                    
                    ## Scan Results
                    ${env.SCAN_RESULTS}
                    
                    ## Summary
                    - Total images scanned: ${env.PRODUCTION_IMAGES.split('\n').size()}
                    - Failed scans: ${env.SCAN_RESULTS.count('FAIL')}
                    - Error scans: ${env.SCAN_RESULTS.count('ERROR')}
                    
                    Full details available in Jenkins build: ${env.BUILD_URL}
                    """
                    
                    writeFile file: 'production-scan-report.md', text: reportContent
                    archiveArtifacts artifacts: 'production-scan-report.md'
                }
            }
        }
    }
    
    post {
        always {
            script {
                def failedCount = env.SCAN_RESULTS?.count('FAIL') ?: 0
                def errorCount = env.SCAN_RESULTS?.count('ERROR') ?: 0
                
                if (failedCount > 0 || errorCount > 0) {
                    // Send alert for failures
                    def alertMessage = """
                    🚨 Production Security Scan Alert 🚨
                    
                    Failed scans: ${failedCount}
                    Error scans: ${errorCount}
                    
                    Details: ${env.BUILD_URL}
                    """
                    
                    // Uncomment and configure for your notification system
                    // slackSend(channel: env.SLACK_CHANNEL, color: 'danger', message: alertMessage)
                    // emailext(subject: "Production Security Scan Alert", body: alertMessage, to: "security-team@company.com")
                    
                    echo alertMessage
                }
            }
        }
        success {
            echo "All production images scanned successfully"
        }
        failure {
            echo "Production scan pipeline failed"
        }
    }
}