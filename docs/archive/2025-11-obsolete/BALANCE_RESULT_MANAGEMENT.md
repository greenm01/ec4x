# Balance Testing Result Management System

**Version:** 1.0
**Date:** 2025-11-23
**Status:** Proposal

---

## Problem Statement

Currently, balance test results are scattered across multiple directories with no systematic organization:

- `/home/niltempus/dev/ec4x/balance_results/` - Recent coevolution tests (7GB+ of logs)
- `/home/niltempus/dev/ec4x/balance_tuning/sweep_results/` - Parameter sweep results
- Test outputs mixed with logs making analysis difficult
- No historical comparison or trend tracking
- No automated archival or cleanup

**Issues:**
1. Large log files (1GB each) filling disk space
2. No easy way to compare test runs over time
3. Unclear which test corresponds to which code changes
4. Manual effort required to find relevant tests

---

## Proposed Solution

### Directory Structure

```
balance_results/
├── archive/                  # Historical tests (compressed)
│   └── YYYY-MM-DD_HHMMSS/   # Timestamped test runs
│       ├── metadata.json     # Git hash, config, params
│       ├── summary.json      # Condensed metrics only
│       └── logs.tar.gz       # Compressed full logs (optional)
│
├── current/                  # Active test workspace
│   ├── coevolution/         # Latest coevolution test
│   ├── sweep/               # Latest parameter sweep
│   └── quick/               # Fast validation tests
│
├── reports/                  # Analysis & comparisons
│   ├── latest.md            # Most recent analysis
│   ├── trends.md            # Historical trend analysis
│   └── comparisons/         # Side-by-side comparisons
│       └── HASH1_vs_HASH2.md
│
└── index.json               # Master index of all tests
```

### Key Features

#### 1. Automatic Archival
- Tests older than 7 days automatically move to `archive/`
- Logs compressed (gzip) to save space
- Only summary JSON + metadata retained in uncompressed form
- Configurable retention policy (keep last N tests per type)

#### 2. Test Metadata Tracking
```json
{
  "timestamp": "2025-11-23T01:07:44Z",
  "git_hash": "48d0470a",
  "git_branch": "main",
  "test_type": "coevolution",
  "config": {
    "generations": 50,
    "population": 10,
    "games_per_gen": 8
  },
  "results_summary": {
    "total_games": 1000,
    "avg_turns": 50,
    "species_win_rates": {...}
  },
  "code_changes": [
    "tests/balance/ai_controller.nim",
    "config/espionage.toml"
  ]
}
```

#### 3. Result Comparison Tool
```bash
# Compare two test runs
./tests/balance/compare_results archive/2025-11-22_010000 current/coevolution

# Output: Markdown report showing:
# - Win rate changes per species
# - Fitness trend differences
# - Configuration differences
# - Statistical significance
```

#### 4. Trend Analysis Dashboard
- Automatically generate trend graphs from archived tests
- Track metrics over time:
  - Species win rates
  - Average game length
  - Combat frequency
  - Economic activity
- Detect balance regressions

#### 5. Smart Cleanup
```bash
# Cleanup policy (configurable)
MAX_TESTS_PER_TYPE=20
MAX_AGE_DAYS=30
COMPRESS_LOGS_OLDER_THAN_DAYS=7
DELETE_LOGS_OLDER_THAN_DAYS=30  # Keep JSON only
```

---

## Implementation Plan

### Phase 1: Directory Structure & Archival (2-3 hours)

**Files to create:**
1. `tests/balance/archive_results.sh` - Archive old tests
2. `tests/balance/cleanup_results.sh` - Manage disk space
3. `tests/balance/result_manager.nim` - Core management logic

**Tasks:**
- Create directory structure
- Implement automatic timestamping
- Add git hash capture to test scripts
- Compress old logs

### Phase 2: Comparison Tool (2-3 hours)

**Files to create:**
1. `tests/balance/compare_results.nim` - Compare two test runs
2. Template: `docs/templates/comparison_report.md`

**Features:**
- Load two test JSONs
- Calculate deltas for all metrics
- Statistical significance tests (t-test for win rates)
- Generate markdown report with tables

### Phase 3: Trend Analysis (3-4 hours)

**Files to create:**
1. `tests/balance/trend_analysis.nim` - Track metrics over time
2. `tests/balance/plot_trends.py` - Generate graphs (matplotlib)

**Features:**
- Load all archived test summaries
- Plot win rate trends over time
- Identify balance regressions
- Correlate with git commits

