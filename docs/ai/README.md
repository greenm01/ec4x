# Analysis Documentation

Guides for optimizing EC4X's Rule-Based AI (RBA) using diagnostic data and Claude Code.

**Last Updated:** 2025-11-27 (Terminal-Based Analysis System)

## Overview

This directory contains everything you need to efficiently balance your game by leveraging your **AMD Ryzen 7950X3D** for data crunching and **Claude Code** for expert analysis.

**Key Insight:** Use local compute to crunch data, share tiny summaries with Claude → 99.99% token reduction!

## 🆕 Recent Changes (2025-11-26)

### QoL Integration Complete

The RBA system now integrates with Quality-of-Life features for intelligent, personality-driven automation:

**✅ Integrated Systems:**
- **Budget Tracking** - Engine + AI level validation (0% overspending achieved!)
- **Standing Orders** - Intelligent fleet automation based on role + personality
- **Fleet Validation** - Security + target validation (100% compliance)
- **Ownership Checks** - Prevents unauthorized fleet control

**🔴 Known Issues:** Several AI subsystems have integration bugs discovered in testing:
- Espionage system not executing (0% usage)
- Scout production not triggering (0 scouts built)
- Mothballing logic not activating (0% usage)
- Resource hoarding (55% games affected)

**See:** `docs/testing/BALANCE_TESTING_2025-11-26.md` for full test report

## 🆕 Terminal-Based Analysis System (2025-11-27)

**NEW WORKFLOW:** Self-service RBA tuning + Claude-assisted analysis

```bash
# Full analysis workflow (fast!)
nimble analyzeBalance           # CSV → Parquet → Analysis → Report

# Or use individual commands:
nimble balanceSummary           # Quick overview
nimble balancePhase2            # Phase 2 gap analysis
nimble balanceOutliers          # Detect anomalies
nimble balanceExport            # Export to Excel/LibreOffice
nimble balanceReport            # Generate markdown report
```

**Key Benefits:**
- ✅ **100x faster** analysis (Parquet vs CSV)
- ✅ **1000x token reduction** for Claude (markdown summaries)
- ✅ **Terminal + Excel** workflow (no web dashboard)
- ✅ **Self-service** tuning (edit `config/rba.toml`, test, repeat)

**See:** `/docs/guides/BALANCE_ANALYSIS_SYSTEM.md` for comprehensive guide

## Quick Start (Legacy)

```bash
# 1. Run diagnostics (2 minutes)
nimble testBalanceDiagnostics

# 2. New: Full analysis workflow
nimble analyzeBalance           # Recommended!

# 3. Legacy: Generate JSON summary
nimble summarizeDiagnostics

# 4. Share with Claude Code
cat balance_results/analysis_report.md  # New: markdown report
cat balance_results/summary.json        # Legacy: JSON summary
```

**Result:** Actionable feedback from ~500 tokens instead of 5 million!

## Documentation

### 0. /docs/guides/BALANCE_ANALYSIS_SYSTEM.md ⭐ **NEW**
**Purpose:** Complete guide to the terminal-based analysis system

**Topics:**
- Self-service RBA tuning workflow
- Best practices for solo tuning
- Tips for Claude-assisted tuning
- Command reference (nimble tasks, CLI, Python API)
- Excel/LibreOffice pivot table analysis
- Troubleshooting & performance tips

**When to read:** START HERE for the new analysis system

### 1. TOKEN_EFFICIENT_WORKFLOW.md
**Purpose:** Learn the optimal workflow for sharing data with Claude Code

**Topics:**
- Token economics (CSV vs Parquet vs JSON)
- The 3-phase workflow (generate → summarize → share)
- Targeted analysis patterns
- Iteration loops
- A/B testing

**When to read:** Before your first optimization session

### 2. RBA_OPTIMIZATION_GUIDE.md
**Purpose:** Systematic approach to improving rule-based AI behavior

**Topics:**
- Understanding RBA architecture (`src/ai/`)
- Diagnostic metrics explained
- Common patterns & fixes (thresholds, personality coverage, etc.)
- Anomaly interpretation
- Validation checklists
- Getting help from Claude effectively

**When to read:** When diving into AI code changes

### 3. AI_ANALYSIS_WORKFLOW.md
**Purpose:** Complete technical reference for analysis tools

