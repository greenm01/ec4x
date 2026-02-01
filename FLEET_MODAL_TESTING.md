# Fleet Detail Modal - Testing Guide

## Quick Start

```bash
./bin/tui
```

## Test Scenario Setup

1. **Launch TUI** and log in to a game
2. **Navigate to Fleet Console** (View → Fleet Console or `V` → `F`)
3. **Select a fleet** from the list (use ↑/↓ arrows)

## Test Cases

### 1. Basic Modal Operations

**Open/Close:**
- [ ] Press `Enter` on a fleet → Modal opens with fleet info
- [ ] Press `Esc` → Modal closes, returns to fleet list
- [ ] Verify modal shows: Fleet ID, Location, Command, ROE, Ship count
- [ ] Verify ship list displays: Class, WEP, AS, DS, MAR, State

**Staged Command Indicator:**
- [ ] Stage a command (see Test Case 2)
- [ ] Close modal and return to fleet list
- [ ] Verify `●` appears before fleet ID in list
- [ ] Select different fleet → verify no `●` indicator

### 2. Command Picker Navigation

**Opening Command Picker:**
- [ ] With modal open, press `C` → Command picker opens
- [ ] Verify 7 categories visible on left side
- [ ] Verify first category (Movement) is selected by default
- [ ] Verify commands shown on right side

**Category Navigation:**
- [ ] Press `Tab` → Next category selected
- [ ] Press `Shift+Tab` → Previous category selected
- [ ] Cycle through all 7 categories:
  1. Movement (4 commands)
  2. Defense (3 commands)
  3. Combat (3 commands)
  4. Colonial (1 command)
  5. Intel (4 commands)
  6. Fleet Ops (3 commands)
  7. Status (2 commands)

**Command Navigation:**
- [ ] Use `↑`/`↓` arrows to navigate commands within category
- [ ] Verify navigation wraps at boundaries (doesn't crash)
- [ ] Verify command count matches category (e.g., Movement has 4)

**Command Selection:**
- [ ] Navigate to "Hold" command
- [ ] Press `Enter` → Modal closes, command staged
- [ ] Press `Esc` instead → Modal closes, no command staged

### 3. ROE Picker

**Opening ROE Picker:**
- [ ] With modal open, press `R` → ROE picker opens
- [ ] Verify slider shows current ROE value (default: 6)
- [ ] Verify tactical description shown (e.g., "Standard: Fight if equal...")

**ROE Navigation:**
- [ ] Press `↑` → ROE increases (6 → 7)
- [ ] Press `↓` → ROE decreases (7 → 6)
- [ ] Navigate to ROE 0 → Verify "Avoid: Avoid all hostile forces"
- [ ] Navigate to ROE 10 → Verify "Suicidal: Fight regardless of odds"
- [ ] Verify bounds: Can't go below 0 or above 10

**ROE Selection:**
- [ ] Set ROE to 8 (Aggressive)
- [ ] Press `Enter` → Modal closes, ROE staged
- [ ] Reopen modal → Verify ROE shows 8 in header
- [ ] Press `Esc` instead → Modal closes, ROE unchanged

### 4. Confirmation Dialogs

**Commands Requiring Confirmation:**
Test each of these commands shows a confirmation prompt:

- [ ] **Bombard** → "Bombard will destroy infrastructure. Proceed? (Y/N)"
- [ ] **Salvage** → "Salvage will scrap all ships. Proceed? (Y/N)"
- [ ] **Reserve** → "Reserve will mothball fleet. Proceed? (Y/N)"
- [ ] **Mothball** → "Mothball will deactivate fleet. Proceed? (Y/N)"

**Confirmation Flow:**
- [ ] Select "Bombard" command
- [ ] Press `Y` → Command staged, modal closes
- [ ] Reopen modal, select "Bombard" again
- [ ] Press `N` → Command cancelled, modal closes
- [ ] Verify no command was staged

### 5. Full Command Workflow

**Complete Command Staging:**
1. [ ] Select fleet in list
2. [ ] Press `Enter` → Open modal
3. [ ] Press `C` → Open command picker
4. [ ] Navigate to "Scout System" (Intel category)
5. [ ] Press `Enter` → Select command
6. [ ] Verify modal closes
7. [ ] Verify `●` appears next to fleet ID
8. [ ] Submit turn (process commands)
9. [ ] Verify command executed in next turn

**ROE Change Workflow:**
1. [ ] Select fleet in list
2. [ ] Press `Enter` → Open modal
3. [ ] Press `R` → Open ROE picker
4. [ ] Set ROE to 3 (Cautious)
5. [ ] Press `Enter` → Confirm
6. [ ] Verify modal closes
7. [ ] Reopen modal → Verify ROE 3 in header

### 6. Edge Cases

**Empty or Small Fleets:**
- [ ] Test with 1-ship fleet → Modal renders correctly
- [ ] Test with 20+ ship fleet → Ship list scrollable

**Rapid Key Presses:**
- [ ] Mash `Tab` rapidly → No crashes, navigation stable
- [ ] Alternate `↑`/`↓` rapidly → No crashes, bounds respected
- [ ] Press `Esc` multiple times → Modal closes cleanly

**Multiple Fleets:**
- [ ] Stage command on Fleet 1
- [ ] Stage command on Fleet 2
- [ ] Verify both show `●` indicator
- [ ] Submit turn → Both commands execute

**Modal State Persistence:**
- [ ] Open modal on Fleet 1
- [ ] Navigate to Combat category
- [ ] Press `Esc` to close
- [ ] Reopen modal → Verify resets to default state (not Combat)

### 7. Visual Verification

**Layout:**
- [ ] Verify systems list is 30% width (left column)
- [ ] Verify fleet list is 70% width (right column)
- [ ] Verify fleet list uses full vertical height (no bottom pane)
- [ ] Verify modal appears centered on screen
- [ ] Verify modal has proper borders and title

**Styling:**
- [ ] Selected category highlighted in command picker
- [ ] Selected command highlighted in command list
- [ ] Current ROE value highlighted in slider
- [ ] Staged command indicator (`●`) visible and distinct

**Small Terminal:**
- [ ] Resize terminal to 80x24
- [ ] Verify modal still readable
- [ ] Verify no text cutoff or overlap

## Known Limitations (Phase 1)

✓ **Target selection not implemented** - Move, Patrol, etc. stage without target  
✓ **Command filtering not active** - All commands visible regardless of fleet composition  
✓ **No zero-turn commands** - Detach/Transfer/Merge not in Phase 1  
✓ **Ship selection UI** - Multi-select with checkboxes deferred to Phase 2

## Reporting Issues

When reporting bugs, include:
1. Step-by-step reproduction
2. Expected behavior vs actual behavior
3. Terminal size (width x height)
4. Fleet composition (ship types, count)
5. Any error messages or crashes

## Quick Reference: Key Bindings

**Fleet List:**
- `Enter` - Open fleet detail modal

**Fleet Detail Modal:**
- `C` - Open command picker
- `R` - Open ROE picker
- `Esc` - Close modal

**Command Picker:**
- `Tab` / `Shift+Tab` - Navigate categories
- `↑` / `↓` - Navigate commands
- `Enter` - Select command
- `Esc` - Cancel

**ROE Picker:**
- `↑` / `↓` - Adjust ROE (0-10)
- `Enter` - Confirm ROE
- `Esc` - Cancel

**Confirmation Dialog:**
- `Y` - Confirm action
- `N` - Cancel action
