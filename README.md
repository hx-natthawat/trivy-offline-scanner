# Trivy Offline Container Scanner

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Trivy](https://img.shields.io/badge/trivy-latest-brightgreen.svg)](https://github.com/aquasecurity/trivy)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://www.docker.com/)

A comprehensive solution for running [Trivy](https://trivy.dev/) container vulnerability scanner in offline (air-gapped) environments without internet access. This toolkit provides scripts, configurations, and automation for maintaining up-to-date vulnerability databases in isolated networks.

## 🚀 Quick Start

### 1. Initial Setup (Requires Internet)

Download the latest Trivy database:

```bash
# Make scripts executable
chmod +x scan-offline.sh update-trivy-offline.sh

# Download database
./scan-offline.sh setup
```

### 2. Scan Images (Offline)

```bash
# Basic scan
./scan-offline.sh scan -i nginx:latest

# Scan with severity filtering
./scan-offline.sh scan -i alpine:latest -s CRITICAL,HIGH

# Export results to JSON
./scan-offline.sh scan -i ubuntu:20.04 -f json -o scan-results/ubuntu.json
```

### 3. Regular Updates

```bash
# Update database when internet is available
./update-trivy-offline.sh

# Or use the basic update
./scan-offline.sh update-db
```

## 📦 Components

| Component | Description | Purpose |
|-----------|-------------|---------|
| `scan-offline.sh` | Main scanning script | Easy command-line scanning |
| `update-trivy-offline.sh` | Advanced update script | Comprehensive database updates |
| `trivy_offline_scanner.py` | Python wrapper | Programmatic scanning |
| `trivy-config.yaml` | Configuration file | Offline mode settings |
| `docker-compose.yml` | Docker Compose setup | Container orchestration |
| `TRIVY_OFFLINE_GUIDE.md` | Detailed guide | Comprehensive documentation |

## 🛠️ Installation & Setup

### Prerequisites

- **Docker** (20.10+)
- **Docker Compose** (optional)
- **Python 3.6+** (for Python wrapper)
- **jq** (for JSON processing)
- **curl** (for internet connectivity checks)

### System Requirements

- **Disk Space**: 2GB minimum (database ~700MB, cache grows over time)
- **Memory**: 1GB RAM minimum for scanning
- **Network**: Internet access required for initial setup and updates

### Installation Steps

1. **Clone or download this repository**

   ```bash
   git clone <repository-url>
   cd container-scanner
   ```

2. **Install Python dependencies** (optional)

   ```bash
   pip install -r requirements.txt
   ```

3. **Make scripts executable**

   ```bash
   chmod +x *.sh
   ```

4. **Initial database setup**

   ```bash
   ./scan-offline.sh setup
   ```

## 📖 Usage Guide

### Command Line Scanning

```bash
# Show all available commands
./scan-offline.sh

# List local Docker images
./scan-offline.sh list

# Basic image scan
./scan-offline.sh scan -i <image-name>

# Advanced scanning options
./scan-offline.sh scan \
  -i myapp:v1.0 \
  -f json \
  -o results/myapp-scan.json \
  -s CRITICAL,HIGH
```

### Docker Compose Usage

```bash
# Start services
docker-compose up -d

# Run scan
docker-compose run --rm trivy image nginx:latest

# Custom configuration
docker-compose run --rm trivy image --config /trivy-config.yaml myapp:latest

# Cleanup
docker-compose down
```

### Python Integration

```python
from trivy_offline_scanner import TrivyOfflineScanner

# Initialize scanner
scanner = TrivyOfflineScanner()

# Scan single image
result = scanner.scan_image("nginx:latest", format="json")
summary = scanner.get_vulnerability_summary(result)

print(f"Critical: {summary.get('CRITICAL', 0)}")
print(f"High: {summary.get('HIGH', 0)}")

# Batch scanning
images = ["alpine:latest", "ubuntu:20.04", "node:16"]
results = scanner.scan_multiple_images(
    images, 
    severity=["CRITICAL", "HIGH"]
)
```

### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-i, --image` | Container image to scan | `nginx:latest` |
| `-f, --format` | Output format | `table`, `json`, `cyclonedx`, `spdx` |
| `-o, --output` | Output file path | `results/scan.json` |
| `-s, --severity` | Severity levels | `CRITICAL,HIGH,MEDIUM` |

## 🔧 Configuration

### Trivy Configuration (`trivy-config.yaml`)

```yaml
# Scan settings
scan:
  security-checks:
    - vuln      # Vulnerability scanning
    - config    # Configuration scanning
  
  severity:
    - CRITICAL
    - HIGH
    - MEDIUM

# Report settings  
report:
  format: table
  exit-code: 1
  
# Timeout
timeout: 5m
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TRIVY_DB_REPOSITORY` | Database location | `file:///trivy-db` |
| `TRIVY_SKIP_DB_UPDATE` | Skip online updates | `true` |
| `TRIVY_CACHE_DIR` | Cache directory | `/root/.cache/trivy` |

## 📁 Directory Structure

```
container-scanner/
├── 📄 README.md                     # This file
├── 📄 TRIVY_OFFLINE_GUIDE.md        # Detailed offline guide
├── 📄 .gitignore                    # Git ignore rules
├── 🔧 trivy-config.yaml             # Trivy configuration
├── 🔧 docker-compose.yml            # Docker Compose setup
├── 📜 scan-offline.sh               # Main scanning script
├── 📜 update-trivy-offline.sh       # Database update script
├── 🐍 trivy_offline_scanner.py      # Python wrapper
├── 📋 requirements.txt              # Python dependencies
├── 📁 trivy-db/                     # Vulnerability database
│   ├── trivy.db                     # Main database file
│   └── metadata.json               # Database metadata
├── 📁 trivy-cache/                  # Cache directory
│   ├── db/                          # Database cache
│   └── fanal/                       # Analysis cache
├── 📁 scan-results/                 # Scan output files
├── 📁 backups/                      # Database backups
└── 📁 packages/                     # Deployment packages
```

## 🔄 Database Management

### Regular Updates

**For environments with periodic internet access:**

```bash
# Comprehensive update with packaging
./update-trivy-offline.sh

# Skip Docker image export (faster)
./update-trivy-offline.sh --skip-docker

# Basic update only
./scan-offline.sh update-db
```

### Offline Deployment

1. **On internet-connected system:**

   ```bash
   ./update-trivy-offline.sh
   ```

2. **Transfer package to offline system:**

   ```bash
   # Verify package integrity
   sha256sum -c trivy-offline-*.tar.gz.sha256
   
   # Extract
   tar -xzf trivy-offline-*.tar.gz
   ```

3. **Deploy on offline system:**

   ```bash
   cp -r trivy-db /opt/trivy/
   cp -r trivy-cache /opt/trivy/
   ```

### Update Schedule Recommendations

| Environment | Update Frequency | Method |
|-------------|------------------|---------|
| High Security | Weekly | Scheduled maintenance window |
| Standard | Bi-weekly | Automated when internet available |
| Development | Monthly | Manual updates |

## 📊 Output Formats

### Table Format (Default)

Human-readable vulnerability report with color coding.

### JSON Format

```bash
./scan-offline.sh scan -i nginx:latest -f json -o results.json
```

### SBOM Formats

```bash
# CycloneDX format
./scan-offline.sh scan -i myapp:latest -f cyclonedx -o sbom.xml

# SPDX format  
./scan-offline.sh scan -i myapp:latest -f spdx -o sbom.spdx
```

## 🚨 Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Database not found" | Missing database files | Run `./scan-offline.sh setup` |
| "Cannot connect to Docker" | Docker not running | Start Docker service |
| "Image not found" | Image not locally available | `docker pull <image>` |
| "Permission denied" | Script not executable | `chmod +x *.sh` |
| "Database too old" | Outdated database | Run update script |

### Debugging

```bash
# Check database status
cat trivy-db/metadata.json | jq '.'

# Verify cache structure
ls -la trivy-cache/

# Test Docker connectivity
docker images

# Check script permissions
ls -la *.sh
```

### Performance Optimization

1. **Use SSD storage** for cache directory
2. **Increase Docker memory** if scans fail
3. **Clear old cache** periodically:

   ```bash
   rm -rf trivy-cache/fanal/*
   ```

## 🔒 Security Considerations

### Database Security

- Update databases regularly (weekly recommended)
- Verify download integrity with checksums
- Store databases securely with appropriate access controls
- Monitor database age and alert when outdated

### Operational Security

- Audit all database updates
- Use dedicated systems for updates
- Encrypt database packages during transfer
- Maintain rollback capability with backups

### Access Control

```bash
# Restrict database access
chmod 750 trivy-db/
chown -R trivy:trivy trivy-db/

# Secure cache directory
chmod 755 trivy-cache/
```

## 🚀 Advanced Usage

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
- name: Scan with Trivy
  run: |
    ./scan-offline.sh scan -i ${{ matrix.image }} -f json -o scan-${{ matrix.image }}.json
    
- name: Upload results
  uses: actions/upload-artifact@v3
  with:
    name: trivy-results
    path: scan-*.json
```

### Jenkins Integration

See `jenkins/` directory for pipeline examples and setup instructions.

### Monitoring

```bash
# Database age monitoring
./monitor-trivy-db.sh

# Automated alerts
if [ $DB_AGE -gt 7 ]; then
  echo "WARNING: Database is $DB_AGE days old" | mail -s "Trivy DB Alert" admin@company.com
fi
```

## 📚 Documentation

- **[TRIVY_OFFLINE_GUIDE.md](TRIVY_OFFLINE_GUIDE.md)** - Comprehensive offline deployment guide
- **[jenkins/JENKINS_SETUP.md](jenkins/JENKINS_SETUP.md)** - Jenkins CI/CD integration
- **[Official Trivy Documentation](https://trivy.dev/)** - Trivy scanner documentation

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: Report bugs and feature requests via GitHub Issues
- **Documentation**: Check the `TRIVY_OFFLINE_GUIDE.md` for detailed instructions
- **Community**: Join the [Trivy community](https://github.com/aquasecurity/trivy/discussions)

## 🎯 Roadmap

- [ ] GUI interface for scan management
- [ ] Integration with vulnerability management platforms
- [ ] Automated compliance reporting
- [ ] Container registry integration
- [ ] Kubernetes operator for automated scanning

---

**⚠️ Security Notice**: This tool is designed for defensive security purposes only. Always ensure compliance with your organization's security policies and keep databases updated for effective vulnerability detection.
