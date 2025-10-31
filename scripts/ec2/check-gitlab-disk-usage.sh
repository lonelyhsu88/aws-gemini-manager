#!/bin/bash
# Check GitLab disk usage and identify potential cleanup targets
# This script should be run ON the GitLab EC2 instance

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "GitLab Disk Usage & Cleanup Analysis"
echo "=========================================="
date
echo ""

# Check if running as root or with sudo access
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠️  This script requires sudo access. Some checks may fail.${NC}"
    echo "Run with: sudo $0"
    echo ""
fi

# Overall disk usage
echo -e "${CYAN}=== OVERALL DISK USAGE ===${NC}"
df -h | grep -E "Filesystem|/$|/dev"
echo ""

# GitLab data directories
echo -e "${CYAN}=== GITLAB DATA DIRECTORIES SIZE ===${NC}"

GITLAB_DIRS=(
    "/var/opt/gitlab/git-data"
    "/var/opt/gitlab/gitlab-rails/shared"
    "/var/opt/gitlab/gitlab-rails/uploads"
    "/var/opt/gitlab/gitlab-ci/builds"
    "/var/opt/gitlab/backups"
    "/var/opt/gitlab/postgresql"
    "/var/opt/gitlab/redis"
    "/var/opt/gitlab/gitlab-rails/shared/artifacts"
    "/var/opt/gitlab/gitlab-rails/shared/lfs-objects"
    "/var/opt/gitlab/gitlab-rails/shared/packages"
    "/var/opt/gitlab/gitlab-rails/shared/terraform_state"
    "/var/opt/gitlab/gitlab-rails/shared/registry"
)

for dir in "${GITLAB_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "  📁 $dir: $size"
    fi
done
echo ""