**Topics:**
- Tool usage (generate_summary.py, convert_to_parquet.py, etc.)
- File locations and formats
- Performance tuning for 7950X3D
- Custom Polars queries
- Integration with CI/CD

**When to read:** When you need technical details about the tools

### 4. DATA_MANAGEMENT.md
**Purpose:** How diagnostic data is stored, archived, and cleaned

**Topics:**
- Auto-archiving with restic
- Clean commands (cleanBalance, cleanBalanceAll, cleanDiagnostics)
- Archive management (list, prune, restore)
- Space usage and best practices

**When to read:** When managing disk space or restoring old data

## Tools Reference

| Tool | Purpose | Usage |
|------|---------|-------|
| `run_parallel_diagnostics.py` | Generate CSV diagnostics | `nimble testBalanceDiagnostics` |
| `generate_summary.py` | Create AI-friendly JSON | `nimble summarizeDiagnostics` |
| `convert_to_parquet.py` | Compress CSV → Parquet | `nimble convertToParquet` |
| `analyze_phase2_gaps.py` | Detailed Phase 2 analysis | `nimble analyzeDiagnostics` |
| `analyze_4act_progression.py` | 4-act validation | `nimble analyzeProgression` |
| `example_custom_analysis.py` | Template for custom queries | See guide |

All tools located in `tools/ai_tuning/`

## Typical Workflow

```
┌──────────────────────────────────────────────────────────────┐
│ Problem: "Fighters aren't being built"                      │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ 1. Run Diagnostics                                           │
│    nimble testBalanceDiagnostics  # 50 games, 2 min         │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ 2. Generate Summary                                          │
│    nimble summarizeDiagnostics                               │
│    → Shows: avg_fighters: 0.4 (target: 5-10)                │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ 3. Share with Claude                                         │
│    cat balance_results/summary.json                          │
│    → Claude: "Build threshold too high (line 312)"          │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ 4. Make Change                                               │
│    # ai_controller.nim:312                                   │
│    - if techPriority >= 0.4 and aggression >= 0.4:          │
│    + if techPriority >= 0.3 or aggression >= 0.5:           │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ 5. Validate                                                  │
│    nimble testBalanceDiagnostics                             │
│    → Shows: avg_fighters: 15.2 ✓                            │
└──────────────────────────────────────────────────────────────┘
```

**Cycle time:** 3-5 minutes per iteration

## File Locations

```
balance_results/
├── diagnostics/
│   ├── game_*.csv                    # Raw diagnostics (9.2 MB)
│   └── ...
├── diagnostics_combined.parquet      # Compressed format (270 KB)
└── summary.json                      # AI-friendly summary (1.4 KB)

docs/analysis/
├── README.md                         # This file
├── TOKEN_EFFICIENT_WORKFLOW.md       # Workflow guide
├── RBA_OPTIMIZATION_GUIDE.md         # RBA-specific guide
└── AI_ANALYSIS_WORKFLOW.md           # Technical reference

tools/ai_tuning/
├── generate_summary.py               # Summary generator
├── convert_to_parquet.py             # Parquet converter
├── example_custom_analysis.py        # Query examples
└── ...                               # Other analysis tools
```

## Quick Command Reference

```bash
# Diagnostic Generation
nimble testBalanceDiagnostics       # 50 games, quick iteration
nimble testUnknownUnknowns          # 200 games, comprehensive

# Analysis
nimble summarizeDiagnostics         # AI-friendly JSON summary
nimble analyzeDiagnostics           # Detailed Phase 2 analysis
nimble analyzeProgression           # 4-act validation

# Data Management
nimble convertToParquet             # CSV → Parquet (34x smaller)
nimble cleanBalance                 # Clean working files (keeps archives)
nimble cleanBalanceAll              # Clean EVERYTHING including archives
nimble cleanDiagnostics             # Clean CSVs only (keep Parquet/summary)

# Archive Management
nimble listArchives                 # List all archived runs
nimble archiveStats                 # Show storage statistics
nimble pruneArchives                # Keep last 10 archives

# Custom Analysis
python3 tools/ai_tuning/example_custom_analysis.py fighters
python3 tools/ai_tuning/example_custom_analysis.py treasury
python3 tools/ai_tuning/example_custom_analysis.py combat
```

## Token Budget Examples

