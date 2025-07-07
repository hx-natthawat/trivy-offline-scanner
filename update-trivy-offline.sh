#!/bin/bash

# Trivy Offline Update Script
# This script updates both the Trivy database and cache for offline usage
# Run this on a system with internet access, then transfer to offline environment

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="${SCRIPT_DIR}/trivy-db"
CACHE_DIR="${SCRIPT_DIR}/trivy-cache"
BACKUP_DIR="${SCRIPT_DIR}/backups"
PACKAGE_DIR="${SCRIPT_DIR}/packages"
LOG_FILE="${SCRIPT_DIR}/trivy-update.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create necessary directories
mkdir -p "${DB_DIR}" "${CACHE_DIR}" "${BACKUP_DIR}" "${PACKAGE_DIR}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check internet connectivity
check_internet() {
    log "Checking internet connectivity..."
    if ! curl -s --head --connect-timeout 5 https://github.com > /dev/null; then
        print_status "$RED" "ERROR: No internet connection available"
        exit 1
    fi
    print_status "$GREEN" "✓ Internet connection verified"
}

# Get current database version
get_db_version() {
    local db_path=$1
    if [ -f "${db_path}/metadata.json" ]; then
        jq -r '.Version' "${db_path}/metadata.json" 2>/dev/null || echo "unknown"
    else
        echo "none"
    fi
}

# Backup current database and cache
backup_current() {
    log "Creating backup of current database and cache..."
    
    local backup_name="trivy-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    mkdir -p "${backup_path}"
    
    # Backup database
    if [ -d "${DB_DIR}" ] && [ "$(ls -A ${DB_DIR})" ]; then
        cp -r "${DB_DIR}" "${backup_path}/"
        print_status "$GREEN" "✓ Database backed up"
    fi
    
    # Backup cache
    if [ -d "${CACHE_DIR}" ] && [ "$(ls -A ${CACHE_DIR})" ]; then
        cp -r "${CACHE_DIR}" "${backup_path}/"
        print_status "$GREEN" "✓ Cache backed up"
    fi
    
    # Keep only last 5 backups
    cd "${BACKUP_DIR}"
    ls -t | tail -n +6 | xargs -r rm -rf
    cd - > /dev/null
    
    log "Backup completed: ${backup_path}"
}

# Download and update Trivy database
update_database() {
    log "Updating Trivy database..."
    
    # Get current version
    local current_version=$(get_db_version "${DB_DIR}")
    print_status "$BLUE" "Current database version: ${current_version}"
    
    # Create temporary directory for download
    local temp_dir=$(mktemp -d)
    log "Downloading to temporary directory: ${temp_dir}"
    
    # Pull latest Trivy image first
    print_status "$YELLOW" "Pulling latest Trivy Docker image..."
    docker pull aquasec/trivy:latest
    
    # Download database
    print_status "$YELLOW" "Downloading latest vulnerability database..."
    docker run --rm \
        -v "${temp_dir}:/root/.cache/trivy" \
        aquasec/trivy:latest \
        image --download-db-only
    
    # Verify download
    if [ ! -f "${temp_dir}/db/trivy.db" ] || [ ! -f "${temp_dir}/db/metadata.json" ]; then
        print_status "$RED" "ERROR: Database download failed"
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    # Get new version
    local new_version=$(get_db_version "${temp_dir}/db")
    print_status "$BLUE" "New database version: ${new_version}"
    
    # Update database
    rm -rf "${DB_DIR}"
    mkdir -p "${DB_DIR}"
    cp -r "${temp_dir}/db/"* "${DB_DIR}/"
    
    # Also update cache database
    mkdir -p "${CACHE_DIR}/db"
    cp -r "${temp_dir}/db/"* "${CACHE_DIR}/db/"
    
    # Clean up
    rm -rf "${temp_dir}"
    
    print_status "$GREEN" "✓ Database updated successfully"
    log "Database updated from ${current_version} to ${new_version}"
}

