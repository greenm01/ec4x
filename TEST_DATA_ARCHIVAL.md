# Test Data Archival System

## Overview

EC4X uses **restic** for automatic archival of balance test data to prevent disk space bloat while preserving historical results for analysis.

## How It Works

1. **Automatic Archival**: `run_balance_test.py` archives existing `balance_results/` before each test run
2. **Date-Based Tags**: Each archive is tagged with timestamp (e.g., `2025-11-23_154530`)
3. **Compression**: Restic automatically deduplicates and compresses data
4. **Local Storage**: Archives stored in `~/.ec4x_test_data` (outside git repo)

## Archive Location

```
~/.ec4x_test_data/          # Restic repository (NOT in git)
```

This directory is excluded from git via `.gitignore`.

## Viewing Archived Data

Use the `view_test_archives.sh` helper script:

```bash
# List all archived snapshots
./view_test_archives.sh list

# Show date tags
./view_test_archives.sh tags

# Restore specific snapshot
./view_test_archives.sh restore <snapshot_id> ./restored_data

# Restore by date
./view_test_archives.sh restore-date 2025-11-23_154530

# Show storage statistics
./view_test_archives.sh stats

# Clean up old archives (keeps last 30 days)
./view_test_archives.sh prune
```

## Storage Management

### Automatic Cleanup
The Python test script removes `balance_results/` after archiving it, keeping your working directory clean.

### Manual Pruning
Remove archives older than 30 days:

```bash
./view_test_archives.sh prune
```

### Full Cleanup
To completely remove all archived data:

```bash
rm -rf ~/.ec4x_test_data
```

## What Gets Archived

- `balance_results/full_simulation.json` - Complete game state snapshots
- `balance_results/simulation_reports/` - Per-house turn reports
- `balance_results/turn_reports/` - Detailed turn-by-turn data
- `balance_results/archive/` - Previous test runs (if any)
- `balance_results/coevolution/` - Genetic algorithm evolution data

## Why Restic?

- **Deduplication**: Only stores changed data (saves ~80% disk space)
- **Compression**: Automatic compression of JSON/text data
- **Fast**: Incremental backups in seconds
- **Reliable**: Battle-tested backup tool used in production
- **No Password**: Local archives don't need encryption overhead

## Integration Points

### Python Test Runner
`run_balance_test.py` line 89-126: Archives before starting new tests

### Nim Simulation
`tests/balance/run_simulation.nim` line 41: Creates `balance_results/` output directories

### Git Ignore
`.gitignore` line 92-94: Excludes `balance_results/` and archive directories

## Troubleshooting

### "Repository does not exist"
The repository is auto-created on first run. If you see this error:

```bash
RESTIC_REPOSITORY="$HOME/.ec4x_test_data" RESTIC_PASSWORD="" restic init
```

### "Permission denied"
Ensure the archive script is executable:

```bash
chmod +x view_test_archives.sh
```

### Check disk usage
```bash
du -sh ~/.ec4x_test_data
./view_test_archives.sh stats
```

## Best Practices

1. **Run `prune` monthly** to clean up old data
2. **Check `stats` occasionally** to monitor disk usage
3. **Keep date tags** for reproducibility (e.g., paper submissions, bug reports)
4. **Archive before major changes** to baseline performance
