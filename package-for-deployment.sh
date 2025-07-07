#!/bin/bash

# Package Trivy Offline Scanner for Deployment
# This script creates a deployment package with all necessary components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NAME="trivy-offline-scanner"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_DIR="${SCRIPT_DIR}/${PACKAGE_NAME}-${TIMESTAMP}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Creating deployment package for Trivy Offline Scanner...${NC}"

# Create package directory
mkdir -p "${PACKAGE_DIR}"

# Copy all necessary files
echo "Copying scanner files..."
cp "${SCRIPT_DIR}/scan-offline.sh" "${PACKAGE_DIR}/"
cp "${SCRIPT_DIR}/trivy_offline_scanner.py" "${PACKAGE_DIR}/"
cp "${SCRIPT_DIR}/docker-compose.yml" "${PACKAGE_DIR}/"
cp "${SCRIPT_DIR}/trivy-config.yaml" "${PACKAGE_DIR}/"
cp "${SCRIPT_DIR}/requirements.txt" "${PACKAGE_DIR}/"
cp "${SCRIPT_DIR}/README.md" "${PACKAGE_DIR}/"

# Copy database if exists
if [ -d "${SCRIPT_DIR}/trivy-db" ] && [ -f "${SCRIPT_DIR}/trivy-db/trivy.db" ]; then
    echo "Copying Trivy database..."
    mkdir -p "${PACKAGE_DIR}/trivy-db"
    cp -r "${SCRIPT_DIR}/trivy-db/"* "${PACKAGE_DIR}/trivy-db/"
    echo -e "${GREEN}Database included in package${NC}"
else
    echo -e "${YELLOW}Warning: No database found. Run './scan-offline.sh setup' first to include database${NC}"
fi

# Copy cache if exists
if [ -d "${SCRIPT_DIR}/trivy-cache" ]; then
    echo "Copying cache directory..."
    mkdir -p "${PACKAGE_DIR}/trivy-cache"
    cp -r "${SCRIPT_DIR}/trivy-cache/"* "${PACKAGE_DIR}/trivy-cache/" 2>/dev/null || true
fi

# Create empty directories
mkdir -p "${PACKAGE_DIR}/scan-results"

# Create offline installer script
cat > "${PACKAGE_DIR}/install-offline.sh" << 'EOF'
#!/bin/bash

