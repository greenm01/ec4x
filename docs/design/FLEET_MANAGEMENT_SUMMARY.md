# Fleet Management System - Design Summary

## Overview

This document summarizes the EC4X fleet management design, addressing the original Esterian Conquest's micromanagement pain points with a modern TUI-based approach optimized for keyboard shortcuts and efficient command.

## Problem Analysis: Original EC (1992)

### Pain Points Identified

1. **15 Mission Types** - Manual assignment per fleet with complex requirements:
   - 00: Hold Position
   - 01: Move Fleet
   - 02: Seek Home
   - 03-08: Combat missions (Patrol, Guard, Blockade, Bombard, Invade, Blitz)
   - 09-11: Espionage missions (Spy Planet/System, Hack Starbase)
   - 12: Colonize
   - 13-14: Join/Rendezvous
   - 15: Salvage

2. **Menu Hell** - Nested DOS menu structure:
   ```
   MAIN MENU
     → PLANET COMMAND
         → BUILD
             → Commission Ships
                 → FLEET COMMAND
                     → Assign Orders
   ```

3. **Manual Pipeline** - Build → Commission → Deploy requires 5-7 menu operations

4. **ROE Micromanagement** - Set Rules of Engagement (0-10) per fleet manually

5. **Late-Game Fleet Explosion** - 20+ fleets × 15 mission types = overwhelming

6. **Army Logistics** - Manual load/unload of marines onto transports

7. **Fleet Coordination** - No batch operations, each fleet managed individually

## Solution: EC4X TUI Fleet Management

### Core Design Principles

1. **Hierarchy-Aware**: Fleet → Squadron → Ship (not flat like original EC)
2. **Keyboard-First**: Single-key shortcuts for 90% of operations
3. **Context-Sensitive**: Only show applicable orders based on fleet composition
4. **Batch-Capable**: Mark multiple fleets and apply same operation
5. **Visual Scanning**: Icons and status indicators for quick assessment
6. **Smart Defaults**: Learn from player patterns and suggest common actions

### Architecture

#### Type Hierarchy
```nim
Ship (Basic M1)
  shipType: ShipType      # Military or Spacelift
  isCrippled: bool

EnhancedShip (M2+)
  shipClass: ShipClass    # Destroyer, Cruiser, Battleship, etc.
  shipType: ShipType
  stats: ShipStats        # AS, DS, CC, CR, tech, costs
  isCrippled: bool
  name: string            # Optional ship name

Squadron (M2+)
  id: SquadronId
  flagship: EnhancedShip
  ships: seq[EnhancedShip]
  owner: HouseId
  location: SystemId

Fleet (M1 simple, M2+ with squadrons)
  id: FleetId
  squadrons: seq[Squadron]  # M2+: Was seq[Ship] in M1
  location: SystemId
  owner: HouseId
  orders: FleetOrders
  roe: int                  # 0-10
```

#### Squadron Mechanics
- **Flagship**: Has Command Rating (CR)
- **Ships**: Each has Command Cost (CC)
- **Constraint**: Sum of ship CC ≤ Flagship CR
- **Combat**: Squadron fights as unit with combined AS/DS
- **Destruction**: If flagship destroyed, squadron is destroyed

#### Ship Classes
Implemented 15 ship classes with varying capabilities:
- **Combat**: Fighter, Scout, Raider, Destroyer, Cruiser, Battlecruiser, Battleship, Dreadnought
- **Special**: Carrier, Super Carrier, Starbase, Planet-Breaker
- **Support**: ETAC, Troop Transport, Ground Battery

Each class has:
- Attack Strength (AS)
- Defense Strength (DS)
- Command Cost (CC) - for squadron assignment
- Command Rating (CR) - for flagships
- Special capabilities (ELI, CLK, CAR, etc.)
- Build/upkeep costs

### TUI Interface

#### Main Screen Layout
```
┌─ EC4X Fleet Command ───────────────────────────────────────────┐
│ ┌─ Systems ──────┐  ┌─ Fleets at System ────────────────────┐ │
│ │ > Caladan [H]   │  │ > Alpha Fleet  [12sq] PATROL    ◯    │ │
│ │   Arrakis [★★] │  │   Beta Fleet   [8sq]  HOLD      ⚠    │ │
│ └─────────────────┘  └───────────────────────────────────────┘ │
│ ┌─ Selected Fleet Details ──────────────────────────────────┐  │
│ │ Squadron         Ships AS/DS  Status   Flagship           │  │
│ │ > Strike-1       8M    48/32  Ready    [BC] Imperial Hand │  │
│ │   Raiders-2      4RR   32/16  Cloaked  [RR] Silent Death  │  │
│ └────────────────────────────────────────────────────────────┘  │
│ [F1]Help [O]rders [R]OE [M]erge [X]fer [Q]uadrons            │
└────────────────────────────────────────────────────────────────┘
```

