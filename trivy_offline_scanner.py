#!/usr/bin/env python3
"""
Trivy Offline Scanner - Python wrapper for offline container scanning
"""

import os
import json
import subprocess
import argparse
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Union
import docker


class TrivyOfflineScanner:
    def __init__(self, db_path: str = None, cache_path: str = None):
        """
        Initialize the Trivy offline scanner.
        
        Args:
            db_path: Path to the Trivy database directory
            cache_path: Path to the Trivy cache directory
        """
        self.base_dir = Path(__file__).parent
        self.db_path = Path(db_path) if db_path else self.base_dir / "trivy-db"
        self.cache_path = Path(cache_path) if cache_path else self.base_dir / "trivy-cache"
        self.results_dir = self.base_dir / "scan-results"
        
        # Create directories if they don't exist
        self.db_path.mkdir(parents=True, exist_ok=True)
        self.cache_path.mkdir(parents=True, exist_ok=True)
        self.results_dir.mkdir(parents=True, exist_ok=True)
        
        # Setup logging
        self.logger = logging.getLogger(__name__)
        
        # Docker client
        try:
            self.docker_client = docker.from_env()
        except Exception as e:
            self.logger.warning(f"Docker client initialization failed: {e}")
            self.docker_client = None
    
    def setup_database(self) -> bool:
        """
        Download and setup the Trivy database for offline use.
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            self.logger.info("Setting up Trivy database for offline use...")
            
            # Pull the trivy-db image
            self.logger.info("Pulling trivy-db image...")
            subprocess.run(
                ["docker", "pull", "aquasec/trivy-db:latest"],
                check=True,
                capture_output=True
            )
            
            # Extract database from the image
            self.logger.info("Extracting database files...")
            subprocess.run([
                "docker", "run", "--rm",
                "-v", f"{self.db_path}:/output",
                "aquasec/trivy-db:latest",
                "sh", "-c", "cp -r /trivy-db/* /output/"
            ], check=True, capture_output=True)
            
            self.logger.info("Database setup complete!")
            return True
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to setup database: {e}")
            return False
    
    def update_database(self) -> bool:
        """
        Update the local Trivy database (requires internet connection).
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            self.logger.info("Updating Trivy database...")
            
            # Pull the latest image
            subprocess.run(
                ["docker", "pull", "aquasec/trivy-db:latest"],
                check=True,
                capture_output=True
            )
            
            # Clear old database
            if self.db_path.exists():
                import shutil
                shutil.rmtree(self.db_path)
                self.db_path.mkdir(parents=True, exist_ok=True)
            
            # Extract new database
            return self.setup_database()
            
        except Exception as e:
            self.logger.error(f"Failed to update database: {e}")
            return False
    
    def scan_image(
        self,
        image: str,
        format: str = "json",
        severity: Optional[List[str]] = None,
        output_file: Optional[str] = None,
        vuln_type: Optional[List[str]] = None
    ) -> Union[Dict, str, None]:
        """
        Scan a container image using the offline database.
        
        Args:
            image: Container image to scan (e.g., 'nginx:latest')
            format: Output format ('json', 'table', 'cyclonedx', 'spdx')
            severity: List of severity levels to include (e.g., ['CRITICAL', 'HIGH'])
            output_file: Optional file to save results
            vuln_type: Types of vulnerabilities to scan (e.g., ['os', 'library'])
        
        Returns:
            Scan results as dict (if format is json), string (if table), or None on error
        """
        # Check if database exists
        if not self.db_path.exists() or not any(self.db_path.iterdir()):
            self.logger.error("Trivy database not found. Please run setup_database() first.")
            return None
        
        try:
            # Build docker command
            cmd = [
                "docker", "run", "--rm",
                "-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
                "-v", f"{self.cache_path}:/root/.cache/trivy",
                "-v", f"{self.db_path}:/trivy-db:ro",
                "-e", "TRIVY_CACHE_DIR=/root/.cache/trivy",
                "-e", "TRIVY_DB_REPOSITORY=file:///trivy-db",
                "-e", "TRIVY_SKIP_UPDATE=true",
                "aquasec/trivy:latest",
                "image",
                "--format", format
            ]
            
            # Add severity filter
            if severity:
                cmd.extend(["--severity", ",".join(severity)])
            
            # Add vulnerability type filter
            if vuln_type:
                cmd.extend(["--vuln-type", ",".join(vuln_type)])
            
            # Add image name
            cmd.append(image)
            
            # Execute scan
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                self.logger.error(f"Scan failed: {result.stderr}")
                return None
            
            # Save output if requested
            if output_file:
                output_path = self.results_dir / output_file
                with open(output_path, 'w') as f:
                    f.write(result.stdout)
                self.logger.info(f"Results saved to: {output_path}")
            
            # Parse and return results
            if format == "json":
                return json.loads(result.stdout)
            else:
                return result.stdout
                
        except Exception as e:
            self.logger.error(f"Scan failed: {e}")
            return None
    
    def scan_multiple_images(
        self,
        images: List[str],
        format: str = "json",
        severity: Optional[List[str]] = None
    ) -> Dict[str, Union[Dict, str, None]]:
        """
        Scan multiple container images.
        
        Args:
            images: List of container images to scan
            format: Output format
            severity: Severity levels to include
        
        Returns:
            Dictionary mapping image names to scan results
        """
        results = {}
        
        for image in images:
            self.logger.info(f"Scanning {image}...")
            result = self.scan_image(image, format=format, severity=severity)
            results[image] = result
            
        return results
    
    def get_vulnerability_summary(self, scan_results: Dict) -> Dict:
        """
        Generate a summary of vulnerabilities from scan results.
        
        Args:
            scan_results: JSON scan results from scan_image()
        
        Returns:
            Summary dictionary with vulnerability counts by severity
        """
        summary = {
            "CRITICAL": 0,
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "UNKNOWN": 0,
            "total": 0
        }
        
        if not scan_results or "Results" not in scan_results:
            return summary
        
        for result in scan_results["Results"]:
            if "Vulnerabilities" in result and result["Vulnerabilities"]:
                for vuln in result["Vulnerabilities"]:
                    severity = vuln.get("Severity", "UNKNOWN")
                    summary[severity] = summary.get(severity, 0) + 1
                    summary["total"] += 1
        
        return summary
    
    def list_local_images(self) -> List[Dict]:
        """
        List all Docker images available locally.
        
        Returns:
            List of image dictionaries
        """
        if not self.docker_client:
            self.logger.error("Docker client not available")
            return []
        
        try:
            images = self.docker_client.images.list()
            image_list = []
            
            for image in images:
                tags = image.tags if image.tags else ["<none>"]
                for tag in tags:
                    image_list.append({
                        "id": image.id[:12],
                        "tag": tag,
                        "size": image.attrs["Size"],
                        "created": image.attrs["Created"]
                    })
            
            return image_list
            
        except Exception as e:
            self.logger.error(f"Failed to list images: {e}")
            return []


