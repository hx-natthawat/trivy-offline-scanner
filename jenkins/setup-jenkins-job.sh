#!/bin/bash

# Setup script for creating Jenkins job for Trivy scanner
# This script helps automate the Jenkins job creation process

set -e

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN}"
JOB_NAME="container-security-scan"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Environment variables:"
    echo "  JENKINS_URL    Jenkins URL (default: http://localhost:8080)"
    echo "  JENKINS_USER   Jenkins username (default: admin)"
    echo "  JENKINS_TOKEN  Jenkins API token (required)"
    echo ""
    echo "Options:"
    echo "  --job-name NAME    Job name (default: container-security-scan)"
    echo "  --help            Show this help"
    echo ""
    echo "Example:"
    echo "  JENKINS_TOKEN=your-token $0 --job-name trivy-scanner"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --job-name)
            JOB_NAME="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate requirements
if [ -z "$JENKINS_TOKEN" ]; then
    echo -e "${RED}Error: JENKINS_TOKEN environment variable is required${NC}"
    echo "Get your token from Jenkins: User menu -> Configure -> API Token"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq not found. Install jq for better JSON handling${NC}"
fi

echo -e "${GREEN}Setting up Jenkins job for Trivy scanner...${NC}"
echo "Jenkins URL: $JENKINS_URL"
echo "Job Name: $JOB_NAME"

# Test Jenkins connection
echo "Testing Jenkins connection..."
if ! curl -s -f -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/api/json" > /dev/null; then
    echo -e "${RED}Error: Cannot connect to Jenkins or invalid credentials${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Jenkins connection successful${NC}"

# Check if job already exists
if curl -s -f -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/job/$JOB_NAME/api/json" > /dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Job '$JOB_NAME' already exists${NC}"
    read -p "Do you want to update it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 0
    fi
    
    # Update existing job
    echo "Updating existing job..."
    curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" \
        -X POST \
        -H "Content-Type: application/xml" \
        --data-binary @job-config.xml \
        "$JENKINS_URL/job/$JOB_NAME/config.xml"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Job updated successfully${NC}"
    else
        echo -e "${RED}Error: Failed to update job${NC}"
        exit 1
    fi
else
    # Create new job
    echo "Creating new job..."
    curl -s -u "$JENKINS_USER:$JENKINS_TOKEN" \
        -X POST \
        -H "Content-Type: application/xml" \
        --data-binary @job-config.xml \
        "$JENKINS_URL/createItem?name=$JOB_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Job created successfully${NC}"
    else
        echo -e "${RED}Error: Failed to create job${NC}"
        exit 1
    fi
fi

# Verify job was created/updated
if curl -s -f -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/job/$JOB_NAME/api/json" > /dev/null; then
    echo -e "${GREEN}✓ Job verification successful${NC}"
    echo ""
    echo "Job URL: $JENKINS_URL/job/$JOB_NAME"
    echo ""
    echo "Next steps:"
    echo "1. Configure any additional job settings in Jenkins UI"
    echo "2. Test the job with a sample Docker image"
    echo "3. Set up notifications (email, Slack, etc.)"
    echo "4. Create additional jobs using the example Jenkinsfiles"
else
    echo -e "${RED}Error: Job verification failed${NC}"
    exit 1
fi