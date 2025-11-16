# Fleet Management TUI Design

## Design Goals

1. **Reduce Micromanagement**: Avoid the original EC's 15-mission-type complexity and manual coordination overhead
2. **Keyboard-Driven**: Fast navigation and commands via single-key shortcuts
3. **Squadron-Aware**: Properly implement Fleet → Squadron → Ship hierarchy
4. **Scalable**: Handle late-game with 20+ fleets without overwhelming the player
5. **Context-Aware**: Show relevant actions based on current selection and game state

## Hierarchy Implementation

### Current State (M1 Stub)
```nim
Ship = object
  shipType: ShipType  # Military or Spacelift
  isCrippled: bool

Fleet = object
  id: FleetId
  ships: seq[Ship]
  owner: HouseId
  location: SystemId
```

### Proposed State (M2+)
```nim
Ship = object
  shipType: ShipType
  shipClass: ShipClass      # Destroyer, Cruiser, Battleship, etc.
  isCrippled: bool
  commandCost: int          # CC for squadron assignment

Squadron = object
  id: SquadronId
  flagship: Ship
  ships: seq[Ship]          # Excludes flagship
  commandRating: int        # Flagship's CR
  location: SystemId
  owner: HouseId

Fleet = object
  id: FleetId
  squadrons: seq[Squadron]  # Changed from seq[Ship]
  location: SystemId
  owner: HouseId
  orders: FleetOrders       # Mission + destination
  roe: int                  # 0-10 Rules of Engagement
```

## TUI Layout

### Main Fleet Management Screen

```
┌─ EC4X Fleet Command ─ Turn 12 ─ House Atreides ──────────────────────┐
│                                                                        │
│ ┌─ Systems (5) ─────────┐  ┌─ Fleets at Arrakis (3) ─────────────┐  │
│ │ > Caladan      [HOME]  │  │ > Alpha Fleet     [12 sq]  PATROL   │  │
│ │   Arrakis      [★★★]   │  │   Beta Fleet      [8 sq]   HOLD     │  │
│ │   Giedi Prime  [!!!]   │  │   Gamma Fleet     [4 sq]   MOVE→GP  │  │
│ │   Kaitain      [HUB]   │  │                                      │  │
│ │   Ix           [○○○]   │  │ Total: 24 squadrons, 156 ships      │  │
│ └────────────────────────┘  └──────────────────────────────────────┘  │
│                                                                        │
│ ┌─ Alpha Fleet Details ──────────────────────────────────────────────┐│
│ │ Location: Arrakis        Orders: PATROL (03)      ROE: 7          ││
│ │                                                                    ││
│ │ Squadron            Ships  AS/DS  Status    Flagship              ││
│ │ > Strike Alpha-1    8M     48/32  Ready     [BC] Imperial Hand    ││
│ │   Strike Alpha-2    6M     36/24  Ready     [CR] Righteous Dawn   ││
│ │   Scout Alpha-3     2SC    2/4    Ready     [SC] Shadow Eye       ││
│ │   Raiders Alpha-4   4RR    32/16  Cloaked   [RR] Silent Death     ││
│ │   Screen Alpha-5    6M     36/24  Ready     [DD] Fast Strike      ││
│ │                                                                    ││
│ │ Spacelift Command:  2 ETAC, 4 Troop Transports (8 MD loaded)      ││
│ └────────────────────────────────────────────────────────────────────┘│
│                                                                        │
│ [F1]Help [F]leets [S]ystems [Q]uadrons [O]rders [R]OE [M]erge [X]fer │
└────────────────────────────────────────────────────────────────────────┘
```

### Key UI Elements

#### System List (Left Panel)
- Shows all known systems
- `[HOME]` = Player homeworld
- `[HUB]` = Central hub system
- `[★★★]` = Starbase count
- `[!!!]` = Hostile forces present
- `[○○○]` = Friendly colony

#### Fleet List (Top Right Panel)
- Shows fleets at selected system
- Squadron count + current orders
- Summary statistics

#### Fleet Details (Bottom Panel)
- Squadron-level view
- Ship composition and status
- Spacelift Command (non-combat ships)
- Current orders and ROE

## Keyboard Shortcuts

### Navigation
| Key | Action |
|-----|--------|
| `↑/↓` | Navigate lists |
| `←/→` | Switch between panels (Systems ↔ Fleets ↔ Squadrons) |
| `Tab` | Cycle focus through panels |
| `Enter` | Drill down / Select |
| `Esc` | Back / Cancel |
| `q` | Quit |