### Phase 4: Integration & Automation (1-2 hours)

**Tasks:**
- Update `run_parallel_test.sh` to auto-archive
- Add cleanup to pre-test hooks
- Generate comparison reports after each test
- Add CI/CD integration (future)

---

## Usage Examples

### Running a Test (Automated Workflow)

```bash
# Run parallel test (automatically archives on completion)
./tests/balance/run_parallel_test.sh 4 10 8 5

# Output:
# - balance_results/current/coevolution/ (latest results)
# - balance_results/reports/latest.md (analysis)
# - balance_results/archive/2025-11-23_010744/ (previous test moved)
```

### Manual Archival

```bash
# Archive current test with custom label
./tests/balance/archive_results.sh --label "post-espionage-fix"

# Output: balance_results/archive/2025-11-23_012000_post-espionage-fix/
```

### Comparing Tests

```bash
# Compare latest test to previous
./tests/balance/compare_results current archive/latest

# Compare specific git commits
./tests/balance/compare_results --git 48d0470 401abb4

# Output: balance_results/reports/comparisons/48d0470_vs_401abb4.md
```

### Cleanup

```bash
# Manual cleanup (safe - prompts before delete)
./tests/balance/cleanup_results.sh --dry-run

# Automatic cleanup (cron job)
# Runs daily, keeps last 20 tests per type, compresses logs >7 days
@daily /home/niltempus/dev/ec4x/tests/balance/cleanup_results.sh --auto
```

---

## Configuration

### Global Config: `balance_results/config.toml`

```toml
[retention]
max_tests_per_type = 20
max_age_days = 30
compress_logs_after_days = 7
delete_logs_after_days = 30  # Keep JSON summaries only

[archival]
auto_archive = true
capture_git_info = true
compress_method = "gzip"  # or "zstd" for better compression

[comparison]
statistical_significance_threshold = 0.05
min_games_for_comparison = 100

[trends]
plot_format = "png"  # or "svg"
update_on_archive = true
```

---

## Metrics Tracked

### Per-Test Summary JSON

```json
{
  "species_performance": {
    "Economic": {
      "win_rate": 0.299,
      "avg_colonies": 1.2,
      "avg_military": 3.5,
      "avg_prestige": 245,
      "avg_fitness": 0.194
    },
    // ... other species
  },
  "game_statistics": {
    "total_games": 1000,
    "avg_turns": 50,
    "max_turns": 50,
    "elimination_wins": 0,
    "prestige_wins": 1000,
    "combat_events": 145,
    "espionage_events": 423,
    "diplomatic_events": 89
  },
  "balance_assessment": {
    "status": "moderate_imbalance",
    "dominant_species": "Technology",
    "unviable_species": [],
    "recommendation": "Increase Military building priority"
  }
}
```

---

## Benefits

1. **Disk Space**: Reduce storage by 80%+ through compression
2. **Organization**: Clear separation of active vs archived tests
3. **Traceability**: Git hash tracking links tests to code changes
4. **Analysis**: Easy comparison and trend detection
5. **Confidence**: Historical data for validating balance changes
6. **Automation**: Set-and-forget cleanup and archival

---

## Alternatives Considered

### Alternative 1: Database Storage
**Pros:** Structured queries, better for large-scale analysis
**Cons:** Additional dependency, overkill for current scale
**Decision:** Keep file-based for simplicity, consider for future

### Alternative 2: Cloud Storage
**Pros:** Unlimited storage, accessible from anywhere
**Cons:** Cost, network dependency, privacy concerns
**Decision:** Local-first, optional cloud sync later

### Alternative 3: Delete Old Tests
**Pros:** Simple, no maintenance
**Cons:** Lose historical data, can't track balance regressions
**Decision:** Archive instead of delete

---

## Next Steps

1. **Review this proposal** - Validate approach
2. **Implement Phase 1** - Basic archival + cleanup (today)
3. **Test workflow** - Run parallel test with archival
4. **Implement Phase 2** - Comparison tool (next session)
5. **Implement Phase 3** - Trend analysis (future)

---

## Questions for Review

1. Is 20 archived tests per type sufficient?
2. Should we track more granular metrics (per-turn data)?
3. Do we want automatic GitHub issue creation for balance regressions?
4. Should comparison tool generate visual diffs (graphs)?

---

**See Also:**
- `docs/BALANCE_TESTING_METHODOLOGY.md` - Testing philosophy
- `docs/STATUS.md` - Current project status
- `tests/balance/README.md` - Testing usage guide
