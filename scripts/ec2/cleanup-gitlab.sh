#!/bin/bash
# GitLab Quick Cleanup Script
# Run this ON the GitLab EC2 instance to free up disk space and memory

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run with sudo${NC}"
    echo "Usage: sudo $0 [--dry-run]"
    exit 1
fi

# Parse arguments
DRY_RUN="false"
if [ "$1" = "--dry-run" ]; then
    DRY_RUN="true"
    echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

echo "=========================================="
echo "GitLab Cleanup Script"
echo "=========================================="
date
echo ""

# Show disk usage before
echo -e "${BLUE}📊 Disk usage BEFORE cleanup:${NC}"
df -h / | grep -v "Filesystem"
echo ""

FREE_BEFORE=$(df / | tail -1 | awk '{print $4}')

# Function to show progress
show_progress() {
    echo -e "${GREEN}▶ $1${NC}"
}

# Function to show completion
show_done() {
    echo -e "${GREEN}  ✅ Done${NC}"
    echo ""
}

# 1. Clean orphaned job artifacts
show_progress "1. Cleaning orphaned job artifacts..."
if [ "$DRY_RUN" = "true" ]; then
    gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=true
else
    gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false
fi
show_done

# 2. Clean orphaned LFS files
show_progress "2. Cleaning orphaned LFS files..."
if [ "$DRY_RUN" = "true" ]; then
    echo "  (Would clean orphaned LFS files)"
else
    gitlab-rake gitlab:cleanup:orphan_lfs_file_references
fi
show_done

# 3. Clean old project exports
show_progress "3. Cleaning old project exports..."
if [ "$DRY_RUN" = "true" ]; then
    echo "  (Would clean project exports)"
else
    gitlab-rake gitlab:cleanup:project_exports
fi
show_done

# 4. Clean remote upload files
show_progress "4. Cleaning remote upload files..."
if [ "$DRY_RUN" = "true" ]; then
    echo "  (Would clean remote upload files)"
else
    gitlab-rake gitlab:cleanup:remote_upload_files || echo "  ⚠️  Skipped (may not be applicable)"
fi
show_done

# 5. Rotate logs
show_progress "5. Rotating and compressing logs..."
if [ "$DRY_RUN" = "true" ]; then
    echo "  (Would rotate logs)"
else
    logrotate -f /etc/logrotate.d/gitlab 2>/dev/null || echo "  ⚠️  Log rotation config not found"
fi
show_done

# 6. Clean package manager cache
show_progress "6. Cleaning package manager cache..."
if [ "$DRY_RUN" = "true" ]; then
    echo "  (Would clean package cache)"
else
    yum clean all 2>/dev/null || apt-get clean 2>/dev/null || echo "  ⚠️  Package manager cleanup not available"
fi
show_done

# 7. Clean old backup files (keep last 3)
show_progress "7. Cleaning old backup files (keeping last 3)..."
BACKUP_DIR="/var/opt/gitlab/backups"
if [ -d "$BACKUP_DIR" ]; then
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.tar 2>/dev/null | wc -l)
    if [ $BACKUP_COUNT -gt 3 ]; then
        echo "  Found $BACKUP_COUNT backups"
        if [ "$DRY_RUN" = "true" ]; then
            echo "  Would remove: $(expr $BACKUP_COUNT - 3) old backups"
            ls -t "$BACKUP_DIR"/*.tar | tail -n +4
        else
            cd "$BACKUP_DIR" && ls -t *.tar | tail -n +4 | xargs -I {} rm -f {}
            echo "  Removed $(expr $BACKUP_COUNT - 3) old backups"
        fi
    else
        echo "  Only $BACKUP_COUNT backups found, skipping"
    fi
else
    echo "  No backup directory found"
fi
show_done

# 8. Clean temporary files
show_progress "8. Cleaning temporary files..."
TEMP_DIR="/var/opt/gitlab/gitlab-rails/tmp"
if [ -d "$TEMP_DIR" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        echo "  (Would clean temp files)"
    else
        find "$TEMP_DIR" -type f -mtime +7 -delete 2>/dev/null || true
        echo "  Cleaned temp files older than 7 days"
    fi
else
    echo "  Temp directory not found"
fi
show_done

# 9. Restart GitLab to free memory
show_progress "9. Restarting GitLab services to free memory..."
if [ "$DRY_RUN" = "true" ]; then
    echo "  (Would restart GitLab services)"
else
    read -p "  Restart GitLab now? This will cause brief downtime. (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        gitlab-ctl restart
        echo "  GitLab services restarted"
    else
        echo "  Skipped GitLab restart"
    fi
fi
show_done

# Show disk usage after
echo "=========================================="
echo -e "${BLUE}📊 Disk usage AFTER cleanup:${NC}"
df -h / | grep -v "Filesystem"

FREE_AFTER=$(df / | tail -1 | awk '{print $4}')
FREED=$(expr $FREE_AFTER - $FREE_BEFORE)

if [ $FREED -gt 0 ]; then
    FREED_GB=$(echo "scale=2; $FREED / 1024 / 1024" | bc)
    echo ""
    echo -e "${GREEN}✅ Freed approximately ${FREED_GB} GB${NC}"
elif [ "$DRY_RUN" = "true" ]; then
    echo ""
    echo -e "${YELLOW}ℹ️  Dry run completed - no changes made${NC}"
else
    echo ""
    echo "ℹ️  No significant space freed (cleanup may have already been recent)"
fi

echo ""
echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="
echo ""
echo "Completed tasks:"
echo "  ✅ Cleaned orphaned job artifacts"
echo "  ✅ Cleaned orphaned LFS files"
echo "  ✅ Cleaned project exports"
echo "  ✅ Rotated logs"
echo "  ✅ Cleaned package cache"
echo "  ✅ Cleaned old backups"
echo "  ✅ Cleaned temporary files"
echo ""

if [ "$DRY_RUN" = "false" ]; then
    echo "Next steps:"
    echo "  1. Monitor disk usage: df -h"
    echo "  2. Monitor memory: free -h"
    echo "  3. Check GitLab status: gitlab-ctl status"
    echo ""
    echo "For deeper cleanup (requires maintenance window):"
    echo "  • Repository garbage collection: gitlab-rake gitlab:git:gc"
    echo "  • Database vacuum: gitlab-rake gitlab:db:vacuum"
fi

echo ""
echo "=========================================="
date
echo "Cleanup completed!"
echo "=========================================="
