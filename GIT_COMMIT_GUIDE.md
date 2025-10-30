# Git Commit Message Guide

This guide ensures all commits in this repository have clear, descriptive, and consistent messages.

---

## 📋 Commit Message Format

```
<type>: <short summary> (max 50 chars)

<detailed description>
- Bullet point 1
- Bullet point 2
- Bullet point 3

<optional: technical details, breaking changes, etc.>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## 🏷️ Commit Types

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat: add autovacuum monitoring tools` |
| `fix` | Bug fix | `fix: resolve dashboard widget alignment issue` |
| `docs` | Documentation only | `docs: add dashboard cleanup deployment record` |
| `refactor` | Code refactoring | `refactor: simplify alarm creation logic` |
| `perf` | Performance improvement | `perf: optimize CloudWatch query batching` |
| `test` | Add or update tests | `test: add RDS metrics validation tests` |
| `chore` | Maintenance tasks | `chore: update AWS SDK to v3.450.0` |
| `style` | Code style/formatting | `style: format Python scripts with black` |
| `ci` | CI/CD changes | `ci: add GitHub Actions workflow` |

---

## ✅ Good Commit Message Principles

### 1. **Be Specific in the Title**

❌ **Bad** (Too generic):
```
docs: add comprehensive CloudWatch dashboard deployment record
docs: add comprehensive CloudWatch dashboard deployment record  ← Duplicate!
```

✅ **Good** (Specific and unique):
```
docs: add Stress and Release RDS monitoring deployment
docs: add dashboard cleanup and autovacuum monitoring tools
```

### 2. **Use Action Verbs**

❌ **Bad**:
```
docs: CloudWatch dashboard documentation
feat: autovacuum tools
```

✅ **Good**:
```
docs: add CloudWatch dashboard deployment record
feat: create autovacuum monitoring tools
```

### 3. **Keep Title Under 50 Characters**

❌ **Bad** (72 chars):
```
docs: add comprehensive documentation for CloudWatch dashboard deployment
```

✅ **Good** (48 chars):
```
docs: add CloudWatch dashboard deployment guide
```

### 4. **Separate Title and Body with Blank Line**

❌ **Bad**:
```
docs: add deployment record
This commit adds deployment documentation for...
```

✅ **Good**:
```
docs: add deployment record

This commit adds deployment documentation for...
```

### 5. **Use Imperative Mood**

❌ **Bad**:
```
docs: added deployment record
docs: adding deployment record
```

✅ **Good**:
```
docs: add deployment record
```

---

## 📝 Detailed Description Guidelines

### Structure

```
<What was done>

Key changes:
- Change 1
- Change 2
- Change 3

Technical details:
- Technical aspect 1
- Technical aspect 2

<Optional: Impact, metrics, or notes>
```

### Example: Feature Commit

```
feat: create autovacuum monitoring toolset

Add comprehensive PostgreSQL autovacuum query tools:
- Python script for detailed analysis (12+ metrics)
- Bash script for quick checks
- SQL query reference guide

Key features:
- Real-time VACUUM progress tracking
- Dead tuple percentage analysis with risk levels
- Alert thresholds (10%, 30%, 50%)
- Support for 10 RDS instances across 3 environments

Technical details:
- Uses psycopg2 for database connections
- Queries pg_stat_all_tables and pg_stat_progress_vacuum
- Compatible with PostgreSQL 14.15

Impact: Enables proactive database health monitoring without
additional CloudWatch costs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Example: Documentation Commit

```
docs: add dashboard cleanup deployment record

Document CloudWatch dashboard cleanup deployment:
- Removed 9 invalid Performance Insights widgets
- Cleaned Production, Release, and Stress dashboards
- Added rollback procedures and backup locations

Key improvements:
- Eliminated "No data available" confusion
- Reduced widget count from 128 to 119
- Saved ~$1.35/month in CloudWatch costs

Files:
- DEPLOYMENT_RECORD.md (624 lines)
- Scripts: cleanup_invalid_widgets.py

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Example: Bug Fix Commit

```
fix: correct EBSIOBalance% alarm threshold

Fix incorrect alarm threshold for EBSIOBalance%:
- Changed from P2 < 50% to P2 < 70%
- Changed from P1 < 30% to P1 < 50%

Reason: Previous thresholds were too aggressive and caused
false positives during normal burst consumption.

Affected instances:
- bingo-prd (5 instances)
- bingo-stress (3 instances)
- pgsqlrel (2 instances)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## 🚫 Common Mistakes to Avoid

### 1. **Duplicate Titles**

❌ **Avoid**:
```
commit 1: docs: add CloudWatch deployment record
commit 2: docs: add CloudWatch deployment record  ← Same title!
```

✅ **Better**:
```
commit 1: docs: add Stress/Release RDS monitoring record
commit 2: docs: add dashboard cleanup and tools record
```

### 2. **Vague Descriptions**

❌ **Avoid**:
```
docs: update files
feat: add stuff
fix: fix bug
```

✅ **Better**:
```
docs: add autovacuum monitoring guide
feat: create Python script for RDS analysis
fix: resolve widget alignment in Stress dashboard
```

### 3. **Missing Context**

❌ **Avoid**:
```
docs: add record