# Offline Installation Script for Trivy Scanner
set -e

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Installing Trivy Offline Scanner...${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo "Please install Docker before running this installer"
    exit 1
fi

# Make scripts executable
chmod +x "${INSTALL_DIR}/scan-offline.sh"
chmod +x "${INSTALL_DIR}/trivy_offline_scanner.py"

# Pull Trivy image if not exists
if ! docker images | grep -q "aquasec/trivy"; then
    echo -e "${YELLOW}Trivy image not found locally${NC}"
    echo "Please load the Docker image from trivy-image.tar if available:"
    echo "  docker load -i trivy-image.tar"
    echo ""
    echo "Or pull it when you have internet:"
    echo "  docker pull aquasec/trivy:latest"
else
    echo -e "${GREEN}Trivy image found${NC}"
fi

# Check database
if [ -f "${INSTALL_DIR}/trivy-db/trivy.db" ]; then
    echo -e "${GREEN}Database found and ready${NC}"
else
    echo -e "${YELLOW}Database not found${NC}"
    echo "Run './scan-offline.sh setup' when you have internet to download the database"
fi

# Create Python virtual environment (optional)
if command -v python3 &> /dev/null; then
    echo ""
    echo "To use the Python wrapper, create a virtual environment:"
    echo "  python3 -m venv venv"
    echo "  source venv/bin/activate"
    echo "  pip install -r requirements.txt"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Quick start:"
echo "  ./scan-offline.sh list              # List Docker images"
echo "  ./scan-offline.sh scan -i <image>   # Scan an image"
echo ""
echo "See README.md for full documentation"
EOF

chmod +x "${PACKAGE_DIR}/install-offline.sh"

# Create deployment README
cat > "${PACKAGE_DIR}/DEPLOYMENT.md" << 'EOF'
# Trivy Offline Scanner - Deployment Guide

## Package Contents

- `scan-offline.sh` - Main shell script for scanning
- `trivy_offline_scanner.py` - Python wrapper (optional)
- `docker-compose.yml` - Docker Compose configuration
- `trivy-config.yaml` - Trivy configuration
- `requirements.txt` - Python dependencies
- `trivy-db/` - Offline database (if included)
- `install-offline.sh` - Installation script

## Deployment Steps

### 1. Transfer Package

Transfer the entire package directory to your target server:

```bash
# Using SCP
scp -r trivy-offline-scanner-* user@server:/path/to/destination/

# Using USB/Physical media
cp -r trivy-offline-scanner-* /media/usb/
```

### 2. Extract and Install

On the target server:

```bash
cd /path/to/destination/trivy-offline-scanner-*
./install-offline.sh
```

### 3. Load Docker Image (if needed)

If the target server has no internet and no Trivy image:

```bash
# On a machine with internet:
docker pull aquasec/trivy:latest
docker save aquasec/trivy:latest -o trivy-image.tar

# Transfer trivy-image.tar to target server, then:
docker load -i trivy-image.tar
```

### 4. Verify Installation

```bash
# List available images
./scan-offline.sh list

# Test scan
./scan-offline.sh scan -i <existing-image>
```

## Prerequisites on Target Server

- Docker installed and running
- Bash shell
- (Optional) Python 3.6+ for Python wrapper

## Database Updates

To update the database when internet is available:

```bash
./scan-offline.sh update-db
```

Then repackage and redeploy to offline servers.

## Troubleshooting

1. **Permission denied**: Run `chmod +x *.sh` on all shell scripts
2. **Docker not found**: Ensure Docker is installed and daemon is running
3. **Database not found**: Check trivy-db directory contains trivy.db file
4. **Image not found**: Docker pull or load the image first

## Security Notes

- Keep the database updated regularly
- Scan images before deploying to production
- Review all HIGH and CRITICAL vulnerabilities
EOF

# Save Docker image if requested
if [ "$1" == "--with-docker-image" ]; then
    echo "Saving Docker image..."
    if docker images | grep -q "aquasec/trivy"; then
        docker save aquasec/trivy:latest -o "${PACKAGE_DIR}/trivy-image.tar"
        echo -e "${GREEN}Docker image saved${NC}"
    else
        echo -e "${YELLOW}Trivy image not found locally${NC}"
    fi
fi

# Create tarball
echo "Creating tarball..."
cd "${SCRIPT_DIR}"
tar -czf "${PACKAGE_NAME}-${TIMESTAMP}.tar.gz" "${PACKAGE_NAME}-${TIMESTAMP}/"

# Calculate package size
PACKAGE_SIZE=$(du -sh "${PACKAGE_NAME}-${TIMESTAMP}.tar.gz" | cut -f1)

# Cleanup directory
rm -rf "${PACKAGE_DIR}"

echo ""
echo -e "${GREEN}✓ Package created successfully!${NC}"
echo "  File: ${PACKAGE_NAME}-${TIMESTAMP}.tar.gz"
echo "  Size: ${PACKAGE_SIZE}"
echo ""
echo "Options:"
echo "  --with-docker-image    Include Docker image in package"
echo ""
echo "To deploy:"
echo "  1. Transfer ${PACKAGE_NAME}-${TIMESTAMP}.tar.gz to target server"
echo "  2. Extract: tar -xzf ${PACKAGE_NAME}-${TIMESTAMP}.tar.gz"
echo "  3. Run: cd ${PACKAGE_NAME}-${TIMESTAMP} && ./install-offline.sh"