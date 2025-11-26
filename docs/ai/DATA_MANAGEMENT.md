# Data Management Guide

How diagnostic data is stored, archived, and cleaned in EC4X.

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Run Diagnostics (nimble testBalanceDiagnostics)         │
│    → Generates balance_results/diagnostics/game_*.csv      │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Auto-Archive (via run_parallel_diagnostics.py)          │
│    → Old CSVs archived to ~/.ec4x_test_data (restic)       │
│    → Old CSVs deleted after successful archive              │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Generate Summary (nimble summarizeDiagnostics)          │
│    → Creates balance_results/summary.json (1.4 KB)         │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Optional: Convert to Parquet (nimble convertToParquet)  │
│    → Creates diagnostics_combined.parquet (270 KB)         │
└─────────────────────────────────────────────────────────────┘
```

## Storage Locations

| Location | Purpose | Size (121 games) | Auto-cleaned? |
|----------|---------|------------------|---------------|
| `balance_results/diagnostics/*.csv` | Raw diagnostic data | 9.2 MB | Yes (after archive) |
| `balance_results/summary.json` | AI-friendly summary | 1.4 KB | Manual |
| `balance_results/diagnostics_combined.parquet` | Compressed data | 270 KB | Manual |
| `~/.ec4x_test_data/` | Restic archives | Varies | Manual |

## Automatic Archiving

Every time you run diagnostics, the script automatically:

1. **Checks for existing CSV files** in `balance_results/diagnostics/`
2. **Archives them to restic** with timestamp tag (e.g., `diagnostics-2025-11-26_083045`)
3. **Deletes old CSVs** after successful archive
4. **Runs new diagnostics** with fresh files

**Result:** Your diagnostics folder stays clean, but historical data is preserved!

### Restic Repository

- **Location:** `~/.ec4x_test_data/`
- **Format:** Restic deduplicated backup
- **Password:** None (local test data only)
- **Tags:** `diagnostics-YYYY-MM-DD_HHMMSS`

**Benefits:**
- Deduplication (saves space for repeated data)
- Incremental backups (only stores changes)
- Easy restore by date
- Compressed storage

## Clean Commands

### Basic Cleaning

```bash
# Clean working files (keeps restic archives)
nimble cleanBalance
```

**Removes:**
- `balance_results/diagnostics/*.csv`
- `balance_results/diagnostics_combined.parquet`
- `balance_results/summary.json`
- `tests/balance/run_simulation` binary

**Keeps:**
- `~/.ec4x_test_data/` (restic archives)

### Deep Cleaning

```bash
# Clean EVERYTHING including archives
nimble cleanBalanceAll
```

⚠️ **Warning:** This permanently deletes ALL historical diagnostic data!

**Removes:**
- Everything from `cleanBalance`
- `~/.ec4x_test_data/` (restic archives)
- `balance_results/*` (all results)

### Selective Cleaning

```bash
# Clean only CSV files (keeps Parquet and summary)
nimble cleanDiagnostics
```

**Removes:**
- `balance_results/diagnostics/*.csv`

**Keeps:**
- `balance_results/summary.json`
- `balance_results/diagnostics_combined.parquet`
- Restic archives

**Use case:** After converting to Parquet, delete raw CSVs to save space.

## Archive Management

### List Archives

```bash
# Show all archived diagnostic runs
nimble listArchives

# Or directly
python3 tools/ai_tuning/manage_archives.py list
```

**Output:**
```
Diagnostic Archives in /home/user/.ec4x_test_data
================================================================================
Found 5 archives:

Date                 Tag                            Files    Size
--------------------------------------------------------------------------------
2025-11-26 08:30:45  diagnostics-2025-11-26_083045  121      9.2 MB
2025-11-25 14:22:10  diagnostics-2025-11-25_142210  100      7.6 MB
2025-11-25 10:15:33  diagnostics-2025-11-25_101533  50       3.8 MB
...
```

### Show Archive Statistics

```bash
# Show total archive size and stats
nimble archiveStats

# Or directly
python3 tools/ai_tuning/manage_archives.py stats
```

### Prune Old Archives

```bash
# Keep only last 10 archives (delete older)
nimble pruneArchives

# Or keep specific number
python3 tools/ai_tuning/manage_archives.py prune 5   # Keep last 5
python3 tools/ai_tuning/manage_archives.py prune 20  # Keep last 20
```

**Use case:** When `~/.ec4x_test_data/` grows too large.

### Restore Archive

```bash
# Restore specific archive by tag
python3 tools/ai_tuning/manage_archives.py restore diagnostics-2025-11-26_083045

# Restore to custom location
python3 tools/ai_tuning/manage_archives.py restore diagnostics-2025-11-26_083045 /tmp/old_results
```

**Use case:** Compare current vs historical performance.

## Typical Workflows

### Daily Development Cycle

```bash
# Automatic! No manual cleaning needed
nimble testBalanceDiagnostics  # Auto-archives old, generates new
nimble summarizeDiagnostics    # Generate summary
# Share summary.json with Claude Code
```

**Result:** Always have current data + historical archives preserved.

### Weekly Maintenance

```bash
# Check archive growth
nimble archiveStats

# If too large (>1 GB), prune old archives
nimble pruneArchives  # Keeps last 10
```

### Before Major Refactor

```bash
# Tag current state
python3 tools/ai_tuning/run_parallel_diagnostics.py 100 30 16

# Archives automatically tagged with timestamp
# Later: Restore and compare
python3 tools/ai_tuning/manage_archives.py list
python3 tools/ai_tuning/manage_archives.py restore <tag>
```

### End of Project

```bash
# Clean everything to free space
nimble cleanBalanceAll

# Or keep archives but clean working data
nimble cleanBalance
```

## Space Usage Estimates

**Per diagnostic run (121 games, 30 turns):**
- Raw CSV: 9.2 MB
- Parquet: 270 KB (3% of CSV)
- Summary: 1.4 KB (0.015% of CSV)
- Restic archive: ~3-5 MB (deduplicated)

**Expected growth:**
- 10 runs: ~30-50 MB (restic)
- 50 runs: ~150-250 MB (restic)
- 100 runs: ~300-500 MB (restic)

**Recommendation:** Prune to last 10-20 archives for balance work.

## Archive vs Parquet vs Summary

| Format | Size | Use Case | When to Use |
|--------|------|----------|-------------|
| **Restic Archive** | 3-5 MB | Historical reference | Automatic (every run) |
| **Parquet** | 270 KB | Deep analysis | When sharing with Claude for complex issues |
| **Summary JSON** | 1.4 KB | Quick feedback | Every time (default workflow) |

**General rule:**
1. **Always generate summary** (1.4 KB, ~500 tokens)
2. **Convert to Parquet if needed** (for targeted queries)
3. **Archives happen automatically** (no action needed)

## Troubleshooting

### "restic not found"

Install restic:
```bash
# Ubuntu/Debian
sudo apt install restic

# macOS
brew install restic

# Or download from: https://restic.net
```

### Archive Failed

If archive fails, old CSVs are still deleted to prevent disk space issues:

```
⚠ Archive failed: ...
  Removing old files anyway...
✓ Removed 121 old CSV files
```

**Solution:** Fix restic installation, or disable archiving:

```python
# In run_parallel_diagnostics.py, comment out:
# archive_old_diagnostics()
```

### Archives Too Large

```bash
# Check size
nimble archiveStats

# Prune to last N
python3 tools/ai_tuning/manage_archives.py prune 5
```

### Can't Restore Archive

```bash
# List available archives
nimble listArchives

# Restore by exact tag
python3 tools/ai_tuning/manage_archives.py restore diagnostics-2025-11-26_083045
```

## Best Practices

### ✅ DO

1. **Let auto-archive work** - Don't disable it
2. **Use summary.json first** - Avoid reading raw CSVs
3. **Prune periodically** - Keep last 10-20 archives
4. **Convert to Parquet** - After validating CSV data
5. **Delete CSVs after Parquet** - Use `nimble cleanDiagnostics`

### ❌ DON'T

1. **Don't manually delete ~/.ec4x_test_data/** - Use `nimble cleanBalanceAll`
2. **Don't keep 100+ archives** - Prune regularly
3. **Don't share raw CSVs** - Use summary or Parquet
4. **Don't disable auto-archive** - Historical data is valuable
5. **Don't forget to prune** - Check `nimble archiveStats` weekly

## Quick Reference

```bash
# Generate data
nimble testBalanceDiagnostics          # 50 games (auto-archives old)
nimble summarizeDiagnostics            # Generate summary.json

# Convert formats
nimble convertToParquet                # CSV → Parquet (34x smaller)

# View archives
nimble listArchives                    # List all archives
nimble archiveStats                    # Show storage stats

# Clean data
nimble cleanDiagnostics                # Clean CSVs only
nimble cleanBalance                    # Clean working files (keeps archives)
nimble cleanBalanceAll                 # Clean EVERYTHING (⚠️ destructive)

# Manage archives
nimble pruneArchives                   # Keep last 10 archives
python3 tools/ai_tuning/manage_archives.py restore <tag>  # Restore specific
```

## Integration with Git

Archives are NOT tracked by git (in `.gitignore`):

```gitignore
balance_results/
~/.ec4x_test_data/
```

**Instead:**
- Commit summary.json for milestone reference
- Use git tags to mark significant RBA changes
- Refer to archive tags in commit messages

**Example:**
```bash
git commit -m "fix(ai): Improve fighter build logic

Baseline: diagnostics-2025-11-26_083045 (0.4 avg fighters)
After:    diagnostics-2025-11-26_141022 (15.2 avg fighters)

See balance_results/summary.json for metrics"
```

## Summary

**Automatic:** Archives clean themselves up, preserving history in restic.

**Manual:** Use `cleanBalance` for working data, `pruneArchives` for old backups.

**Result:** Always have current data for analysis + historical baseline for comparison.