Added deployment record.
```

✅ **Better**:
```
docs: add dashboard cleanup deployment record

Document removal of 9 invalid Performance Insights widgets
from Production, Release, and Stress RDS dashboards.

Impact: Eliminates "No data available" warnings.
```

### 4. **Too Much Detail in Title**

❌ **Avoid**:
```
docs: add comprehensive deployment record documenting dashboard cleanup and autovacuum tools
```

✅ **Better**:
```
docs: add dashboard cleanup and autovacuum tools

<Details in body>
```

### 5. **No Separation Between Commits**

When making multiple related changes, ensure each commit has a **distinct purpose**:

❌ **Avoid**:
```
commit 1: docs: update documentation
commit 2: docs: update documentation  ← Not helpful!
```

✅ **Better**:
```
commit 1: docs: add deployment procedures
commit 2: docs: add troubleshooting guide
commit 3: docs: add rollback instructions
```

---

## 📊 Commit Message Checklist

Before committing, verify:

- [ ] **Title is specific** and describes what changed
- [ ] **Title is unique** (not duplicate of recent commits)
- [ ] **Title uses imperative mood** (add, fix, update, not added/adding)
- [ ] **Title is under 50 characters**
- [ ] **Blank line** separates title from body
- [ ] **Body explains WHY** (not just what)
- [ ] **Body includes key changes** as bullet points
- [ ] **Technical details** are documented if relevant
- [ ] **Impact or metrics** included when significant
- [ ] **Co-authored tag** included

---

## 🎯 Real Examples from This Repository

### Good Examples

✅ **Specific and clear**:
```
feat: add Stress environment RDS monitoring without SNS notifications
```

✅ **Descriptive with context**:
```
docs: add dashboard cleanup and autovacuum monitoring tools

Add DEPLOYMENT_RECORD.md documenting:
- Dashboard cleanup: removed 9 invalid Performance Insights widgets
- Autovacuum monitoring tools: 3 query methods (Python, Bash, SQL)
...
```

✅ **Clear scope**:
```
feat: comprehensive RDS CloudWatch alarm optimization for all Bingo instances
```

### Improved Examples

❌ **Before** (too similar):
```
commit 1: docs: add comprehensive CloudWatch dashboard deployment record
commit 2: docs: add comprehensive CloudWatch dashboard deployment record
```

✅ **After** (specific and unique):
```
commit 1: docs: add Stress and Release RDS monitoring deployment
commit 2: docs: add dashboard cleanup and autovacuum tools
```

---

## 🔧 Git Amend (When You Need to Fix)

If you need to fix a commit message after committing but **before others pull**:

```bash
# Amend the last commit message
git commit --amend -m "New commit message"

# Force push (⚠️ only if not yet pulled by others)
git push --force origin main
```

⚠️ **Warning**: Only use `--force` if you're certain no one else has pulled the commit.

---

## 📚 Additional Resources

- [Conventional Commits](https://www.conventionalcommits.org/)
- [How to Write a Git Commit Message](https://chris.beams.io/posts/git-commit/)
- [Angular Commit Guidelines](https://github.com/angular/angular/blob/master/CONTRIBUTING.md#commit)

---

## 🎓 Quick Reference

### Template for Copy-Paste

```
<type>: <short summary (max 50 chars)>

<What was done - 1-2 sentences>

Key changes:
- Change 1
- Change 2
- Change 3

Technical details:
- Detail 1
- Detail 2

Impact: <Business or technical impact>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Title Formula

```
<type>: <action verb> <what> [optional: for/in <where>]

Examples:
- feat: add autovacuum tools for RDS monitoring
- docs: update deployment guide for Production
- fix: resolve widget alignment in Stress dashboard
- refactor: simplify alarm creation logic
```

---

**Last Updated**: 2025-10-30
**Maintained By**: DevOps Team

---

## 💡 Key Takeaway

> **Every commit should tell a clear story of WHAT changed and WHY.**
>
> Future you (or your teammates) should understand the purpose and impact
> of the change just by reading the commit message.

---