def main():
    """Command line interface for the scanner."""
    parser = argparse.ArgumentParser(description="Trivy Offline Scanner")
    subparsers = parser.add_subparsers(dest="command", help="Commands")
    
    # Setup command
    setup_parser = subparsers.add_parser("setup", help="Setup offline database")
    
    # Update command
    update_parser = subparsers.add_parser("update", help="Update offline database")
    
    # Scan command
    scan_parser = subparsers.add_parser("scan", help="Scan container image")
    scan_parser.add_argument("image", help="Container image to scan")
    scan_parser.add_argument("-f", "--format", default="table", 
                           choices=["table", "json", "cyclonedx", "spdx"],
                           help="Output format")
    scan_parser.add_argument("-s", "--severity", nargs="+",
                           choices=["CRITICAL", "HIGH", "MEDIUM", "LOW"],
                           help="Severity levels to include")
    scan_parser.add_argument("-o", "--output", help="Output file")
    
    # List command
    list_parser = subparsers.add_parser("list", help="List local images")
    
    # Parse arguments
    args = parser.parse_args()
    
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Initialize scanner
    scanner = TrivyOfflineScanner()
    
    # Execute command
    if args.command == "setup":
        scanner.setup_database()
    
    elif args.command == "update":
        scanner.update_database()
    
    elif args.command == "scan":
        result = scanner.scan_image(
            args.image,
            format=args.format,
            severity=args.severity,
            output_file=args.output
        )
        
        if args.format == "json" and result:
            summary = scanner.get_vulnerability_summary(result)
            print(f"\nVulnerability Summary for {args.image}:")
            print(f"  CRITICAL: {summary['CRITICAL']}")
            print(f"  HIGH:     {summary['HIGH']}")
            print(f"  MEDIUM:   {summary['MEDIUM']}")
            print(f"  LOW:      {summary['LOW']}")
            print(f"  TOTAL:    {summary['total']}")
        elif args.format == "table" and result:
            print(result)
    
    elif args.command == "list":
        images = scanner.list_local_images()
        print("\nLocal Docker Images:")
        print(f"{'IMAGE':50} {'ID':15} {'SIZE':10}")
        print("-" * 80)
        for img in images:
            size_mb = img['size'] / (1024 * 1024)
            print(f"{img['tag']:50} {img['id']:15} {size_mb:.1f} MB")
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()