### Scenario 1: Quick Check (Recommended)
```
Share: summary.json (500 tokens)
Time:  Instant
Result: "Fighter threshold too high, try 0.3 instead of 0.4"
```

### Scenario 2: Targeted Analysis
```
Share: filtered_fighters.json (1,500 tokens)
Time:  Instant
Result: "Only House Atreides builds fighters - personality coverage issue"
```

### Scenario 3: Deep Dive (Rare)
```
Share: diagnostics_combined.parquet (50,000 tokens)
Time:  ~30 seconds to upload
Result: Full cross-system analysis with multiple interconnected fixes
```

### Scenario 4: Naive Approach (DON'T DO THIS)
```
Share: Raw CSV files (5,000,000 tokens)
Result: Context overflow, conversation fails, can't get help
```

## Performance Expectations

**7950X3D @ 16 workers:**
- 50 games: ~2 minutes
- 100 games: ~4 minutes
- 200 games: ~10 minutes

**Analysis:**
- Summary generation: ~2 seconds
- Parquet conversion: ~3 seconds
- Custom query: <1 second (from Parquet)

**Claude feedback:**
- From summary: ~10 seconds
- From filtered data: ~30 seconds
- From Parquet: ~60 seconds

## Best Practices

### ✅ DO
- Start with summary.json (99% of cases)
- Use 50 games for quick iterations
- Share filtered subsets for targeted issues
- Ask specific questions with code context
- Iterate rapidly (3-5 minute cycles)

### ❌ DON'T
- Upload raw CSV files
- Test with <20 games (too much variance)
- Share all 130 columns unnecessarily
- Ask vague questions without metrics
- Wait for 200-game runs before getting feedback

## Example Session

**You:**
```
Working on Phase 2b (fighter/carrier). Ran 50 games.

[paste summary.json]

Why aren't fighters being built?
```

**Claude:**
```
Issue: avg_fighters: 0.4 (target: 5-10)

This is very low. Let me check ai_controller.nim...

Found it at line 312:
  if personality.techPriority >= 0.4 and personality.aggression >= 0.4:

This requires BOTH traits high. Only 1/4 of personalities match.

Try:
  if personality.techPriority >= 0.3 or personality.aggression >= 0.5:

This allows tech-focused OR aggressive houses to build fighters.
```

**You (2 minutes later):**
```
Made the change. New results:

[paste new summary.json showing 15.2 avg_fighters]
```

**Claude:**
```
Excellent! avg_fighters: 15.2 ✓

But now idle_carrier_rate: 23.4% - fighters exist but aren't being
loaded onto carriers. Want me to check the assignment logic?
```

**Result:** Two iterations, ~5 minutes, ~1000 tokens total

## Dependencies

```bash
# Required for analysis tools
pip install polars

# Verify
python3 -c "import polars as pl; print(f'Polars {pl.__version__} ready')"
```

## Getting Started

1. **Read TOKEN_EFFICIENT_WORKFLOW.md** (15 min)
2. **Run test diagnostics**: `nimble testBalanceDiagnostics` (2 min)
3. **Generate summary**: `nimble summarizeDiagnostics` (instant)
4. **Try sharing summary.json with Claude** in a conversation
5. **Read RBA_OPTIMIZATION_GUIDE.md** when ready to make changes

## Support

- **Tool documentation**: See individual `.py` file headers
- **Nimble tasks**: `nimble --help`
- **Claude Code help**: Ask about specific metrics or anomalies
- **RBA code**: See `src/ai/` modules

## Contributing

When adding new diagnostic metrics:

1. Add column to CSV in `tests/balance/run_simulation.nim`
2. Update `generate_summary.py` to analyze it
3. Document in `RBA_OPTIMIZATION_GUIDE.md`
4. Add example query to `example_custom_analysis.py`

## Related Documentation

- `/docs/BALANCE_TESTING_METHODOLOGY.md` - Target metrics and 4-act structure
- `/docs/UNKNOWN_UNKNOWNS_FINDINGS_2025-11-25.md` - Lessons learned
- `/tools/ai_tuning/README.md` - Tool-specific documentation
- `/CLAUDE_CONTEXT.md` - Development context and gotchas

---

**Remember:** Crunch data locally with your 7950X3D, share tiny summaries with Claude Code. This workflow gives you fast, expert feedback while staying well within token budgets!
