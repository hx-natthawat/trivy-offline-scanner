// Jenkins Shared Library for Trivy Scanner
// Place this in your Jenkins shared library under vars/trivyScanner.groovy

def call(Map config = [:]) {
    // Default configuration
    def defaultConfig = [
        image: '',
        severity: 'HIGH,CRITICAL',
        format: 'json',
        failOnVulnerabilities: true,
        outputDir: "${env.WORKSPACE}/scan-results",
        trivyDbPath: '/var/lib/jenkins/trivy-db',
        trivyCachePath: '/var/lib/jenkins/trivy-cache'
    ]
    
    // Merge with provided config
    def scanConfig = defaultConfig + config
    
    if (!scanConfig.image) {
        error "Docker image must be specified for scanning"
    }
    
    return scanImage(scanConfig)
}

def scanImage(Map config) {
    def scanResult = [
        success: false,
        vulnerabilities: [:],
        totalCount: 0,
        report: '',
        exitCode: 0
    ]
    
    try {
        // Ensure directories exist
        sh """
            mkdir -p ${config.outputDir}
            mkdir -p ${config.trivyCachePath}/db
        """
        
        // Copy database to cache if needed
        sh """
            if [ ! -f ${config.trivyCachePath}/db/trivy.db ] && [ -f ${config.trivyDbPath}/trivy.db ]; then
                cp ${config.trivyDbPath}/* ${config.trivyCachePath}/db/
            fi
        """
        
        // Generate output filename
        def timestamp = new Date().format('yyyyMMdd_HHmmss')
        def sanitizedImage = config.image.replace('/', '_').replace(':', '_')
        def outputFile = "${config.outputDir}/trivy_scan_${sanitizedImage}_${timestamp}.${config.format}"
        
        // Run Trivy scan
        scanResult.exitCode = sh(
            returnStatus: true,
            script: """
                docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock:ro \
                    -v ${config.trivyCachePath}:/root/.cache/trivy \
                    -v ${config.outputDir}:/output \
                    -e TRIVY_CACHE_DIR=/root/.cache/trivy \
                    -e TRIVY_SKIP_DB_UPDATE=true \
                    -e TRIVY_SKIP_JAVA_DB_UPDATE=true \
                    aquasec/trivy:latest \
                    image \
                    --format ${config.format} \
                    --severity ${config.severity} \
                    --output /output/\$(basename ${outputFile}) \
                    ${config.image}
            """
        )
        
        scanResult.report = outputFile
        
        // Parse results if JSON format
        if (config.format == 'json' && fileExists(outputFile)) {
            def jsonResults = readJSON file: outputFile
            scanResult.vulnerabilities = parseVulnerabilities(jsonResults)
            scanResult.totalCount = countVulnerabilities(jsonResults, config.severity.split(','))
        }
        
        scanResult.success = (scanResult.exitCode == 0)
        
        // Handle build failure
        if (config.failOnVulnerabilities && scanResult.exitCode != 0) {
            error "Security scan failed: Found ${scanResult.totalCount} vulnerabilities in ${config.image}"
        }
        
    } catch (Exception e) {
        scanResult.error = e.message
        if (config.failOnVulnerabilities) {
            throw e
        }
    }
    
    return scanResult
}

def parseVulnerabilities(jsonResults) {
    def vulnMap = [
        'CRITICAL': [],
        'HIGH': [],
        'MEDIUM': [],
        'LOW': [],
        'UNKNOWN': []
    ]
    
    jsonResults.Results?.each { result ->
        result.Vulnerabilities?.each { vuln ->
            def severity = vuln.Severity ?: 'UNKNOWN'
            vulnMap[severity] << [
                id: vuln.VulnerabilityID,
                pkg: vuln.PkgName,
                version: vuln.InstalledVersion,
                fixedVersion: vuln.FixedVersion,
                title: vuln.Title
            ]
        }
    }
    
    return vulnMap
}

def countVulnerabilities(jsonResults, severityFilter) {
    def count = 0
    jsonResults.Results?.each { result ->
        result.Vulnerabilities?.each { vuln ->
            if (severityFilter.contains(vuln.Severity)) {
                count++
            }
        }
    }
    return count
}

// Convenience methods for specific severity scans
def scanCritical(String image) {
    return call(image: image, severity: 'CRITICAL')
}

def scanHighCritical(String image) {
    return call(image: image, severity: 'CRITICAL,HIGH')
}

def scanAll(String image) {
    return call(image: image, severity: 'CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN')
}

// Generate summary report
def generateSummary(scanResult) {
    def summary = """
    ===== Trivy Security Scan Summary =====
    Image: ${scanResult.image ?: 'Unknown'}
    Status: ${scanResult.success ? 'PASSED' : 'FAILED'}
    Total Vulnerabilities: ${scanResult.totalCount}
    
    Breakdown by Severity:
    """
    
    scanResult.vulnerabilities?.each { severity, vulns ->
        summary += "  ${severity}: ${vulns.size()}\n"
    }
    
    if (scanResult.error) {
        summary += "\nError: ${scanResult.error}\n"
    }
    
    summary += "=====================================\n"
    
    return summary
}

// Method to check if image is safe based on policy
def checkPolicy(scanResult, Map policy = [:]) {
    def defaultPolicy = [
        maxCritical: 0,
        maxHigh: 5,
        maxMedium: 20,
        maxLow: 50
    ]
    
    def activePolicy = defaultPolicy + policy
    
    def violations = []
    
    if (scanResult.vulnerabilities.CRITICAL?.size() > activePolicy.maxCritical) {
        violations << "CRITICAL vulnerabilities exceed limit (${scanResult.vulnerabilities.CRITICAL.size()} > ${activePolicy.maxCritical})"
    }
    
    if (scanResult.vulnerabilities.HIGH?.size() > activePolicy.maxHigh) {
        violations << "HIGH vulnerabilities exceed limit (${scanResult.vulnerabilities.HIGH.size()} > ${activePolicy.maxHigh})"
    }
    
    if (scanResult.vulnerabilities.MEDIUM?.size() > activePolicy.maxMedium) {
        violations << "MEDIUM vulnerabilities exceed limit (${scanResult.vulnerabilities.MEDIUM.size()} > ${activePolicy.maxMedium})"
    }
    
    if (scanResult.vulnerabilities.LOW?.size() > activePolicy.maxLow) {
        violations << "LOW vulnerabilities exceed limit (${scanResult.vulnerabilities.LOW.size()} > ${activePolicy.maxLow})"
    }
    
    return [
        compliant: violations.isEmpty(),
        violations: violations
    ]
}