# Trivy Offline Scanner - Jenkins Integration Guide

## Overview

This guide shows how to integrate the Trivy offline scanner with Jenkins for automated container security scanning in your CI/CD pipeline.

## Prerequisites

- Jenkins server with Docker support
- Docker plugin installed
- Pipeline plugin installed
- HTML Publisher plugin (for reports)
- Git plugin (if using SCM)

## Setup Steps

### 1. Install Scanner on Jenkins Server

```bash
# Copy the deployment package to Jenkins server
scp trivy-offline-scanner-*.tar.gz jenkins-server:/opt/

# On Jenkins server
sudo su - jenkins
cd /opt
tar -xzf trivy-offline-scanner-*.tar.gz
cd trivy-offline-scanner-*
./install-offline.sh

# Move to standard location
sudo mkdir -p /opt/trivy-offline-scanner
sudo cp -r * /opt/trivy-offline-scanner/
sudo chown -R jenkins:jenkins /opt/trivy-offline-scanner

# Setup database and cache directories
sudo mkdir -p /var/lib/jenkins/trivy-db
sudo mkdir -p /var/lib/jenkins/trivy-cache
sudo cp -r trivy-db/* /var/lib/jenkins/trivy-db/
sudo chown -R jenkins:jenkins /var/lib/jenkins/trivy-*
```

### 2. Install Required Jenkins Plugins

Go to **Manage Jenkins** → **Manage Plugins** and install:

- Pipeline
- Docker Pipeline
- HTML Publisher
- Blue Ocean (optional, for better UI)
- Email Extension (for notifications)

### 3. Create Jenkins Job

#### Option A: Using Jenkins UI

1. **New Item** → **Pipeline**
2. **Configure** → **Pipeline**
3. Select **Pipeline script from SCM** or **Pipeline script**
4. Copy the `Jenkinsfile` content

#### Option B: Using Job DSL or Configuration as Code

```groovy
// JobDSL example
pipelineJob('container-security-scan') {
    description('Scan Docker images for security vulnerabilities')
    parameters {
        stringParam('DOCKER_IMAGE', '', 'Docker image to scan')
        choiceParam('SEVERITY_THRESHOLD', ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'], 'Severity threshold')
        choiceParam('OUTPUT_FORMAT', ['table', 'json', 'cyclonedx', 'spdx'], 'Output format')
        booleanParam('FAIL_ON_VULNERABILITIES', true, 'Fail build on vulnerabilities')
    }
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://your-repo/trivy-scanner.git')
                        credentials('git-credentials')
                    }
                    branch('main')
                }
            }
            scriptPath('jenkins/Jenkinsfile')
        }
    }
}
```

### 4. Setup Shared Library (Optional)

1. **Manage Jenkins** → **Configure System**
2. **Global Pipeline Libraries** → **Add**
3. Configure your shared library repository

Place `TrivyScannerLibrary.groovy` in `vars/trivyScanner.groovy` in your shared library repo.

### 5. Configure Permissions

Ensure Jenkins user can run Docker:

```bash
# Add jenkins user to docker group
sudo usermod -a -G docker jenkins

# Restart Jenkins
sudo systemctl restart jenkins
```

## Usage Examples

### Basic Pipeline Usage

```groovy
pipeline {
    agent any
    stages {
        stage('Security Scan') {
            steps {
                script {
                    // Using the Jenkinsfile parameters
                    build job: 'container-security-scan', parameters: [
                        string(name: 'DOCKER_IMAGE', value: 'nginx:latest'),
                        string(name: 'SEVERITY_THRESHOLD', value: 'HIGH'),
                        string(name: 'OUTPUT_FORMAT', value: 'json'),
                        booleanParam(name: 'FAIL_ON_VULNERABILITIES', value: true)
                    ]
                }
            }
        }
    }
}
```

### Using Shared Library

```groovy
@Library('your-shared-library') _

pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                script {
                    // Build your Docker image
                    sh "docker build -t myapp:${BUILD_NUMBER} ."
                }
            }
        }
        stage('Security Scan') {
            steps {
                script {
                    // Scan the built image
                    def scanResult = trivyScanner(
                        image: "myapp:${BUILD_NUMBER}",
                        severity: 'CRITICAL,HIGH',
                        format: 'json',
                        failOnVulnerabilities: true
                    )
                    
                    // Check against policy
                    def policyCheck = trivyScanner.checkPolicy(scanResult, [
                        maxCritical: 0,
                        maxHigh: 5
                    ])
                    
                    if (!policyCheck.compliant) {
                        error("Security policy violations: ${policyCheck.violations}")
                    }
                    
                    // Generate summary
                    echo trivyScanner.generateSummary(scanResult)
                }
            }
        }
    }
}
```

### Multi-Stage Build with Security Gates