# Update Java database (for JAR vulnerability scanning)
update_java_db() {
    log "Updating Java vulnerability database..."
    
    local temp_dir=$(mktemp -d)
    
    # Download Java DB
    print_status "$YELLOW" "Downloading Java vulnerability database..."
    docker run --rm \
        -v "${temp_dir}:/root/.cache/trivy" \
        -e TRIVY_DOWNLOAD_JAVA_DB_ONLY=true \
        aquasec/trivy:latest \
        image --download-java-db-only || {
            print_status "$YELLOW" "⚠ Java DB download not available in this version"
        }
    
    # Copy Java DB if it exists
    if [ -d "${temp_dir}/java-db" ]; then
        mkdir -p "${CACHE_DIR}/java-db"
        cp -r "${temp_dir}/java-db/"* "${CACHE_DIR}/java-db/" 2>/dev/null || true
        print_status "$GREEN" "✓ Java database updated"
    fi
    
    rm -rf "${temp_dir}"
}

# Verify database integrity
verify_database() {
    log "Verifying database integrity..."
    
    # Check main database
    if [ ! -f "${DB_DIR}/trivy.db" ]; then
        print_status "$RED" "ERROR: Database file not found"
        exit 1
    fi
    
    # Check file size (should be at least 100MB)
    local db_size=$(stat -f%z "${DB_DIR}/trivy.db" 2>/dev/null || stat -c%s "${DB_DIR}/trivy.db" 2>/dev/null)
    if [ "$db_size" -lt 104857600 ]; then
        print_status "$RED" "ERROR: Database file too small (${db_size} bytes)"
        exit 1
    fi
    
    # Check metadata
    if ! jq -e '.Version' "${DB_DIR}/metadata.json" >/dev/null 2>&1; then
        print_status "$RED" "ERROR: Invalid metadata file"
        exit 1
    fi
    
    # Check database age
    local updated_at=$(jq -r '.UpdatedAt' "${DB_DIR}/metadata.json")
    local age_days=$(( ($(date +%s) - $(date -d "$updated_at" +%s)) / 86400 ))
    
    if [ $age_days -gt 7 ]; then
        print_status "$YELLOW" "⚠ WARNING: Database is ${age_days} days old"
    else
        print_status "$GREEN" "✓ Database age: ${age_days} days (OK)"
    fi
    
    print_status "$GREEN" "✓ Database verification passed"
}

# Create offline package
create_package() {
    log "Creating offline deployment package..."
    
    local package_name="trivy-offline-$(date +%Y%m%d-%H%M%S)"
    local package_path="${PACKAGE_DIR}/${package_name}"
    
    mkdir -p "${package_path}"
    
    # Copy all necessary files
    cp -r "${DB_DIR}" "${package_path}/"
    cp -r "${CACHE_DIR}" "${package_path}/"
    
    # Copy scripts and configs if they exist
    [ -f "${SCRIPT_DIR}/scan-offline.sh" ] && cp "${SCRIPT_DIR}/scan-offline.sh" "${package_path}/"
    [ -f "${SCRIPT_DIR}/trivy-config.yaml" ] && cp "${SCRIPT_DIR}/trivy-config.yaml" "${package_path}/"
    [ -f "${SCRIPT_DIR}/docker-compose.yml" ] && cp "${SCRIPT_DIR}/docker-compose.yml" "${package_path}/"
    [ -f "${SCRIPT_DIR}/trivy_offline_scanner.py" ] && cp "${SCRIPT_DIR}/trivy_offline_scanner.py" "${package_path}/"
    
    # Create manifest
    cat > "${package_path}/manifest.json" << EOF
{
  "package_date": "$(date -Iseconds)",
  "db_version": "$(get_db_version "${DB_DIR}")",
  "db_updated": "$(jq -r '.UpdatedAt' "${DB_DIR}/metadata.json")",
  "files": [
    "trivy-db/",
    "trivy-cache/",
    "scan-offline.sh",
    "trivy-config.yaml",
    "docker-compose.yml"
  ],
  "created_by": "$(whoami)@$(hostname)"
}
EOF
    
    # Create tarball
    cd "${PACKAGE_DIR}"
    tar -czf "${package_name}.tar.gz" "${package_name}"
    
    # Generate checksum
    sha256sum "${package_name}.tar.gz" > "${package_name}.tar.gz.sha256"
    
    # Clean up directory
    rm -rf "${package_path}"
    
    cd - > /dev/null
    
    print_status "$GREEN" "✓ Package created: ${PACKAGE_DIR}/${package_name}.tar.gz"
    log "Package created with size: $(du -h "${PACKAGE_DIR}/${package_name}.tar.gz" | cut -f1)"
}

