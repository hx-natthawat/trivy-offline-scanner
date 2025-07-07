# Trivy Offline Scanner - Deployment Package Instructions

## Package Created Successfully

**Package file**: `trivy-offline-scanner-20250702_115253.tar.gz` (132MB)

This package includes:

- ✅ All scanner scripts and tools
- ✅ Trivy vulnerability database (66MB)
- ✅ Configuration files
- ✅ Installation scripts
- ✅ Documentation

## Deployment Instructions

### Step 1: Transfer Package to Target Server

Choose one of these methods:

```bash
# Option A: Using SCP
scp trivy-offline-scanner-20250702_115253.tar.gz user@server:/opt/

# Option B: Using rsync
rsync -avz trivy-offline-scanner-20250702_115253.tar.gz user@server:/opt/

# Option C: Using USB drive
cp trivy-offline-scanner-20250702_115253.tar.gz /media/usb/
```

### Step 2: On the Target Server

```bash
# 1. Extract the package
cd /opt
tar -xzf trivy-offline-scanner-20250702_115253.tar.gz

# 2. Enter directory
cd trivy-offline-scanner-20250702_115253

# 3. Run installer
./install-offline.sh

# 4. Test the installation
./scan-offline.sh list
```

### Step 3: Load Docker Image (if needed)

If the target server doesn't have the Trivy Docker image:

**On a machine with internet:**

```bash
# Save the Docker image
docker pull aquasec/trivy:latest
docker save aquasec/trivy:latest -o trivy-docker-image.tar

# Transfer to target server along with the package
```

**On the target server:**

```bash
# Load the Docker image
docker load -i trivy-docker-image.tar
```

## Quick Usage on Target Server

```bash
# List available Docker images
./scan-offline.sh list

# Scan an image
./scan-offline.sh scan -i nginx:latest

# Scan with JSON output
./scan-offline.sh scan -i redis:alpine -f json -o results.json

# Scan only CRITICAL vulnerabilities
./scan-offline.sh scan -i postgres:latest -s CRITICAL
```

## Creating Package with Docker Image

If you want to include the Docker image in the package (adds ~168MB):

```bash
./package-for-deployment.sh --with-docker-image
```

## Prerequisites on Target Server

- Docker installed and running
- Bash shell
- Root or sudo access (for Docker commands)
- At least 500MB free disk space

## Updating the Database

When you have internet access:

1. Update the database:

   ```bash
   ./scan-offline.sh update-db
   ```

2. Create a new package:

   ```bash
   ./package-for-deployment.sh
   ```

3. Deploy the new package to offline servers

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Permission denied | Run `chmod +x *.sh` on all scripts |
| Docker not found | Install Docker on target server |
| Cannot connect to Docker | Ensure user is in docker group or use sudo |
| Database not found | Check trivy-db directory exists |
| Image scan fails | Ensure Docker image exists locally |

## Security Recommendations

1. **Update database monthly** - Vulnerabilities are discovered daily
2. **Scan before production** - Always scan images before deployment
3. **Fix CRITICAL/HIGH** - Prioritize fixing severe vulnerabilities
4. **Use specific tags** - Avoid using 'latest' tag in production
5. **Regular rescans** - Rescan images periodically

## Support Files Included

- `README.md` - Full documentation
- `DEPLOYMENT.md` - Deployment-specific guide
- `requirements.txt` - Python dependencies
- `trivy-config.yaml` - Trivy configuration

The scanner is now ready for deployment to offline environments!
