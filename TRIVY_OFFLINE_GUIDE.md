# Trivy Offline Database and Cache Management Guide

This guide provides comprehensive instructions for preparing, updating, and maintaining Trivy vulnerability database and cache for use in offline (air-gapped) networks.

## Table of Contents

1. [Overview](#overview)
2. [Understanding Trivy Components](#understanding-trivy-components)
3. [Initial Database Preparation](#initial-database-preparation)
4. [Database Update Process](#database-update-process)
5. [Cache Management](#cache-management)
6. [Offline Deployment](#offline-deployment)
7. [Maintenance Schedule](#maintenance-schedule)
8. [Troubleshooting](#troubleshooting)
9. [Security Considerations](#security-considerations)

## Overview

Trivy requires two main components for vulnerability scanning:

- **Vulnerability Database (trivy-db)**: Contains CVE information and vulnerability metadata
- **Cache Directory (trivy-cache)**: Stores analysis results and temporary data

In offline environments, these components must be prepared on a system with internet access and then transferred to the isolated network.

## Understanding Trivy Components

### Vulnerability Database (trivy-db)

- Located in `trivy-db/` directory
- Contains:
  - `trivy.db`: SQLite database with vulnerability information
  - `metadata.json`: Database version and update information
- Updated bi-daily by Aqua Security
- Size: ~200-300MB

### Cache Directory (trivy-cache)

- Located in `trivy-cache/` directory
- Contains:
  - `db/`: Copy of the vulnerability database
  - `fanal/`: Analysis cache for scanned images
- Grows over time as more images are scanned

## Initial Database Preparation

### Method 1: Using Docker (Recommended)

1. **On a system with internet access**, create a working directory:

```bash
mkdir trivy-offline-prep
cd trivy-offline-prep
```

2. **Download the latest Trivy database**:

```bash
# Create directories
mkdir -p trivy-db trivy-cache

# Download database using Trivy
docker run --rm \
  -v $(pwd)/trivy-cache:/root/.cache/trivy \
  aquasec/trivy:latest \
  image --download-db-only

# Copy database to dedicated directory
cp -r trivy-cache/db/* trivy-db/
```

3. **Verify the database**:

```bash
ls -la trivy-db/
# Should show:
# - trivy.db (main database file)
# - metadata.json (version information)
```

### Method 2: Direct Download

1. **Download from GitHub** (alternative method):

```bash
# Get the latest release URL
TRIVY_DB_URL=$(curl -s https://api.github.com/repos/aquasecurity/trivy-db/releases/latest | \
  grep "browser_download_url.*trivy-offline.db.tgz" | \
  cut -d '"' -f 4)

# Download and extract
wget $TRIVY_DB_URL -O trivy-offline.db.tgz
mkdir -p trivy-db
tar -xzf trivy-offline.db.tgz -C trivy-db
```

### Method 3: Using the Provided Script

```bash
# Use the scan-offline.sh script
./scan-offline.sh setup
```

## Database Update Process

### When Internet is Available - Update Strategy

The Trivy vulnerability database is updated twice daily by Aqua Security with new CVEs, security advisories, and vulnerability metadata. To maintain effective security scanning in offline environments, you must establish a regular update routine during periods when internet access is available.

#### Update Windows and Planning

1. **Scheduled Internet Access**
   - Plan regular maintenance windows when systems can access the internet
   - Coordinate with network security teams for temporary access
   - Document all internet access periods for compliance

2. **Update Frequency Guidelines**
   - **Minimum**: Weekly updates during maintenance windows
   - **Recommended**: Bi-weekly updates for high-security environments
   - **Critical**: Immediate updates when zero-day vulnerabilities are announced

3. **Pre-Update Checklist**

   ```bash
   # Before connecting to internet, verify:
   - [ ] Current database version and age
   - [ ] Available disk space (need ~500MB free)
   - [ ] Backup of current database completed
   - [ ] Update scripts are ready
   - [ ] Transfer media prepared (USB, etc.)
   ```

### Regular Updates (Recommended: Weekly)

1. **Check current database version**:

```bash
cat trivy-db/metadata.json | jq '.Version'
```

2. **Update the database**:

```bash
# Using Docker
docker run --rm \
  -v $(pwd)/trivy-db-new:/root/.cache/trivy \
  aquasec/trivy:latest \
  image --download-db-only

# Or using the script
./scan-offline.sh update-db
```

3. **Compare versions**:

```bash
# Check new version
cat trivy-db-new/db/metadata.json | jq '.Version'

# If newer, replace old database
rm -rf trivy-db-old
mv trivy-db trivy-db-old
mv trivy-db-new/db trivy-db
```

### Automated Update Script

Create `update-trivy-db.sh`:

```bash
#!/bin/bash
set -e

DB_DIR="/path/to/trivy-db"
BACKUP_DIR="/path/to/trivy-db-backups"
LOG_FILE="/var/log/trivy-db-update.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create backup
log "Starting Trivy database update"
mkdir -p "$BACKUP_DIR"
if [ -d "$DB_DIR" ]; then
    BACKUP_NAME="trivy-db-$(date +%Y%m%d-%H%M%S)"
    cp -r "$DB_DIR" "$BACKUP_DIR/$BACKUP_NAME"
    log "Backed up current database to $BACKUP_DIR/$BACKUP_NAME"
fi

# Download new database
TEMP_DIR=$(mktemp -d)
log "Downloading new database to $TEMP_DIR"

docker run --rm \
  -v "$TEMP_DIR:/root/.cache/trivy" \
  aquasec/trivy:latest \
  image --download-db-only

# Verify download
if [ -f "$TEMP_DIR/db/trivy.db" ] && [ -f "$TEMP_DIR/db/metadata.json" ]; then
    # Get version info
    NEW_VERSION=$(cat "$TEMP_DIR/db/metadata.json" | jq -r '.Version')
    OLD_VERSION=$(cat "$DB_DIR/metadata.json" 2>/dev/null | jq -r '.Version' || echo "unknown")
    
    log "Current version: $OLD_VERSION"
    log "New version: $NEW_VERSION"
    
    # Update database
    rm -rf "$DB_DIR"
    mkdir -p "$DB_DIR"
    cp -r "$TEMP_DIR/db/"* "$DB_DIR/"
    
    log "Database updated successfully"
    
    # Clean up old backups (keep last 5)
    cd "$BACKUP_DIR"
    ls -t | tail -n +6 | xargs -r rm -rf
else
    log "ERROR: Failed to download database"
    exit 1
fi

# Clean up
rm -rf "$TEMP_DIR"
log "Update complete"
```

### Establishing Update Procedures for Internet Access

#### Option 1: Dedicated Update System

Set up a dedicated system that can periodically access the internet:

```bash
# Create update system configuration
cat > /etc/trivy-update/config.sh << 'EOF'
#!/bin/bash
# Trivy Update System Configuration

# Paths
STAGING_DIR="/opt/trivy-staging"
OFFLINE_MEDIA="/mnt/transfer-media"
UPDATE_LOG="/var/log/trivy-updates.log"

# Network check
check_internet() {
    curl -s --head --connect-timeout 5 https://github.com > /dev/null
    return $?
}

# Update when internet is available
if check_internet; then
    echo "[$(date)] Internet available, starting update" >> "$UPDATE_LOG"
    /opt/trivy-update/update-trivy-db.sh
    
    # Package for offline transfer
    /opt/trivy-update/package-for-offline.sh
else
    echo "[$(date)] No internet access, skipping update" >> "$UPDATE_LOG"
fi
EOF
```

#### Option 2: Temporary Internet Access Procedure

For environments with controlled internet access:

```bash
#!/bin/bash
# temporary-update.sh - Run during maintenance windows

set -e

echo "=== Trivy Database Update - Maintenance Window ==="
echo "Start time: $(date)"

# 1. Enable internet access (coordinate with network team)
echo "Waiting for internet access confirmation..."
read -p "Press Enter when internet access is enabled: "

# 2. Verify connectivity
if ! curl -s --head --connect-timeout 5 https://github.com > /dev/null; then
    echo "ERROR: Cannot reach internet. Aborting."
    exit 1
fi

# 3. Quick update process
echo "Downloading latest Trivy database..."
START_TIME=$(date +%s)

# Download to staging area
STAGING="/tmp/trivy-update-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$STAGING"

docker run --rm \
    -v "$STAGING:/root/.cache/trivy" \
    aquasec/trivy:latest \
    image --download-db-only

# 4. Verify and package
if [ -f "$STAGING/db/trivy.db" ]; then
    echo "Database downloaded successfully"
    
    # Create timestamped package
    PACKAGE_NAME="trivy-db-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "/secure/transfer/$PACKAGE_NAME" -C "$STAGING/db" .
    
    # Generate manifest
    cat > "/secure/transfer/${PACKAGE_NAME}.manifest" << EOF
Update Date: $(date)
Database Version: $(cat "$STAGING/db/metadata.json" | jq -r '.Version')
Update Duration: $(($(date +%s) - START_TIME)) seconds
SHA256: $(sha256sum "/secure/transfer/$PACKAGE_NAME" | cut -d' ' -f1)
EOF
    
    echo "Package created: /secure/transfer/$PACKAGE_NAME"
else
    echo "ERROR: Database download failed"
    exit 1
fi

# 5. Cleanup
rm -rf "$STAGING"

echo "Update complete. Internet access can be disabled."
echo "End time: $(date)"
```

#### Option 3: Automated Detection and Update

For systems that occasionally get internet access:

```bash
# /etc/cron.d/trivy-opportunistic-update
# Run every hour to check for internet and update if available
0 * * * * root /opt/trivy/opportunistic-update.sh
```

Create `/opt/trivy/opportunistic-update.sh`:

```bash
#!/bin/bash

LOCKFILE="/var/lock/trivy-update.lock"
UPDATE_MARKER="/var/lib/trivy/last-update"
MIN_UPDATE_INTERVAL=86400  # 24 hours in seconds

# Prevent concurrent updates
if [ -f "$LOCKFILE" ]; then
    exit 0
fi
touch "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT

# Check if update is needed
if [ -f "$UPDATE_MARKER" ]; then
    LAST_UPDATE=$(stat -c %Y "$UPDATE_MARKER" 2>/dev/null || echo 0)
    CURRENT_TIME=$(date +%s)
    TIME_SINCE_UPDATE=$((CURRENT_TIME - LAST_UPDATE))
    
    if [ $TIME_SINCE_UPDATE -lt $MIN_UPDATE_INTERVAL ]; then
        exit 0
    fi
fi

# Check internet connectivity
if ! timeout 5 curl -s --head https://github.com > /dev/null; then
    exit 0
fi

# Internet is available - perform update
logger -t trivy-update "Internet detected, updating Trivy database"

# Run update
/opt/trivy/update-and-package.sh >> /var/log/trivy-opportunistic-update.log 2>&1

# Mark update time
touch "$UPDATE_MARKER"

# Notify administrators
if command -v mail >/dev/null 2>&1; then
    echo "Trivy database updated at $(date)" | \
        mail -s "Trivy Database Updated" security-team@company.com
fi
```

### Best Practices for Internet-Available Updates

1. **Security During Updates**

   ```bash
   # Use specific endpoints only
   ALLOWED_URLS=(
       "https://github.com/aquasecurity/trivy-db"
       "https://ghcr.io"
       "https://aquasec.github.io"
   )
   
   # Implement firewall rules during update
   for url in "${ALLOWED_URLS[@]}"; do
       # Allow only these specific URLs
       iptables -A OUTPUT -d $(dig +short $url) -j ACCEPT
   done
   ```

2. **Validation and Verification**

   ```bash
   # Always verify downloads
   verify_database() {
       local db_path=$1
       
       # Check file integrity
       if ! file "$db_path/trivy.db" | grep -q "SQLite"; then
           echo "ERROR: Invalid database file"
           return 1
       fi
       
       # Verify metadata
       if ! jq -e '.Version' "$db_path/metadata.json" >/dev/null; then
           echo "ERROR: Invalid metadata"
           return 1
       fi
       
       # Check age
       local updated_at=$(jq -r '.UpdatedAt' "$db_path/metadata.json")
       local age_days=$(( ($(date +%s) - $(date -d "$updated_at" +%s)) / 86400 ))
       
       if [ $age_days -gt 7 ]; then
           echo "WARNING: Database is $age_days days old"
       fi
       
       return 0
   }
   ```

3. **Update Logging and Auditing**

   ```bash
   # Comprehensive logging
   log_update() {
       local action=$1
       local details=$2
       
       # Log to syslog
       logger -t trivy-update -p security.info "$action: $details"
       
       # Log to audit file
       echo "[$(date -Iseconds)] $action: $details" >> /var/log/trivy-audit.log
       
       # Log to database
       if command -v sqlite3 >/dev/null; then
           sqlite3 /var/lib/trivy/updates.db <<EOF
           INSERT INTO update_log (timestamp, action, details, user)
           VALUES ('$(date -Iseconds)', '$action', '$details', '$(whoami)');

EOF
       fi
   }

   ```

## Cache Management

### Initial Cache Setup

```bash
# Create cache structure
mkdir -p trivy-cache/{db,fanal}

# Copy database to cache
cp trivy-db/* trivy-cache/db/
```

### Cache Maintenance

1. **Monitor cache size**:

```bash
du -sh trivy-cache/
```

2. **Clear old cache entries** (if needed):

```bash
# Clear analysis cache only (preserves database)
rm -rf trivy-cache/fanal/*

# Or use Trivy's built-in clear
docker run --rm \
  -v $(pwd)/trivy-cache:/root/.cache/trivy \
  aquasec/trivy:latest \
  clean --all
```

## Offline Deployment

### Package for Transfer

1. **Create deployment package**:

```bash
# Include database, cache, and scripts
tar -czf trivy-offline-$(date +%Y%m%d).tar.gz \
  trivy-db/ \
  trivy-cache/ \
  scan-offline.sh \
  trivy-config.yaml \
  docker-compose.yml

# Create checksum
sha256sum trivy-offline-*.tar.gz > checksums.txt
```

2. **Transfer to offline environment** using:
   - USB drive
   - Secure file transfer
   - Physical media

3. **Deploy on offline system**:

```bash
# Verify checksum
sha256sum -c checksums.txt

# Extract
tar -xzf trivy-offline-*.tar.gz

# Set permissions
chmod +x scan-offline.sh
```

### Docker Image Transfer

For the Trivy Docker image:

```bash
# On internet-connected system
docker pull aquasec/trivy:latest
docker save aquasec/trivy:latest -o trivy-latest.tar

# On offline system
docker load -i trivy-latest.tar
```

## Maintenance Schedule

### Recommended Update Frequency

| Component | Update Frequency | Reason |
|-----------|-----------------|---------|
| Vulnerability Database | Weekly | New CVEs published daily |
| Trivy Docker Image | Monthly | Bug fixes and features |
| Cache Cleanup | Monthly | Prevent excessive growth |
| Full System Backup | Before each update | Recovery capability |

### Update Checklist

- [ ] Check current database version
- [ ] Download latest database on internet-connected system
- [ ] Verify database integrity
- [ ] Create backup of current database
- [ ] Package for transfer
- [ ] Deploy to offline environment
- [ ] Test with sample scan
- [ ] Document update in log

## Troubleshooting

### Common Issues

1. **"Database not found" error**

   ```bash
   # Verify database files exist
   ls -la trivy-db/
   
   # Check permissions
   chmod -R 755 trivy-db/
   ```

2. **"Database is too old" warning**
   - Database should be updated at least weekly
   - Check metadata.json for NextUpdate field

3. **Large cache size**

   ```bash
   # Check what's using space
   du -h trivy-cache/* | sort -h
   
   # Clear fanal cache if needed
   rm -rf trivy-cache/fanal/*
   ```

4. **Scan performance issues**
   - Ensure cache directory is on fast storage (SSD preferred)
   - Increase Docker memory limits if needed

### Verification Commands

```bash
# Test database functionality
docker run --rm \
  -v $(pwd)/trivy-db:/trivy-db:ro \
  -v $(pwd)/trivy-cache:/root/.cache/trivy \
  -e TRIVY_DB_REPOSITORY=file:///trivy-db \
  -e TRIVY_SKIP_DB_UPDATE=true \
  aquasec/trivy:latest \
  image alpine:3.18

# Check database metadata
cat trivy-db/metadata.json | jq '.'

# Verify cache structure
find trivy-cache -type f -name "*.db" -ls
```

## Security Considerations

### Database Integrity

1. **Verify downloads**:
   - Always download from official Aqua Security sources
   - Check SSL certificates
   - Verify checksums when available

2. **Access control**:

   ```bash
   # Restrict database access
   chmod 750 trivy-db/
   chown -R trivy:trivy trivy-db/
   ```

3. **Audit trail**:
   - Log all database updates
   - Track who performed updates
   - Document transfer methods

### Operational Security

1. **Separate update system**: Use a dedicated system for database updates
2. **Secure transfer**: Encrypt database packages during transfer
3. **Version control**: Track database versions in use
4. **Rollback capability**: Keep previous database versions

### Compliance Considerations

- Document update procedures for audit requirements
- Maintain chain of custody for database files
- Regular verification of database integrity
- Compliance with organizational security policies

## Advanced Configuration

### Custom Database Location

```yaml
# trivy-config.yaml
db:
  repository: "file:///custom/path/to/trivy-db"
  skip-update: true
```

### Multiple Database Versions

Maintain multiple database versions for testing:

```bash
trivy-databases/
├── production/
│   └── trivy-db/
├── staging/
│   └── trivy-db/
└── archive/
    ├── trivy-db-20250101/
    └── trivy-db-20250108/
```

### Monitoring Script

Create `monitor-trivy-db.sh`:

```bash
#!/bin/bash

# Check database age
DB_DATE=$(cat trivy-db/metadata.json | jq -r '.UpdatedAt')
DB_AGE=$(( ($(date +%s) - $(date -d "$DB_DATE" +%s)) / 86400 ))

if [ $DB_AGE -gt 7 ]; then
    echo "WARNING: Database is $DB_AGE days old"
    exit 1
fi

echo "Database age: $DB_AGE days - OK"
```

## Deployment Checklist

Use this checklist to ensure successful offline deployment:

### Pre-Deployment
- [ ] Internet-connected system available for updates
- [ ] Sufficient disk space (2GB minimum)
- [ ] Docker installed and running
- [ ] Required tools installed (jq, curl, tar, sha256sum)

### Database Preparation
- [ ] Downloaded latest Trivy database
- [ ] Verified database integrity
- [ ] Created deployment package
- [ ] Generated checksums
- [ ] Tested package integrity

### Offline Deployment
- [ ] Transferred package securely
- [ ] Verified package checksums
- [ ] Extracted to correct locations
- [ ] Set appropriate permissions
- [ ] Tested scanning functionality

### Post-Deployment
- [ ] Documented deployment date and version
- [ ] Scheduled next update
- [ ] Configured monitoring/alerting
- [ ] Trained users on scanning procedures

## Maintenance Scripts

### Database Age Monitor

Create `scripts/check-db-age.sh`:

```bash
#!/bin/bash
# Check Trivy database age and alert if outdated

DB_METADATA="/opt/trivy/trivy-db/metadata.json"
MAX_AGE_DAYS=7
ALERT_EMAIL="security-team@company.com"

if [ ! -f "$DB_METADATA" ]; then
    echo "ERROR: Database metadata not found"
    exit 1
fi

UPDATED_AT=$(jq -r '.UpdatedAt' "$DB_METADATA")
CURRENT_TIME=$(date +%s)
DB_TIME=$(date -d "$UPDATED_AT" +%s 2>/dev/null || echo 0)
AGE_DAYS=$(( (CURRENT_TIME - DB_TIME) / 86400 ))

echo "Database age: $AGE_DAYS days"

if [ $AGE_DAYS -gt $MAX_AGE_DAYS ]; then
    MESSAGE="WARNING: Trivy database is $AGE_DAYS days old (last updated: $UPDATED_AT)"
    echo "$MESSAGE"
    
    # Send alert if mail is configured
    if command -v mail >/dev/null; then
        echo "$MESSAGE" | mail -s "Trivy Database Alert" "$ALERT_EMAIL"
    fi
    
    exit 1
fi

echo "Database age is acceptable"
```

### Cleanup Script

Create `scripts/cleanup-cache.sh`:

```bash
#!/bin/bash
# Clean up old Trivy cache files

CACHE_DIR="/opt/trivy/trivy-cache"
BACKUP_DIR="/opt/trivy/backups"
MAX_BACKUPS=5

echo "Cleaning Trivy cache and backups..."

# Clean analysis cache (keeps database)
if [ -d "$CACHE_DIR/fanal" ]; then
    echo "Cleaning analysis cache..."
    rm -rf "$CACHE_DIR/fanal"/*
    echo "Analysis cache cleaned"
fi

# Clean old backups
if [ -d "$BACKUP_DIR" ]; then
    echo "Cleaning old backups (keeping last $MAX_BACKUPS)..."
    cd "$BACKUP_DIR"
    ls -t | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -rf
    echo "Old backups cleaned"
fi

echo "Cleanup completed"
```

## Integration Examples

### Prometheus Monitoring

```yaml
# prometheus-rules.yml
groups:
  - name: trivy-alerts
    rules:
      - alert: TrivyDatabaseOld
        expr: trivy_database_age_days > 7
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Trivy database is outdated"
          description: "Trivy vulnerability database is {{ $value }} days old"
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Trivy Offline Scanner",
    "panels": [
      {
        "title": "Database Age",
        "type": "stat",
        "targets": [
          {
            "expr": "trivy_database_age_days"
          }
        ]
      },
      {
        "title": "Scan Results",
        "type": "table",
        "targets": [
          {
            "expr": "trivy_vulnerabilities_total"
          }
        ]
      }
    ]
  }
}
```

### Ansible Playbook

```yaml
---
- name: Deploy Trivy Offline Scanner
  hosts: offline_scanners
  become: yes
  
  tasks:
    - name: Create trivy directories
      file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
      loop:
        - /opt/trivy/trivy-db
        - /opt/trivy/trivy-cache
        - /opt/trivy/backups
        
    - name: Copy database files
      copy:
        src: "{{ trivy_package_path }}"
        dest: /tmp/trivy-package.tar.gz
        
    - name: Extract trivy package
      unarchive:
        src: /tmp/trivy-package.tar.gz
        dest: /opt/trivy/
        remote_src: yes
        
    - name: Set permissions
      file:
        path: /opt/trivy
        owner: trivy
        group: trivy
        recurse: yes
```

## Troubleshooting Guide

### Performance Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Slow scanning | Large cache on slow storage | Move cache to SSD |
| High memory usage | Large images | Increase Docker memory limit |
| Scan timeouts | Network/CPU constraints | Increase timeout values |

### Database Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| "DB not found" | Missing database files | Re-run setup or restore backup |
| "DB corrupted" | Incomplete download | Download fresh database |
| "Version mismatch" | Mixed versions | Ensure consistent versions |

### Network Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Update fails | No internet access | Schedule update during maintenance |
| Slow downloads | Network limitations | Use local mirror or proxy |
| SSL errors | Certificate issues | Update certificates or use HTTP |

## Conclusion

Maintaining Trivy databases for offline use requires careful planning and regular updates. By following this guide, you can ensure your offline vulnerability scanning remains effective and current. 

### Key Success Factors

1. **Regular Updates**: Weekly database updates minimum
2. **Proper Testing**: Verify each update before deployment
3. **Backup Strategy**: Maintain rollback capability
4. **Documentation**: Keep detailed update logs
5. **Monitoring**: Alert on outdated databases
6. **Training**: Ensure team knows procedures

### Next Steps

1. Implement the update procedures for your environment
2. Set up monitoring and alerting
3. Create runbooks for common issues
4. Schedule regular reviews and updates
5. Consider automation opportunities

For additional support or questions, consult:

- **Official Trivy Documentation**: https://trivy.dev/
- **Trivy GitHub Repository**: https://github.com/aquasecurity/trivy
- **Community Support**: https://github.com/aquasecurity/trivy/discussions
- **Security Best Practices**: Your organization's security team
