#!/bin/bash

# Trivy Offline Scanner - Disk Cleanup Script
# This script helps manage disk space by cleaning various components safely

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="${SCRIPT_DIR}/trivy-db"
CACHE_DIR="${SCRIPT_DIR}/trivy-cache"
RESULTS_DIR="${SCRIPT_DIR}/scan-results"
BACKUP_DIR="${SCRIPT_DIR}/backups"
PACKAGES_DIR="${SCRIPT_DIR}/packages"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Get directory size in human readable format
get_size() {
    local dir=$1
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

# Count files in directory
count_files() {
    local dir=$1
    if [ -d "$dir" ]; then
        find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Display usage information
usage() {
    echo "Trivy Disk Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --cache         Clean analysis cache (keeps database)"
    echo "  --results       Clean old scan results"
    echo "  --backups       Clean old backups (keeps last 3)"
    echo "  --packages      Clean deployment packages"
    echo "  --logs          Clean log files"
    echo "  --temp          Clean temporary files"
    echo "  --docker        Clean Docker build cache and unused images"
    echo "  --all           Clean everything (except database and last 3 backups)"
    echo "  --deep-clean    WARNING: Complete cleanup including database"
    echo "  --dry-run       Show what would be cleaned without actually doing it"
    echo "  --status        Show disk usage status"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --status                    # Show current disk usage"
    echo "  $0 --cache --results           # Clean cache and results"
    echo "  $0 --dry-run --all             # Show what --all would clean"
    echo "  $0 --backups                   # Clean old backups"
    echo ""
    echo "Safety Notes:"
    echo "  - Database is never touched unless --deep-clean is used"
    echo "  - Last 3 backups are always preserved"
    echo "  - Use --dry-run to preview changes"
}

# Show current disk usage status
show_status() {
    print_status "$BLUE" "=== Trivy Disk Usage Status ==="
    echo ""
    
    printf "%-20s %-10s %-10s %s\n" "Component" "Size" "Files" "Location"
    printf "%-20s %-10s %-10s %s\n" "─────────" "────" "─────" "────────"
    
    # Database
    if [ -d "$DB_DIR" ]; then
        printf "%-20s %-10s %-10s %s\n" "Database" "$(get_size "$DB_DIR")" "$(count_files "$DB_DIR")" "$DB_DIR"
    fi
    
    # Cache
    if [ -d "$CACHE_DIR" ]; then
        printf "%-20s %-10s %-10s %s\n" "Cache" "$(get_size "$CACHE_DIR")" "$(count_files "$CACHE_DIR")" "$CACHE_DIR"
        
        # Cache subdirectories
        if [ -d "$CACHE_DIR/db" ]; then
            printf "%-20s %-10s %-10s %s\n" "  └─ Database" "$(get_size "$CACHE_DIR/db")" "$(count_files "$CACHE_DIR/db")" "$CACHE_DIR/db"
        fi
        if [ -d "$CACHE_DIR/fanal" ]; then
            printf "%-20s %-10s %-10s %s\n" "  └─ Analysis" "$(get_size "$CACHE_DIR/fanal")" "$(count_files "$CACHE_DIR/fanal")" "$CACHE_DIR/fanal"
        fi
        if [ -d "$CACHE_DIR/java-db" ]; then
            printf "%-20s %-10s %-10s %s\n" "  └─ Java DB" "$(get_size "$CACHE_DIR/java-db")" "$(count_files "$CACHE_DIR/java-db")" "$CACHE_DIR/java-db"
        fi
    fi
    
    # Results
    if [ -d "$RESULTS_DIR" ]; then
        printf "%-20s %-10s %-10s %s\n" "Scan Results" "$(get_size "$RESULTS_DIR")" "$(count_files "$RESULTS_DIR")" "$RESULTS_DIR"
    fi
    
    # Backups
    if [ -d "$BACKUP_DIR" ]; then
        printf "%-20s %-10s %-10s %s\n" "Backups" "$(get_size "$BACKUP_DIR")" "$(count_files "$BACKUP_DIR")" "$BACKUP_DIR"
    fi
    
    # Packages
    if [ -d "$PACKAGES_DIR" ]; then
        printf "%-20s %-10s %-10s %s\n" "Packages" "$(get_size "$PACKAGES_DIR")" "$(count_files "$PACKAGES_DIR")" "$PACKAGES_DIR"
    fi
    
    # Log files
    local log_files=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$log_files" -gt 0 ]; then
        local log_size=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.log" -type f -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        printf "%-20s %-10s %-10s %s\n" "Log Files" "$log_size" "$log_files" "$SCRIPT_DIR/*.log"
    fi
    
    echo ""
    printf "%-20s %-10s\n" "Total Directory" "$(get_size "$SCRIPT_DIR")"
    
    # Docker images (if Docker is available)
    if command -v docker >/dev/null 2>&1; then
        echo ""
        print_status "$BLUE" "Docker Usage:"
        if docker system df >/dev/null 2>&1; then
            docker system df
        else
            echo "Docker not running or not accessible"
        fi
    fi
}

# Clean analysis cache (preserves database)
clean_cache() {
    local action="Cleaning"
    [ "$DRY_RUN" = true ] && action="Would clean"
    
    if [ -d "$CACHE_DIR/fanal" ]; then
        local size=$(get_size "$CACHE_DIR/fanal")
        local files=$(count_files "$CACHE_DIR/fanal")
        print_status "$YELLOW" "$action analysis cache: $size ($files files)"
        
        if [ "$DRY_RUN" != true ]; then
            rm -rf "$CACHE_DIR/fanal"/*
            print_status "$GREEN" "✓ Analysis cache cleaned"
        fi
    else
        print_status "$BLUE" "No analysis cache to clean"
    fi
}

# Clean scan results
clean_results() {
    local action="Cleaning"
    [ "$DRY_RUN" = true ] && action="Would clean"
    
    if [ -d "$RESULTS_DIR" ] && [ "$(ls -A "$RESULTS_DIR" 2>/dev/null)" ]; then
        local size=$(get_size "$RESULTS_DIR")
        local files=$(count_files "$RESULTS_DIR")
        print_status "$YELLOW" "$action scan results: $size ($files files)"
        
        if [ "$DRY_RUN" != true ]; then
            rm -rf "$RESULTS_DIR"/*
            print_status "$GREEN" "✓ Scan results cleaned"
        fi
    else
        print_status "$BLUE" "No scan results to clean"
    fi
}

# Clean old backups (keep last 3)
clean_backups() {
    local action="Cleaning"
    [ "$DRY_RUN" = true ] && action="Would clean"
    
    if [ -d "$BACKUP_DIR" ]; then
        local total_backups=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$total_backups" -gt 3 ]; then
            local to_remove=$((total_backups - 3))
            print_status "$YELLOW" "$action old backups (keeping last 3, removing $to_remove)"
            
            if [ "$DRY_RUN" = true ]; then
                cd "$BACKUP_DIR"
                ls -t | tail -n +4 | while read backup; do
                    echo "  Would remove: $backup ($(get_size "$backup"))"
                done
                cd - > /dev/null
            else
                cd "$BACKUP_DIR"
                ls -t | tail -n +4 | xargs -r rm -rf
                cd - > /dev/null
                print_status "$GREEN" "✓ Old backups cleaned (kept last 3)"
            fi
        else
            print_status "$BLUE" "No old backups to clean (have $total_backups, keeping all)"
        fi
    else
        print_status "$BLUE" "No backup directory found"
    fi
}

# Clean deployment packages
clean_packages() {
    local action="Cleaning"
    [ "$DRY_RUN" = true ] && action="Would clean"
    
    if [ -d "$PACKAGES_DIR" ] && [ "$(ls -A "$PACKAGES_DIR" 2>/dev/null)" ]; then
        local size=$(get_size "$PACKAGES_DIR")
        local files=$(count_files "$PACKAGES_DIR")
        print_status "$YELLOW" "$action deployment packages: $size ($files files)"
        
        if [ "$DRY_RUN" != true ]; then
            rm -rf "$PACKAGES_DIR"/*
            print_status "$GREEN" "✓ Deployment packages cleaned"
        fi
    else
        print_status "$BLUE" "No deployment packages to clean"
    fi
}

# Clean log files
clean_logs() {
    local action="Cleaning"
    [ "$DRY_RUN" = true ] && action="Would clean"
    
    local log_files=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.log" -type f 2>/dev/null)
    
    if [ -n "$log_files" ]; then
        local count=$(echo "$log_files" | wc -l | tr -d ' ')
        local total_size=$(echo "$log_files" | xargs du -ch 2>/dev/null | tail -1 | cut -f1)
        print_status "$YELLOW" "$action log files: $total_size ($count files)"
        
        if [ "$DRY_RUN" = true ]; then
            echo "$log_files" | while read logfile; do
                echo "  Would remove: $(basename "$logfile") ($(get_size "$logfile"))"
            done
        else
            echo "$log_files" | xargs rm -f
            print_status "$GREEN" "✓ Log files cleaned"
        fi
    else
        print_status "$BLUE" "No log files to clean"
    fi
}

# Clean temporary files
clean_temp() {
    local action="Cleaning"
    [ "$DRY_RUN" = true ] && action="Would clean"
    
    local temp_files=""
    local temp_dirs=""
    
    # Find temporary files and directories
    temp_files=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*.tmp" -o -name "*.temp" -o -name ".tmp*" \) -type f 2>/dev/null || true)
    temp_dirs=$(find "$SCRIPT_DIR" -maxdepth 1 \( -name "temp" -o -name "tmp" -o -name ".temp*" \) -type d 2>/dev/null || true)
    
    local total_items=""
    [ -n "$temp_files" ] && total_items="$temp_files"
    [ -n "$temp_dirs" ] && total_items="$total_items $temp_dirs"
    
    if [ -n "$total_items" ]; then
        local count=$(echo "$total_items" | wc -w | tr -d ' ')
        print_status "$YELLOW" "$action temporary files: $count items"
        
        if [ "$DRY_RUN" = true ]; then
            [ -n "$temp_files" ] && echo "$temp_files" | while read tmpfile; do
                echo "  Would remove file: $(basename "$tmpfile")"
            done
            [ -n "$temp_dirs" ] && echo "$temp_dirs" | while read tmpdir; do
                echo "  Would remove dir: $(basename "$tmpdir") ($(get_size "$tmpdir"))"
            done
        else
            [ -n "$temp_files" ] && echo "$temp_files" | xargs rm -f
            [ -n "$temp_dirs" ] && echo "$temp_dirs" | xargs rm -rf
            print_status "$GREEN" "✓ Temporary files cleaned"
        fi
    else
        print_status "$BLUE" "No temporary files to clean"
    fi
}

# Clean Docker cache and unused images
clean_docker() {
    local action="Cleaning"
    [ "$DRY_RUN" = true ] && action="Would clean"
    
    if ! command -v docker >/dev/null 2>&1; then
        print_status "$BLUE" "Docker not available, skipping Docker cleanup"
        return
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_status "$BLUE" "Docker not running, skipping Docker cleanup"
        return
    fi
    
    print_status "$YELLOW" "$action Docker cache and unused images..."
    
    if [ "$DRY_RUN" = true ]; then
        echo "Would run: docker system prune -f"
        echo "Would run: docker image prune -f"
        # Show what would be cleaned
        docker system df
    else
        # Clean build cache
        docker system prune -f >/dev/null 2>&1 || true
        # Clean unused images (not referenced by any container)
        docker image prune -f >/dev/null 2>&1 || true
        print_status "$GREEN" "✓ Docker cache cleaned"
    fi
}

# Deep clean (WARNING: removes everything including database)
deep_clean() {
    print_status "$RED" "WARNING: Deep clean will remove EVERYTHING including the database!"
    print_status "$RED" "This will require re-downloading the database (~700MB) before scanning again."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$YELLOW" "Would perform deep clean:"
        echo "  - Remove entire database directory ($DB_DIR)"
        echo "  - Remove entire cache directory ($CACHE_DIR)"
        echo "  - Remove all scan results ($RESULTS_DIR)"
        echo "  - Remove all backups ($BACKUP_DIR)"
        echo "  - Remove all packages ($PACKAGES_DIR)"
        echo "  - Remove all log files"
        echo "  - Remove all temporary files"
        return
    fi
    
    echo -n "Are you sure you want to proceed? Type 'YES' to confirm: "
    read confirmation
    
    if [ "$confirmation" != "YES" ]; then
        print_status "$BLUE" "Deep clean cancelled"
        return
    fi
    
    print_status "$RED" "Performing deep clean..."
    
    # Remove everything
    [ -d "$DB_DIR" ] && rm -rf "$DB_DIR"
    [ -d "$CACHE_DIR" ] && rm -rf "$CACHE_DIR"
    [ -d "$RESULTS_DIR" ] && rm -rf "$RESULTS_DIR"
    [ -d "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"
    [ -d "$PACKAGES_DIR" ] && rm -rf "$PACKAGES_DIR"
    
    # Clean logs and temp files
    find "$SCRIPT_DIR" -maxdepth 1 -name "*.log" -type f -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -maxdepth 1 \( -name "*.tmp" -o -name "*.temp" -o -name ".tmp*" \) -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -maxdepth 1 \( -name "temp" -o -name "tmp" -o -name ".temp*" \) -type d -exec rm -rf {} + 2>/dev/null || true
    
    print_status "$GREEN" "✓ Deep clean completed"
    print_status "$YELLOW" "Remember to run './scan-offline.sh setup' to re-download the database"
}

# Main execution
main() {
    local DRY_RUN=false
    local CLEAN_CACHE=false
    local CLEAN_RESULTS=false
    local CLEAN_BACKUPS=false
    local CLEAN_PACKAGES=false
    local CLEAN_LOGS=false
    local CLEAN_TEMP=false
    local CLEAN_DOCKER=false
    local CLEAN_ALL=false
    local DEEP_CLEAN=false
    local SHOW_STATUS=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cache)
                CLEAN_CACHE=true
                shift
                ;;
            --results)
                CLEAN_RESULTS=true
                shift
                ;;
            --backups)
                CLEAN_BACKUPS=true
                shift
                ;;
            --packages)
                CLEAN_PACKAGES=true
                shift
                ;;
            --logs)
                CLEAN_LOGS=true
                shift
                ;;
            --temp)
                CLEAN_TEMP=true
                shift
                ;;
            --docker)
                CLEAN_DOCKER=true
                shift
                ;;
            --all)
                CLEAN_ALL=true
                shift
                ;;
            --deep-clean)
                DEEP_CLEAN=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Show status if requested
    if [ "$SHOW_STATUS" = true ]; then
        show_status
        exit 0
    fi
    
    # If no action specified, show help
    if [ "$CLEAN_CACHE" = false ] && [ "$CLEAN_RESULTS" = false ] && [ "$CLEAN_BACKUPS" = false ] && \
       [ "$CLEAN_PACKAGES" = false ] && [ "$CLEAN_LOGS" = false ] && [ "$CLEAN_TEMP" = false ] && \
       [ "$CLEAN_DOCKER" = false ] && [ "$CLEAN_ALL" = false ] && [ "$DEEP_CLEAN" = false ]; then
        show_status
        exit 0
    fi
    
    print_status "$BLUE" "=== Trivy Disk Cleanup ==="
    [ "$DRY_RUN" = true ] && print_status "$YELLOW" "DRY RUN MODE - No changes will be made"
    echo ""
    
    # Handle deep clean
    if [ "$DEEP_CLEAN" = true ]; then
        deep_clean
        echo ""
        show_status
        exit 0
    fi
    
    # Handle --all option
    if [ "$CLEAN_ALL" = true ]; then
        CLEAN_CACHE=true
        CLEAN_RESULTS=true
        CLEAN_BACKUPS=true
        CLEAN_PACKAGES=true
        CLEAN_LOGS=true
        CLEAN_TEMP=true
        CLEAN_DOCKER=true
    fi
    
    # Execute cleanup actions
    [ "$CLEAN_CACHE" = true ] && clean_cache
    [ "$CLEAN_RESULTS" = true ] && clean_results
    [ "$CLEAN_BACKUPS" = true ] && clean_backups
    [ "$CLEAN_PACKAGES" = true ] && clean_packages
    [ "$CLEAN_LOGS" = true ] && clean_logs
    [ "$CLEAN_TEMP" = true ] && clean_temp
    [ "$CLEAN_DOCKER" = true ] && clean_docker
    
    echo ""
    if [ "$DRY_RUN" != true ]; then
        print_status "$GREEN" "Cleanup completed!"
        echo ""
        print_status "$BLUE" "Updated disk usage:"
        show_status
    else
        print_status "$BLUE" "Dry run completed. Use without --dry-run to perform actual cleanup."
    fi
}

# Run main function with all arguments
main "$@"