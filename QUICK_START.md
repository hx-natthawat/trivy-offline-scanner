# Trivy Offline Scanner - Quick Start Guide

This guide will get you scanning containers for vulnerabilities in under 5 minutes!

## 🚀 Prerequisites

Make sure you have:
- Docker installed and running
- Internet access (for initial setup only)
- 2GB free disk space

## 📥 Step 1: Setup

1. **Download the scripts**
   ```bash
   chmod +x scan-offline.sh update-trivy-offline.sh
   ```

2. **Download vulnerability database** (requires internet)
   ```bash
   ./scan-offline.sh setup
   ```
   
   This downloads ~700MB of vulnerability data. Wait for completion.

## 🔍 Step 2: Your First Scan

Scan any Docker image on your system:

```bash
# Scan Alpine Linux (small, fast test)
./scan-offline.sh scan -i alpine:latest

# Scan a specific image with high/critical only
./scan-offline.sh scan -i nginx:latest -s CRITICAL,HIGH

# Save results to file
./scan-offline.sh scan -i ubuntu:20.04 -f json -o my-scan.json
```

## 📊 Understanding Results

### Table Output (Default)
```
Target: nginx:latest (debian 12.8)
┌─────────────┬──────────────┬──────────┬────────┬──────────────┬───────────────┬──────────────────┐
│   Library   │ Vulnerability │ Severity │ Status │   Version    │ Fixed Version │      Title       │
├─────────────┼──────────────┼──────────┼────────┼──────────────┼───────────────┼──────────────────┤
│ libssl3     │ CVE-2024-1234│   HIGH   │ fixed  │ 3.0.11-1     │ 3.0.13-1      │ OpenSSL issue... │
└─────────────┴──────────────┴──────────┴────────┴──────────────┴───────────────┴──────────────────┘
```

### Priority Levels
- 🔴 **CRITICAL**: Fix immediately
- 🟠 **HIGH**: Fix within days
- 🟡 **MEDIUM**: Fix within weeks
- 🔵 **LOW**: Fix when convenient
- ⚪ **UNKNOWN**: Review manually

## 🛠️ Common Commands

```bash
# List all available Docker images
./scan-offline.sh list

# Scan with different output formats
./scan-offline.sh scan -i myapp:v1.0 -f json        # JSON output
./scan-offline.sh scan -i myapp:v1.0 -f cyclonedx   # SBOM format

# Filter by severity
./scan-offline.sh scan -i myapp:v1.0 -s CRITICAL,HIGH,MEDIUM

# Scan and save results
./scan-offline.sh scan -i myapp:v1.0 -o scan-results/myapp.json
```

## 🔄 Keeping Updated

Update your vulnerability database weekly:

```bash
# Quick update (requires internet)
./scan-offline.sh update-db

# Comprehensive update with packaging
./update-trivy-offline.sh
```

## ❗ Troubleshooting

| Problem | Solution |
|---------|----------|
| "Database not found" | Run `./scan-offline.sh setup` |
| "Docker daemon not running" | Start Docker service |
| "Image not found" | Pull image: `docker pull <image>` |
| "Permission denied" | Make executable: `chmod +x *.sh` |

## 📁 File Locations

After setup, you'll have:
```
container-scanner/
├── scan-offline.sh          # Main scanner script
├── trivy-db/               # Vulnerability database (~700MB)
├── trivy-cache/            # Cache files (grows over time)
└── scan-results/           # Your scan outputs
```

## 🎯 Next Steps

1. **Automate scanning**: Add to your CI/CD pipeline
2. **Set up monitoring**: Alert when database gets old
3. **Read the full guide**: Check `TRIVY_OFFLINE_GUIDE.md` for advanced usage
4. **Integrate with tools**: Use JSON output with security platforms

## 💡 Pro Tips

- **Faster scans**: Keep cache on SSD storage
- **Batch scanning**: Use Python wrapper for multiple images
- **CI Integration**: Export results in JSON for automation
- **Regular updates**: Set up weekly database updates
- **Storage management**: Clean cache periodically

---

**Need help?** Check the full [README.md](README.md) or [detailed guide](TRIVY_OFFLINE_GUIDE.md)