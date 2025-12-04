
╔══════════════════════════════════════════════════════════════╗
║           RBA BASELINE ANALYSIS REPORT                       ║
╚══════════════════════════════════════════════════════════════╝

Dataset Overview:
  Total Games:    16
  Total Houses:   64

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MILITARY BEHAVIOR ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Wars Declared:
  Mean:       0.0
  Std Dev:    0.0
  Range:      [0, 0]

  Target:     6-15 wars per game
  Status:     ❌ BELOW TARGET

Invasions Attempted:
  Mean:       0.0
  Std Dev:    0.0
  Range:      [0, 0]

  Target:     15-40 invasions per game
  Status:     ❌ BELOW TARGET

Other Combat:
  Space Battles (avg):         0.0
  Orbital Bombardments (avg):  0.0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BUDGET ALLOCATION (ACT 3)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Production (avg):         0.0 PP/turn
Treasury (avg):           0.0 PP
Ship Growth (avg):        0.0 ships

Note: Detailed budget breakdown requires additional instrumentation

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GAME QUALITY METRICS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Games Reaching Turn 40:   0/16
Houses Collapsed:         0
Houses Eliminated:        0

Final State (avg):
  Colonies:    2.0
  Ships:       6.0
  Prestige:    2507

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GOAP EVALUATION CRITERIA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current RBA Performance:
  Wars:        0.0 (target: 6-15)
  Invasions:   0.0 (target: 15-40)

Recommendation:

  ❌ CURRENT RBA BELOW TARGETS

  GOAP could help by:
  - Better multi-turn planning (invasion sequences)
  - Goal-driven war declarations
  - Opportunistic military strategy

  Gaps:
    Wars: 6.0 below minimum
    Invasions: 15.0 below minimum


Next Steps:
  1. Review detailed game CSVs for patterns
  2. Run 2-3 day GOAP prototype spike
  3. Compare complexity vs benefit
  4. Make informed decision

Report saved to: analysis/rba_baseline_report.md
