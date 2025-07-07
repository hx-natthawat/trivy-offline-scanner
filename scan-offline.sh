#!/bin/bash

# Offline Trivy Scanner Script
# This script manages the local Trivy database and performs container scanning

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="${SCRIPT_DIR}/trivy-db"
CACHE_DIR="${SCRIPT_DIR}/trivy-cache"
RESULTS_DIR="${SCRIPT_DIR}/scan-results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create necessary directories
mkdir -p "${DB_DIR}" "${CACHE_DIR}" "${RESULTS_DIR}"

# Function to display usage
usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  setup       Download and setup the Trivy database for offline use"
    echo "  scan        Scan a container image (requires image name)"
    echo "  update-db   Update the local database (requires internet)"
    echo "  list        List all available images on the system"
    echo ""
    echo "Options for 'scan' command:"
    echo "  -i, --image IMAGE    Container image to scan"
    echo "  -f, --format FORMAT  Output format (table, json, cyclonedx, spdx) [default: table]"
    echo "  -o, --output FILE    Output file path"
    echo "  -s, --severity LEVEL Severity levels to include (CRITICAL,HIGH,MEDIUM,LOW)"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 scan -i nginx:latest"
    echo "  $0 scan -i myapp:v1.0 -f json -o results.json"
    echo "  $0 scan -i alpine:3.14 -s CRITICAL,HIGH"
    exit 1
}

# Function to setup the database
setup_database() {
    echo -e "${GREEN}Setting up Trivy database for offline use...${NC}"
    
    # Create a temporary directory for initial download
    TEMP_CACHE="${SCRIPT_DIR}/temp-cache"
    mkdir -p "${TEMP_CACHE}"
    
    # Use Trivy to download the database
    echo "Downloading Trivy database..."
    docker run --rm \
        -v "${TEMP_CACHE}:/root/.cache/trivy" \
        -v "${DB_DIR}:/output" \
        aquasec/trivy:latest \
        image --download-db-only
    
    # Copy the database to our local directory
    echo "Copying database files..."
    if [ -d "${TEMP_CACHE}/db" ]; then
        cp -r "${TEMP_CACHE}/db"/* "${DB_DIR}/" 2>/dev/null || true
    fi
    
    # Clean up temp cache
    rm -rf "${TEMP_CACHE}"
    
    echo -e "${GREEN}Database setup complete!${NC}"
    echo "Database location: ${DB_DIR}"
}

# Function to update the database
update_database() {
    echo -e "${YELLOW}Updating Trivy database (requires internet)...${NC}"
    
    # Pull the latest trivy-db image
    docker pull aquasec/trivy-db:latest
    
    # Remove old database
    rm -rf "${DB_DIR}"/*
    
    # Extract new database
    docker run --rm -v "${DB_DIR}:/output" aquasec/trivy-db:latest sh -c "cp -r /trivy-db/* /output/"
    
    echo -e "${GREEN}Database update complete!${NC}"
}

# Function to scan an image
scan_image() {
    local IMAGE=""
    local FORMAT="table"
    local OUTPUT=""
    local SEVERITY=""
    
    # Parse scan options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--image)
                IMAGE="$2"
                shift 2
                ;;
            -f|--format)
                FORMAT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT="$2"
                shift 2
                ;;
            -s|--severity)
                SEVERITY="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
        esac
    done
    
    # Validate image parameter
    if [ -z "$IMAGE" ]; then
        echo -e "${RED}Error: Image name is required${NC}"
        usage
    fi
    
    # Check if database exists
    if [ ! -d "${DB_DIR}" ] || [ -z "$(ls -A ${DB_DIR})" ]; then
        echo -e "${RED}Error: Trivy database not found. Please run '$0 setup' first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Scanning image: ${IMAGE}${NC}"
    
    # Copy DB to cache directory structure if needed
    if [ -f "${DB_DIR}/trivy.db" ] && [ ! -f "${CACHE_DIR}/db/trivy.db" ]; then
        mkdir -p "${CACHE_DIR}/db"
        cp "${DB_DIR}/trivy.db" "${CACHE_DIR}/db/"
        cp "${DB_DIR}/metadata.json" "${CACHE_DIR}/db/"
    fi
    
    # Build docker run command
    DOCKER_CMD="docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v ${CACHE_DIR}:/root/.cache/trivy \
        -v ${RESULTS_DIR}:/results \
        -e TRIVY_CACHE_DIR=/root/.cache/trivy \
        -e TRIVY_SKIP_DB_UPDATE=true \
        -e TRIVY_SKIP_JAVA_DB_UPDATE=true \
        aquasec/trivy:latest \
        image"
    
    # Add format option
    DOCKER_CMD="${DOCKER_CMD} --format ${FORMAT}"
    
    # Add severity filter if specified
    if [ -n "$SEVERITY" ]; then
        DOCKER_CMD="${DOCKER_CMD} --severity ${SEVERITY}"
    fi
    
    # Add output file if specified
    if [ -n "$OUTPUT" ]; then
        OUTPUT_PATH="/results/$(basename ${OUTPUT})"
        DOCKER_CMD="${DOCKER_CMD} --output ${OUTPUT_PATH}"
        echo "Results will be saved to: ${RESULTS_DIR}/$(basename ${OUTPUT})"
    fi
    
    # Add image name
    DOCKER_CMD="${DOCKER_CMD} ${IMAGE}"
    
    # Execute scan
    eval ${DOCKER_CMD}
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Scan completed successfully!${NC}"
        if [ -n "$OUTPUT" ]; then
            echo "Results saved to: ${RESULTS_DIR}/$(basename ${OUTPUT})"
        fi
    else
        echo -e "${RED}Scan failed!${NC}"
        exit 1
    fi
}

# Function to list available images
list_images() {
    echo -e "${GREEN}Available Docker images:${NC}"
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"
}

# Main script logic
case "$1" in
    setup)
        setup_database
        ;;
    scan)
        shift
        scan_image "$@"
        ;;
    update-db)
        update_database
        ;;
    list)
        list_images
        ;;
    *)
        usage
        ;;
esac