#### Status Icons
- `[H]` - Homeworld
- `[★★]` - Starbases present
- `[!!!]` - Hostiles present
- `◯` - All healthy
- `⚠` - Some damage
- `◉` - In combat
- `→` - Moving
- `👁` - Cloaked

### Keyboard Shortcuts

#### Navigation (Always Available)
- `↑/↓` - Navigate lists
- `←/→` - Switch panels
- `Tab` - Cycle focus
- `Enter` - Select/drill down
- `Esc` - Back/cancel
- `q` - Quit

#### Views
- `F` - Fleet list
- `S` - System list
- `Q` - Squadron details
- `Ctrl+S` - Strategic overview

#### Fleet Operations
- `n` - New fleet (at system)
- `N` - New squadron (in fleet)
- `m` - Merge fleets
- `p` - Split fleet
- `x` - Transfer squadrons
- `d` - Disband

#### Orders (O key → submenu)
```
┌─ Fleet Orders ────────────────────┐
│ 0  Hold Position                  │
│ 1  Move Fleet                     │
│ 2  Seek Home                      │
│ 3  Patrol System                  │
│ 4  Guard Starbase                 │
│ 5  Guard/Blockade Planet          │
│ 6  Bombard Planet                 │
│ 7  Invade Planet     [needs TRP]  │
│ 8  Blitz Planet      [needs TRP]  │
│ 9  Spy on Planet     [needs SC]   │
│ a  Hack Starbase     [needs SC]   │
│ b  Spy on System     [needs SC]   │
│ c  Colonize          [needs ETAC] │
│ j  Join Fleet                     │
│ r  Rendezvous                     │
│ s  Salvage                        │
└───────────────────────────────────┘
```

Context-sensitive: Greyed out options require specific ship types.

#### ROE (R key)
```
┌─ Rules of Engagement ─────────┐
│ 0  Avoid all hostile forces   │
│ 1  Engage defenseless only    │
│ 2  Engage if 4:1 advantage    │
│ 3  Engage if 3:1 advantage    │
│ 4  Engage if 2:1 advantage    │
│ 5  Engage if 3:2 advantage    │
│ 6  Engage equal/inferior      │
│ 7  Engage even if 3:2 outgun  │ ← Current
│ 8  Engage even if 2:1 outgun  │
│ 9  Engage even if 3:1 outgun  │
│ x  Engage regardless of size  │
└───────────────────────────────┘
```

One-key selection updates immediately.

### Advanced Features

#### 1. Fleet Templates
Save common fleet compositions:
- **Strike Group**: 3× Battlecruiser squadrons, 1× Raider squadron
- **Patrol Group**: 2× Cruiser squadrons, 1× Scout squadron
- **Invasion Force**: 2× Battleship squadrons, 4× Troop Transports
- **Colonization Fleet**: 1× ETAC, 1× Destroyer escort

Press `T` to apply template during fleet creation.

#### 2. Batch Operations
1. Press `Space` to mark fleets
2. Press `O` for orders
3. Select order → applies to all marked

Visual indicator: `[✓]` prefix on marked fleets

#### 3. Strategic Overview (Ctrl+S)
```
┌─ Strategic Overview ────────────────────────────────────┐
│ System       Fleets  Squadrons  Status  Orders          │
│ Caladan [H]  3       18         ◯       2 Patrol, 1 H  │
│ Arrakis      5       34         ⚠       3 Guard, 2 Pat │
│ Giedi Prime  1       4          →       1 Move → Ix    │
│ Kaitain [HUB]2       12         ◉       2 Combat       │
└─────────────────────────────────────────────────────────┘
```

#### 4. Command Mode (vim-style)
Press `:` for direct commands:
- `:goto arrakis` - Jump to system
- `:fleet alpha-1` - Focus fleet
- `:orders alpha-1 patrol` - Set orders
- `:roe alpha-1 7` - Set ROE
- `:merge alpha-1 beta-1` - Merge fleets

#### 5. Search and Filter
- `/` - Search by name
- `Ctrl+F` - Filter by status (combat, moving, damaged)
- `Ctrl+O` - Filter by orders
- `Ctrl+L` - Filter by location

#### 6. Auto-Assignment
When commissioning ships:
- System suggests squadron based on CR availability
- Shows which flagships have capacity
- One-key accept or manual override

### Comparison Table

| Feature | Original EC | EC4X TUI |
|---------|-------------|----------|
| Navigation | Nested menus (6+ levels) | Single-key shortcuts |
| Orders | Manual per fleet | Batch + templates |
| ROE | Set per fleet, no memory | Smart defaults + history |
| Fleet Management | Flat list | Hierarchical with filters |
| Late-game Scaling | 20+ fleets overwhelming | Strategic overview + filters |
| Ship Commissioning | 5-step pipeline | Auto-suggestion |
| Army Loading | Manual load/unload | Spacelift panel shows status |
| Fleet Coordination | One at a time | Batch operations |

