# Player TUI Playtest Checklist

Use this checklist for structured human playtest sessions focused on
commanding through the Player TUI without dev shortcuts.

## Session Metadata

- Date:
- Build/commit:
- Player house:
- Seed / game id:
- Terminal size (cols x rows):
- Notes recorder:

## Pre-Session Setup

- [ ] Build passes (`nimble buildTui`).
- [ ] Player can open and navigate all core views.
- [ ] Draft restore path is available.
- [ ] Terminal starts in target size for this session.

## Scenario Track A: Single-Fleet Normal Flow

- [ ] Open fleet detail from list view.
- [ ] Stage one movement command and one target-select command.
- [ ] Change ROE and verify staged summary reflects changes.
- [ ] Edit or drop staged fleet command.
- [ ] Confirm target picker behavior is sensible and reachable.

## Scenario Track B: Batch Fleet Flow

- [ ] Select multiple fleets with `X`.
- [ ] Stage batch command and batch ROE update.
- [ ] Move cursor/sort between stage and confirm.
- [ ] Verify snapshot semantics (only X-selected fleets affected).
- [ ] Stage one batch ZTC and verify summary count.

## Scenario Track C: Colony + Economy + Diplomacy

- [ ] Stage build command(s) and adjust quantity.
- [ ] Stage repair/scrap from maintenance modal.
- [ ] Stage population transfer and terraform command.
- [ ] Stage one diplomacy change and one espionage action.
- [ ] Stage research allocation and verify totals.

## Scenario Track D: Draft Restore + Replay

- [ ] Save draft with mixed staged categories.
- [ ] Restart client and restore draft.
- [ ] Verify optimistic fleet state after restore.
- [ ] Drop/edit one restored command and re-check summary.

## Narrow-Terminal Pass

- [ ] Repeat critical modal flows at 100x30.
- [ ] Repeat critical modal flows at 80x24.
- [ ] Verify no clipped footers, borders, or key hints.
- [ ] Verify table and footer widths feel balanced.

## Submit Confidence

- [ ] Submit mixed command packet.
- [ ] Verify submit confirmation category totals.
- [ ] Verify staged queue clears as expected after submit.

## Exit Criteria

- [ ] No blocking UX defects found.
- [ ] All discovered issues logged with reproduction steps.
- [ ] Session outcomes summarized and linked to issue entries.