### Fleet Management
| Key | Action | Context |
|-----|--------|---------|
| `F` | Fleet list view | Global |
| `S` | System list view | Global |
| `Q` | Squadron detail view | Fleet selected |
| `n` | New fleet | System selected |
| `N` | New squadron | Fleet selected |

### Orders (O key → submenu)
| Key | Order | Requirements |
|-----|-------|--------------|
| `0` | Hold Position | None |
| `1` | Move Fleet | Pick destination |
| `2` | Seek Home | None |
| `3` | Patrol System | None |
| `4` | Guard Starbase | Combat ships |
| `5` | Guard/Blockade | Combat ships |
| `6` | Bombard | Combat ships |
| `7` | Invade | Combat + loaded transports |
| `8` | Blitz | Loaded transports |
| `9` | Spy Planet | Solo scout |
| `a` | Hack Starbase | Solo scout |
| `b` | Spy System | Solo scout |
| `c` | Colonize | ETAC |
| `j` | Join Fleet | Pick target fleet |
| `r` | Rendezvous | Pick destination |
| `s` | Salvage | Friendly system |

### ROE (R key)
- Opens quick picker: `0-9` + `x` for 10
- Shows current ROE with highlighting
- One-key selection

### Fleet Operations
| Key | Action | Context |
|-----|--------|---------|
| `m` | Merge fleets | Multiple fleets in system |
| `p` | Split fleet | Fleet selected |
| `x` | Transfer squadrons | Fleet selected |
| `d` | Disband fleet | Fleet selected |

### Squadron Operations (Q detail view)
| Key | Action | Context |
|-----|--------|---------|
| `x` | Transfer to another fleet | Squadron selected |
| `r` | Reassign ships | Non-hostile system |
| `s` | Split squadron | Squadron selected |
| `d` | Disband squadron | Non-hostile system |

## Advanced Features to Reduce Micromanagement

### 1. Fleet Templates
Save common fleet compositions as templates:
- Strike Group (heavy combat)
- Patrol Group (mixed)
- Invasion Force (combat + transports)
- Colonization Fleet (ETAC + escort)
- Scout Mission (solo scout)

**Shortcut**: `T` key to apply template

### 2. Squadron Auto-Assignment
When commissioning new ships, suggest squadron assignment based on:
- Command Rating availability
- Ship class compatibility
- Current fleet composition

**Shortcut**: `a` key to auto-assign during commissioning

### 3. Batch Orders
Apply same orders to multiple fleets:
1. Mark fleets with `Space`
2. Press `O` for orders menu
3. Select order applies to all marked

**Visual**: `[✓]` prefix for marked fleets

### 4. Smart Defaults
- New fleets default to previous fleet's ROE at that system
- Patrol orders default to current system
- Move orders remember last 5 destinations per fleet

### 5. Fleet Status Icons
Quick visual indicators:
- `[→]` Moving
- `[◉]` In combat
- `[⚠]` Damaged ships
- `[◐]` Mixed condition
- `[◯]` All healthy
- `[👁]` Cloaked

### 6. System Overview Mode
Press `Ctrl+S` for strategic overview:
```
┌─ Strategic Overview ────────────────────────────────────────────┐
│ System          Fleets  Squadrons  Status    Orders Summary     │
│ > Caladan [H]   3       18         ◯         2 Patrol, 1 Hold   │
│   Arrakis       5       34         ⚠         3 Guard, 2 Patrol  │
│   Giedi Prime   1       4          →         1 Moving to Ix     │
│   Kaitain [HUB] 2       12         ◉         2 Combat           │
│   Ix            0       0          -         -                  │
└─────────────────────────────────────────────────────────────────┘
```

### 7. Quick Commands
Press `:` for vim-style command mode:
- `:goto <system>` - Jump to system view
- `:fleet <id>` - Focus specific fleet
- `:orders <fleet> <order> <dest>` - Set orders directly
- `:roe <fleet> <0-10>` - Set ROE directly
- `:merge <fleet1> <fleet2>` - Merge fleets
- `:split <fleet> <squadrons>` - Split fleet

### 8. Filters and Search
- `/` - Search systems, fleets, squadrons
- `Ctrl+F` - Filter by status (combat, moving, damaged, etc.)
- `Ctrl+O` - Filter by orders type
- `Ctrl+L` - Filter by location

## Comparison: Original EC vs EC4X