### Key Improvements

1. **2-3× Faster Operations**: Keyboard shortcuts reduce 6-click operations to 1-2 keys
2. **Cognitive Load**: Visual scanning with icons vs. reading text menus
3. **Scalability**: Strategic overview + filters handle 50+ fleets
4. **Context Awareness**: Only show valid orders based on ship composition
5. **Learning**: Templates and defaults adapt to player style
6. **Reversibility**: Most operations confirmable or undoable

## Implementation Roadmap

### M1: Basic Game (Complete)
- ✅ Simple Ship type (Military/Spacelift + crippled flag)
- ✅ Basic Fleet (seq[Ship] + owner + location)
- ✅ Moderator CLI commands
- ✅ JSON persistence

### M2: Squadron System
- [ ] Implement EnhancedShip with ShipClass and stats
- [ ] Implement Squadron with flagship and CR/CC mechanics
- [ ] Update Fleet to use seq[Squadron]
- [ ] Update combat system to use squadron AS/DS totals
- [ ] Add squadron operations (merge, split, reassign)

### M3: Basic TUI
- [ ] Choose TUI library (recommend `illwill`)
- [ ] Implement 3-panel layout (Systems, Fleets, Details)
- [ ] Basic navigation (↑↓←→ Tab Enter Esc)
- [ ] System list view
- [ ] Fleet list view
- [ ] Squadron detail view

### M4: Orders and Operations
- [ ] Order assignment menu (O key)
- [ ] ROE picker (R key)
- [ ] Context-sensitive order validation
- [ ] Fleet merge/split/transfer
- [ ] Squadron reassignment

### M5: Advanced Features
- [ ] Fleet templates (save/load)
- [ ] Batch operations (mark + apply)
- [ ] Strategic overview (Ctrl+S)
- [ ] Command mode (`:` commands)
- [ ] Search/filter (/, Ctrl+F/O/L)
- [ ] Status icons and indicators

### M6: Polish
- [ ] Auto-assignment suggestions
- [ ] Smart defaults and history
- [ ] Help system (F1)
- [ ] Keyboard shortcuts reference
- [ ] Color themes
- [ ] Error handling and validation

### M7: Integration
- [ ] Connect to turn resolution system
- [ ] Connect to order submission (TOML)
- [ ] Connect to results display
- [ ] Save UI state and preferences

### M8: Testing and Balance
- [ ] Playtest with 4-6 players
- [ ] Balance ship stats
- [ ] Tune CC/CR values
- [ ] Optimize late-game performance
- [ ] User feedback iteration

## Technical Details

### Files Created
1. **docs/design/FLEET_MANAGEMENT_TUI.md** - Full TUI design specification
2. **src/engine/squadron.nim** - Squadron implementation with ship classes
3. **docs/design/FLEET_MANAGEMENT_SUMMARY.md** - This summary
4. **docs/design/CONFIG_SYSTEM.md** - Configuration system design (M3)

### Squadron Module Features
- 15 ship classes defined (Fighter to Planet-Breaker)
- Stats system (AS, DS, CC, CR, tech, costs)
- Squadron construction and operations
- CR/CC validation and capacity checking
- Combat strength calculations
- Special capabilities (ELI, CLK, CAR, etc.)
- Crippling and destruction mechanics
- M2: Hardcoded defaults (temporary)
- M3: Will migrate to TOML config files (see CONFIG_SYSTEM.md)

### Next Steps
1. **Test squadron module**: Write tests for CR/CC mechanics
2. **Update Fleet type**: Migrate from seq[Ship] to seq[Squadron]
3. **Choose TUI library**: Evaluate `illwill` vs alternatives
4. **Prototype basic TUI**: Implement 3-panel layout with mock data
5. **Connect to gamestate**: Integrate squadron system into turn resolution

## Open Questions

1. **Tech Progression**: How do ship stats scale with tech levels?
2. **Squadron Limits**: Should there be max squadrons per fleet for UI reasons?
3. **Fighter Squadrons**: They're planet-based. Separate UI panel or include in system view?
4. **Spacelift Representation**: Inline with squadrons or separate panel?
5. **Auto-Engagement**: Should fleets auto-engage based on ROE without explicit patrol orders?
6. **Formation Roles**: Implement in M2 or defer to M5?

## Conclusion

The EC4X fleet management system addresses all major pain points from the original Esterian Conquest while preserving the strategic depth of the 15 mission types and ROE system. The TUI design prioritizes keyboard efficiency, visual scanning, and scalability to handle late-game complexity.

Key innovations:
- **Squadron hierarchy** provides tactical depth
- **Context-aware menus** reduce invalid options
- **Batch operations** eliminate repetitive tasks
- **Strategic overview** manages late-game fleet explosions
- **Templates and defaults** speed common operations

The implementation is split across 8 milestones, with M1 complete and M2 (squadron system) ready to begin.