# Git repositories
echo -e "${CYAN}=== GIT REPOSITORIES ===${NC}"
if [ -d "/var/opt/gitlab/git-data/repositories" ]; then
    REPOS_SIZE=$(du -sh /var/opt/gitlab/git-data/repositories 2>/dev/null | cut -f1)
    REPOS_COUNT=$(find /var/opt/gitlab/git-data/repositories -name "*.git" -type d 2>/dev/null | wc -l)
    echo "  📦 Total size: $REPOS_SIZE"
    echo "  📊 Repository count: $REPOS_COUNT"

    # Largest repositories
    echo ""
    echo "  Top 10 largest repositories:"
    du -sh /var/opt/gitlab/git-data/repositories/*/*.git 2>/dev/null | sort -rh | head -n 10 | while read line; do
        echo "    $line"
    done
else
    echo "  ⚠️  Git data directory not found"
fi
echo ""

# CI/CD Artifacts
echo -e "${CYAN}=== CI/CD ARTIFACTS ===${NC}"
if [ -d "/var/opt/gitlab/gitlab-rails/shared/artifacts" ]; then
    ARTIFACTS_SIZE=$(du -sh /var/opt/gitlab/gitlab-rails/shared/artifacts 2>/dev/null | cut -f1)
    ARTIFACTS_COUNT=$(find /var/opt/gitlab/gitlab-rails/shared/artifacts -type f 2>/dev/null | wc -l)
    echo "  📦 Total size: $ARTIFACTS_SIZE"
    echo "  📊 File count: $ARTIFACTS_COUNT"

    # Old artifacts (older than 30 days)
    OLD_ARTIFACTS=$(find /var/opt/gitlab/gitlab-rails/shared/artifacts -type f -mtime +30 2>/dev/null | wc -l)
    if [ $OLD_ARTIFACTS -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  Old artifacts (>30 days): $OLD_ARTIFACTS files${NC}"
    fi
else
    echo "  ℹ️  No artifacts directory found"
fi
echo ""

# LFS Objects
echo -e "${CYAN}=== GIT LFS OBJECTS ===${NC}"
if [ -d "/var/opt/gitlab/gitlab-rails/shared/lfs-objects" ]; then
    LFS_SIZE=$(du -sh /var/opt/gitlab/gitlab-rails/shared/lfs-objects 2>/dev/null | cut -f1)
    LFS_COUNT=$(find /var/opt/gitlab/gitlab-rails/shared/lfs-objects -type f 2>/dev/null | wc -l)
    echo "  📦 Total size: $LFS_SIZE"
    echo "  📊 File count: $LFS_COUNT"
else
    echo "  ℹ️  No LFS objects found"
fi
echo ""

# Container Registry
echo -e "${CYAN}=== CONTAINER REGISTRY ===${NC}"
if [ -d "/var/opt/gitlab/gitlab-rails/shared/registry" ]; then
    REGISTRY_SIZE=$(du -sh /var/opt/gitlab/gitlab-rails/shared/registry 2>/dev/null | cut -f1)
    echo "  📦 Total size: $REGISTRY_SIZE"
else
    echo "  ℹ️  Container Registry not found"
fi
echo ""

# Backups
echo -e "${CYAN}=== BACKUPS ===${NC}"
if [ -d "/var/opt/gitlab/backups" ]; then
    BACKUP_SIZE=$(du -sh /var/opt/gitlab/backups 2>/dev/null | cut -f1)
    BACKUP_COUNT=$(ls -1 /var/opt/gitlab/backups/*.tar 2>/dev/null | wc -l)
    echo "  📦 Total size: $BACKUP_SIZE"
    echo "  📊 Backup count: $BACKUP_COUNT"

    if [ $BACKUP_COUNT -gt 0 ]; then
        echo ""
        echo "  Backup files:"
        ls -lh /var/opt/gitlab/backups/*.tar 2>/dev/null | tail -n 10
    fi
else
    echo "  ℹ️  No backups directory found"
fi
echo ""

# PostgreSQL
echo -e "${CYAN}=== POSTGRESQL DATABASE ===${NC}"
if [ -d "/var/opt/gitlab/postgresql" ]; then
    PG_SIZE=$(du -sh /var/opt/gitlab/postgresql 2>/dev/null | cut -f1)
    echo "  📦 Total size: $PG_SIZE"

    # Get database sizes
    if command -v gitlab-psql &> /dev/null; then
        echo ""
        echo "  Database sizes:"
        sudo gitlab-psql -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;" 2>/dev/null || echo "    Unable to query database"
    fi
else
    echo "  ⚠️  PostgreSQL directory not found"
fi
echo ""

# Redis
echo -e "${CYAN}=== REDIS ===${NC}"
if [ -d "/var/opt/gitlab/redis" ]; then
    REDIS_SIZE=$(du -sh /var/opt/gitlab/redis 2>/dev/null | cut -f1)
    echo "  📦 Total size: $REDIS_SIZE"

    # Redis memory usage
    if command -v gitlab-redis-cli &> /dev/null; then
        echo ""
        echo "  Redis info:"
        sudo gitlab-redis-cli INFO memory 2>/dev/null | grep -E "used_memory_human|used_memory_rss_human|maxmemory_human" || echo "    Unable to query Redis"
    fi
else
    echo "  ⚠️  Redis directory not found"
fi
echo ""

# Logs
echo -e "${CYAN}=== LOG FILES ===${NC}"
if [ -d "/var/log/gitlab" ]; then
    LOGS_SIZE=$(du -sh /var/log/gitlab 2>/dev/null | cut -f1)
    echo "  📦 Total size: $LOGS_SIZE"

    echo ""
    echo "  Largest log files:"
    find /var/log/gitlab -type f -exec du -sh {} \; 2>/dev/null | sort -rh | head -n 10

    # Old logs
    OLD_LOGS=$(find /var/log/gitlab -type f -name "*.log.*" -mtime +30 2>/dev/null | wc -l)
    if [ $OLD_LOGS -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  Old log files (>30 days): $OLD_LOGS files${NC}"
    fi
else
    echo "  ⚠️  Log directory not found"
fi
echo ""

# Temp files
echo -e "${CYAN}=== TEMPORARY FILES ===${NC}"
TEMP_DIRS=(
    "/var/opt/gitlab/gitlab-rails/tmp"
    "/tmp"
)

for dir in "${TEMP_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        temp_size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "  📁 $dir: $temp_size"
    fi
done
echo ""

# Summary and recommendations
echo "=========================================="
echo -e "${CYAN}CLEANUP RECOMMENDATIONS${NC}"
echo "=========================================="
echo ""

echo -e "${GREEN}✅ Safe cleanup commands (can be run anytime):${NC}"
echo ""
echo "1. Clean old CI/CD artifacts (older than default expiration):"
echo "   sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files"
echo ""
echo "2. Clean orphaned LFS files:"
echo "   sudo gitlab-rake gitlab:cleanup:orphan_lfs_file_references"
echo ""
echo "3. Clean old project exports:"
echo "   sudo gitlab-rake gitlab:cleanup:project_exports"
echo ""
echo "4. Clean Redis cache:"
echo "   sudo gitlab-redis-cli FLUSHALL"
echo ""
echo "5. Rotate and compress logs:"
echo "   sudo logrotate -f /etc/logrotate.d/gitlab"
echo ""
echo "6. Clean package manager cache:"
echo "   sudo yum clean all  # or: sudo apt-get clean"
echo ""
echo "7. Remove old backup files (keep last 3):"
echo "   cd /var/opt/gitlab/backups && ls -t | tail -n +4 | xargs -I {} sudo rm -f {}"
echo ""

echo -e "${YELLOW}⚠️  Requires maintenance window:${NC}"
echo ""
echo "1. Garbage collect all repositories (can take hours):"
echo "   sudo gitlab-rake gitlab:git:gc"
echo ""
echo "2. Repack all repositories:"
echo "   sudo gitlab-rake gitlab:git:repack"
echo ""
echo "3. Clean up unreferenced objects:"
echo "   sudo gitlab-rake gitlab:git:prune"
echo ""
echo "4. Database vacuum (PostgreSQL):"
echo "   sudo gitlab-rake gitlab:db:vacuum"
echo ""

echo -e "${RED}❗ Requires careful planning:${NC}"
echo ""
echo "1. Set default artifact expiration (in /etc/gitlab/gitlab.rb):"
echo "   gitlab_rails['artifacts_expire_at'] = '30 days'"
echo ""
echo "2. Clean up old Container Registry images:"
echo "   Review and delete old images via UI or API"
echo ""
echo "3. Archive or remove unused projects"
echo ""

echo "=========================================="
echo -e "${CYAN}IMMEDIATE ACTIONS TO FREE SPACE${NC}"
echo "=========================================="
echo ""
echo "Quick cleanup script (safe to run):"
echo ""
cat << 'CLEANUP_EOF'
#!/bin/bash
# Quick GitLab cleanup

echo "Starting cleanup..."

# Clean orphaned artifacts
echo "1. Cleaning orphaned job artifacts..."
sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false

# Clean orphaned LFS
echo "2. Cleaning orphaned LFS files..."
sudo gitlab-rake gitlab:cleanup:orphan_lfs_file_references

# Clean project exports
echo "3. Cleaning old project exports..."
sudo gitlab-rake gitlab:cleanup:project_exports

# Rotate logs
echo "4. Rotating logs..."
sudo logrotate -f /etc/logrotate.d/gitlab

# Clean package cache
echo "5. Cleaning package cache..."
sudo yum clean all 2>/dev/null || sudo apt-get clean 2>/dev/null

echo ""
echo "Cleanup completed!"
echo "Check disk usage: df -h"
CLEANUP_EOF

echo ""
echo "Save the above script and run it to perform quick cleanup."