### Original EC Pain Points
| Problem | EC Approach | EC4X Solution |
|---------|-------------|---------------|
| 15 mission types | Manual selection per fleet | Context-aware order menu |
| Fleet explosion | Manage each individually | Batch operations + filters |
| ROE micromanagement | Set per fleet manually | Templates + smart defaults |
| Menu diving | Nested DOS menus | Single-key shortcuts |
| Build-commission-deploy | 3-step manual process | Auto-assign suggestions |
| Army loading | Manual load/unload | Spacelift panel shows status |
| Coordination | Manual across fleets | Batch marking + orders |

### Key Improvements
1. **Context Filtering**: Only show applicable orders based on fleet composition
2. **Visual Scanning**: Icons and status let you see fleet state at a glance
3. **Keyboard Speed**: Most operations are 1-2 keypresses
4. **Batch Operations**: Mark multiple fleets and apply same action
5. **Templates**: Save and reuse common fleet compositions
6. **Smart Defaults**: Learn from player's patterns

## Implementation Phases

### M2: Basic TUI
- [ ] Implement Squadron type in fleet.nim
- [ ] Create TUI framework (consider `illwill` or `nimwave`)
- [ ] System list view
- [ ] Fleet list view
- [ ] Basic navigation (↑↓←→)

### M3: Fleet Operations
- [ ] Squadron detail view
- [ ] Order assignment (O key menu)
- [ ] ROE assignment (R key picker)
- [ ] Fleet merge/split
- [ ] Squadron transfer

### M4: Advanced Features
- [ ] Fleet templates
- [ ] Batch operations
- [ ] Smart defaults
- [ ] Strategic overview mode
- [ ] Command mode (`:` commands)
- [ ] Search and filters

### M5: Polish
- [ ] Status icons and visual indicators
- [ ] Help system (F1)
- [ ] Keyboard shortcuts reference
- [ ] Color themes
- [ ] Mouse support (optional)

## Technical Considerations

### TUI Libraries for Nim
- **illwill**: Lightweight, good for basic TUI
- **nimwave**: More full-featured, complex
- **termstyle**: Basic colors/styles only
- **Custom**: Direct escape codes (most control)

**Recommendation**: Start with `illwill` for M2, evaluate if more features needed

### State Management
Use TEA pattern already planned:
```nim
type
  FleetView = enum
    fvSystemList,
    fvFleetList,
    fvSquadronDetail,
    fvStrategicOverview

  FleetUIState = object
    view: FleetView
    selectedSystem: Option[SystemId]
    selectedFleet: Option[FleetId]
    selectedSquadron: Option[SquadronId]
    markedFleets: seq[FleetId]
    filter: Option[FleetFilter]
    searchQuery: string

  FleetUIMsg = enum
    muNavigateUp,
    muNavigateDown,
    muSelectSystem,
    muSelectFleet,
    muOpenOrderMenu,
    muSetOrder,
    # ... etc
```

### Performance
For 20+ fleets × 5-10 squadrons each = ~100-200 squadrons:
- Render only visible rows (virtual scrolling)
- Cache fleet/squadron aggregations
- Update UI incrementally on state changes

### Persistence
Save UI preferences:
- Last selected system
- Favorite systems (hotkeys 1-9?)
- ROE defaults per system
- Fleet templates

## Future Enhancements (Post-M5)

1. **Fleet Formations**: Assign squadrons to formation roles (vanguard, main, reserve)
2. **Waypoint Paths**: Set multi-system movement paths
3. **Conditional Orders**: "If hostile, retreat to X"
4. **Patrol Routes**: Define patrol circuits between systems
5. **Fleet Doctrine**: House-wide defaults for ROE, auto-engagement rules
6. **AI Suggestions**: "Recommended: Reinforce Arrakis with 2 squadrons"
7. **Combat Replay**: Review past combat with TUI visualization
8. **Fleet History**: Track movement and combat history per fleet

## Open Questions

1. **Ship Classes**: Need to define full ship class list (Destroyer, Cruiser, Battleship, Carrier, etc.)
2. **Command Rating Formula**: How to calculate flagship CR? Tech-dependent?
3. **Squadron Limits**: Max squadrons per fleet? (spec says unlimited, but UI limits?)
4. **Auto-Patrol**: Should fleets auto-engage based on ROE without explicit orders?
5. **Spacelift Display**: Show in separate panel or inline with squadrons?
6. **Fighter Squadrons**: They're planet-based, not fleet-based. Separate view?

## Notes

- Keep the 15 original order types from spec for backward compatibility with EC gameplay
- TUI must work in 80×24 terminal minimum (expand if available)
- Support SSH play (no mouse required)
- Color should enhance, not be required (monochrome fallback)
- All operations must be reversible or confirmable
