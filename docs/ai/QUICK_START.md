# Quick Start: RBA Optimization with Claude Code

**Time to first feedback: 3 minutes**

## 1. Run Diagnostics (2 minutes)

```bash
nimble testBalanceDiagnostics
```

This runs 50 games in parallel on your 7950X3D and generates diagnostic CSV files.

## 2. Generate Summary (instant)

```bash
nimble summarizeDiagnostics
```

This creates `balance_results/summary.json` (~500 tokens) - an AI-friendly summary of all diagnostic data.

## 3. Share with Claude Code

```bash
cat balance_results/summary.json
```

Copy the output and paste into your Claude Code conversation:

```
Me: I just ran diagnostics on my RBA. Here's the summary:

[paste JSON]

What issues do you see?
```

## 4. Get Feedback

Claude will analyze the summary and provide specific, actionable feedback:

```
Claude: I see two critical issues:

1. **Fighter Production (Phase 2b): FAIL**
   - avg_fighters: 0.4 (target: 5-10)
   - capacity_violation_rate: 2.04%

   Issue: Build threshold too restrictive at ai_controller.nim:312

2. **Treasury Hoarding Anomaly**
   - 82,461 turns with 10+ zero-spend streaks

   Issue: Budget allocation logic in budget.nim not spending available PP

Want me to investigate the fighter build logic?
```

## 5. Iterate

Make the suggested change, re-run diagnostics, share new summary. Typical iteration cycle: **3-5 minutes**.

---

## What You Get

- **Token efficiency**: 500 tokens instead of 5,000,000
- **Fast feedback**: 10 seconds instead of waiting for manual analysis
- **Actionable insights**: Specific file/line numbers and code suggestions
- **Rapid iteration**: 3-5 minute cycles

## Next Steps

- Read **TOKEN_EFFICIENT_WORKFLOW.md** for the complete workflow
- Read **RBA_OPTIMIZATION_GUIDE.md** for RBA-specific patterns
- Read **AI_ANALYSIS_WORKFLOW.md** for technical details

## Dependencies

```bash
pip install polars
```

## That's It!

You're now ready to efficiently optimize your RBA with Claude Code's help.