# Export Docker image
export_docker_image() {
    log "Exporting Trivy Docker image..."
    
    local image_name="trivy-docker-image-$(date +%Y%m%d).tar"
    local image_path="${PACKAGE_DIR}/${image_name}"
    
    print_status "$YELLOW" "Saving Docker image (this may take a moment)..."
    docker save aquasec/trivy:latest -o "${image_path}"
    
    # Compress the image
    gzip "${image_path}"
    
    # Generate checksum
    sha256sum "${image_path}.gz" > "${image_path}.gz.sha256"
    
    print_status "$GREEN" "✓ Docker image exported: ${image_path}.gz"
    log "Docker image size: $(du -h "${image_path}.gz" | cut -f1)"
}

# Generate deployment instructions
generate_instructions() {
    local instructions_file="${PACKAGE_DIR}/DEPLOYMENT_INSTRUCTIONS.md"
    
    cat > "${instructions_file}" << 'EOF'
# Trivy Offline Deployment Instructions

## Package Contents
- `trivy-db/` - Vulnerability database
- `trivy-cache/` - Cache directory with database copy
- `scan-offline.sh` - Scanning script
- `trivy-config.yaml` - Trivy configuration
- `manifest.json` - Package information

## Deployment Steps

1. **Transfer files to offline system**
   ```bash
   # Verify checksum
   sha256sum -c trivy-offline-*.tar.gz.sha256
   
   # Extract package
   tar -xzf trivy-offline-*.tar.gz
   cd trivy-offline-*
   ```

2. **Load Docker image** (if provided)
   ```bash
   # Verify checksum
   sha256sum -c trivy-docker-image-*.tar.gz.sha256
   
   # Load image
   gunzip -c trivy-docker-image-*.tar.gz | docker load
   ```

3. **Set up directories**
   ```bash
   # Copy to final location
   sudo cp -r trivy-db /opt/trivy/
   sudo cp -r trivy-cache /opt/trivy/
   
   # Set permissions
   sudo chmod -R 755 /opt/trivy/
   ```

4. **Test the setup**
   ```bash
   ./scan-offline.sh scan -i alpine:latest
   ```

## Usage
See README.md for detailed usage instructions.
EOF
    
    print_status "$GREEN" "✓ Deployment instructions generated"
}

# Summary report
generate_summary() {
    local summary_file="${PACKAGE_DIR}/update-summary-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "${summary_file}" << EOF
Trivy Offline Update Summary
============================
Date: $(date)
User: $(whoami)@$(hostname)

Database Information:
- Version: $(get_db_version "${DB_DIR}")
- Updated: $(jq -r '.UpdatedAt' "${DB_DIR}/metadata.json")
- Next Update: $(jq -r '.NextUpdate' "${DB_DIR}/metadata.json" 2>/dev/null || echo "N/A")

Package Location:
$(ls -la "${PACKAGE_DIR}"/trivy-offline-*.tar.gz 2>/dev/null | tail -1)

Docker Image:
$(ls -la "${PACKAGE_DIR}"/trivy-docker-image-*.tar.gz 2>/dev/null | tail -1 || echo "Not exported")

Actions Performed:
✓ Internet connectivity verified
✓ Current data backed up
✓ Database updated
✓ Cache updated
✓ Database verified
✓ Offline package created
✓ Instructions generated

Next Steps:
1. Transfer package to offline environment
2. Deploy using provided instructions
3. Test scanning functionality
4. Schedule next update (recommended: within 7 days)
EOF
    
    print_status "$GREEN" "\n✓ Update completed successfully!"
    print_status "$BLUE" "\nSummary saved to: ${summary_file}"
    cat "${summary_file}"
}

# Main execution
main() {
    print_status "$BLUE" "=== Trivy Offline Update Script ==="
    print_status "$BLUE" "Starting at: $(date)"
    
    # Parse command line options
    SKIP_DOCKER_EXPORT=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-docker)
                SKIP_DOCKER_EXPORT=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-docker    Skip Docker image export"
                echo "  --help, -h       Show this help message"
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute update steps
    check_internet
    backup_current
    update_database
    update_java_db
    verify_database
    create_package
    
    if [ "$SKIP_DOCKER_EXPORT" = false ]; then
        export_docker_image
    fi
    
    generate_instructions
    generate_summary
    
    print_status "$BLUE" "\nCompleted at: $(date)"
}

# Run main function
main "$@"