```groovy
pipeline {
    agent any
    environment {
        REGISTRY = "your-registry.com"
        IMAGE_NAME = "myapp"
        IMAGE_TAG = "${BUILD_NUMBER}"
    }
    
    stages {
        stage('Build') {
            steps {
                script {
                    sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                }
            }
        }
        
        stage('Security Scan - Pre-Deploy') {
            steps {
                script {
                    // Strict scan before deployment
                    build job: 'container-security-scan', parameters: [
                        string(name: 'DOCKER_IMAGE', value: "${IMAGE_NAME}:${IMAGE_TAG}"),
                        string(name: 'SEVERITY_THRESHOLD', value: 'CRITICAL'),
                        string(name: 'OUTPUT_FORMAT', value: 'json'),
                        booleanParam(name: 'FAIL_ON_VULNERABILITIES', value: true)
                    ]
                }
            }
        }
        
        stage('Push to Registry') {
            steps {
                script {
                    sh """
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    """
                }
            }
        }
        
        stage('Security Scan - Full Report') {
            steps {
                script {
                    // Comprehensive scan for reporting
                    build job: 'container-security-scan', parameters: [
                        string(name: 'DOCKER_IMAGE', value: "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"),
                        string(name: 'SEVERITY_THRESHOLD', value: 'LOW'),
                        string(name: 'OUTPUT_FORMAT', value: 'json'),
                        booleanParam(name: 'FAIL_ON_VULNERABILITIES', value: false)
                    ]
                }
            }
        }
    }
}
```

## Automation and Scheduling

### 1. Scheduled Scans

```groovy
// In your pipeline
triggers {
    // Scan all production images daily at 2 AM
    cron('0 2 * * *')
}
```

### 2. Webhook Triggers

Configure webhooks to trigger scans when:
- New images are pushed to registry
- Base images are updated
- Security database is updated

### 3. Database Update Job

Create a separate job to update the Trivy database:

```groovy
pipeline {
    agent any
    triggers {
        // Update database weekly
        cron('0 1 * * 0')
    }
    stages {
        stage('Update Database') {
            steps {
                script {
                    sh '''
                        cd /opt/trivy-offline-scanner
                        ./scan-offline.sh update-db
                        
                        # Copy to Jenkins cache
                        cp -r trivy-db/* /var/lib/jenkins/trivy-db/
                        
                        # Clean old cache
                        rm -rf /var/lib/jenkins/trivy-cache/*
                    '''
                }
            }
        }
    }
    post {
        success {
            // Trigger scans of critical images
            build job: 'rescan-production-images'
        }
    }
}
```

## Notifications

### Email Notifications

```groovy
post {
    failure {
        emailext (
            subject: "Security Scan FAILED: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
            body: """
            Security scan failed for image: ${params.DOCKER_IMAGE}
            
            Build URL: ${env.BUILD_URL}
            Console: ${env.BUILD_URL}console
            
            Please review the scan results and address any security vulnerabilities.
            """,
            to: "${env.CHANGE_AUTHOR_EMAIL}, security-team@company.com"
        )
    }
    always {
        script {
            if (currentBuild.description?.contains('Vulnerabilities:')) {
                emailext (
                    subject: "Security Scan Report: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
                    body: """
                    Security scan completed for image: ${params.DOCKER_IMAGE}
                    
                    ${currentBuild.description}
                    
                    Full report: ${env.BUILD_URL}Trivy_Security_Scan_Report/
                    """,
                    to: "security-team@company.com"
                )
            }
        }
    }
}
```

### Slack Integration

```groovy
post {
    always {
        script {
            def color = currentBuild.result == 'SUCCESS' ? 'good' : 'danger'
            def message = """
            Security Scan: ${currentBuild.result}
            Image: ${params.DOCKER_IMAGE}
            ${currentBuild.description ?: 'No vulnerabilities summary available'}
            <${env.BUILD_URL}|View Build>
            """
            
            slackSend(
                channel: '#security',
                color: color,
                message: message
            )
        }
    }
}
```

## Troubleshooting

### Common Issues

1. **Docker permission denied**
   ```bash
   sudo usermod -a -G docker jenkins
   sudo systemctl restart jenkins
   ```

2. **Database not found**
   ```bash
   # Check database location
   ls -la /var/lib/jenkins/trivy-db/
   
   # Copy database
   sudo cp -r /opt/trivy-offline-scanner/trivy-db/* /var/lib/jenkins/trivy-db/
   sudo chown -R jenkins:jenkins /var/lib/jenkins/trivy-db
   ```

3. **Cache permission issues**
   ```bash
   sudo mkdir -p /var/lib/jenkins/trivy-cache
   sudo chown -R jenkins:jenkins /var/lib/jenkins/trivy-cache
   ```

4. **Pipeline script errors**
   - Check Jenkins logs: `/var/log/jenkins/jenkins.log`
   - Validate Jenkinsfile syntax in Jenkins UI
   - Test with simple pipeline first

### Performance Optimization

1. **Use Jenkins agents** for parallel scanning
2. **Cache Docker images** to avoid repeated pulls
3. **Database persistence** to avoid re-downloading
4. **Result caching** for repeated scans of same image

## Security Best Practices

1. **Least privilege** - Jenkins user should have minimal required permissions
2. **Secure database** - Protect the vulnerability database
3. **Audit trails** - Log all scan activities
4. **Regular updates** - Keep database and tools updated
5. **Policy enforcement** - Define and enforce security policies
6. **Secrets management** - Use Jenkins credentials for registry access

## Integration with Other Tools

- **SonarQube**: Combine with code quality scans
- **JIRA**: Auto-create tickets for vulnerabilities
- **Grafana**: Dashboard for security metrics
- **Harbor/Nexus**: Registry integration for automated scanning