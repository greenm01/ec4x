# EC4X Fleet Management - Quick Reference

## Keyboard Shortcuts

### Navigation
```
↑/↓       Navigate lists
←/→       Switch panels
Tab       Cycle focus
Enter     Select / Drill down
Esc       Back / Cancel
q         Quit
```

### Views
```
F         Fleet list
S         System list
Q         Squadron details
Ctrl+S    Strategic overview
```

### Fleet Operations
```
n         New fleet
N         New squadron
m         Merge fleets
p         Split fleet
x         Transfer squadrons
d         Disband
Space     Mark for batch operations
```

### Orders (press O)
```
0   Hold Position
1   Move Fleet
2   Seek Home
3   Patrol System
4   Guard Starbase
5   Guard/Blockade Planet
6   Bombard Planet
7   Invade Planet
8   Blitz Planet
9   Spy on Planet
a   Hack Starbase
b   Spy on System
c   Colonize
j   Join Fleet
r   Rendezvous
s   Salvage
```

### ROE (press R)
```
0   Avoid all
1   Engage defenseless only
2   Engage if 4:1 advantage
3   Engage if 3:1 advantage
4   Engage if 2:1 advantage
5   Engage if 3:2 advantage
6   Engage equal/inferior
7   Engage even if 3:2 outgunned
8   Engage even if 2:1 outgunned
9   Engage even if 3:1 outgunned
x   Engage regardless
```

### Advanced
```
T         Apply fleet template
:         Command mode (vim-style)
/         Search
Ctrl+F    Filter by status
Ctrl+O    Filter by orders
Ctrl+L    Filter by location
F1        Help
```

## Command Mode Examples
```
:goto arrakis              Jump to system
:fleet alpha-1             Focus fleet
:orders alpha-1 patrol     Set orders
:roe alpha-1 7             Set ROE
:merge alpha-1 beta-1      Merge fleets
:split alpha-1 strike-1    Split squadron from fleet
```

## Status Icons
```
[H]    Homeworld
[HUB]  Central hub
[★★]   Starbases present
[!!!]  Hostile forces
[○○]   Friendly colony
◯      All healthy
⚠      Some damage
◉      In combat
→      Moving
👁      Cloaked
```

## Ship Classes
```
Combat:
  Fighter (F)           AS:1   DS:1   CC:0   Planet-based
  Scout (SC)            AS:1   DS:2   CC:1   ELI capable
  Raider (RR)           AS:4   DS:2   CC:2   Cloaking
  Destroyer (DD)        AS:4   DS:3   CC:2   CR:3
  Cruiser (CR)          AS:6   DS:4   CC:3   CR:5
  Battlecruiser (BC)    AS:8   DS:5   CC:4   CR:7
  Battleship (BS)       AS:10  DS:6   CC:5   CR:9
  Dreadnought (DN)      AS:15  DS:8   CC:7   CR:12

Special:
  Carrier (CV)          AS:2   DS:4   CC:4   Carries 3 FS
  Super Carrier (CX)    AS:3   DS:5   CC:6   Carries 5 FS
  Starbase (SB)         AS:12  DS:10  CC:0   ELI+2, orbital
  Planet-Breaker (PB)   AS:20  DS:6   CC:8   Shield penetration

Support:
  ETAC                  AS:0   DS:2   CC:2   Colonization
  Troop Transport       AS:0   DS:3   CC:2   Carries 1 MD
  Ground Battery (GB)   AS:3   DS:2   CC:0   Planet-based
```

## Squadron Mechanics

### Command Rating (CR) / Command Cost (CC)
- Each flagship has a **Command Rating (CR)**
- Each ship has a **Command Cost (CC)**
- Sum of ship CC must be ≤ Flagship CR

### Example Squadron
```
Flagship: Battlecruiser (CR:7)
  + 2× Destroyer (CC:2 each) = 4
  + 1× Scout (CC:1)          = 1
                     Total CC = 5 ≤ 7 ✓
```

### Combat
- Squadron fights as a unit
- Total AS = Sum of all ship AS (crippled ships: AS/2)
- Total DS = Sum of all ship DS
- If flagship destroyed → squadron destroyed

## Fleet Templates

### Strike Group
```
3× Battlecruiser squadrons (heavy combat)
1× Raider squadron (cloaked ambush)
1× Scout squadron (ELI support)
```

### Patrol Group
```
2× Cruiser squadrons (balanced)
1× Scout squadron (detection)
2× Destroyer squadrons (fast response)
```

### Invasion Force
```
2× Battleship squadrons (orbital superiority)
4× Troop Transports (8 MD total)
1× Destroyer squadron (escort)
```

### Colonization Fleet
```
1× ETAC (colonization)
1× Destroyer squadron (escort)
```

## Batch Operations Workflow

1. Mark fleets with `Space`
   ```
   [✓] Alpha Fleet    [12sq]  PATROL
   [✓] Beta Fleet     [8sq]   HOLD
   [ ] Gamma Fleet    [4sq]   MOVE
   ```

2. Press `O` for orders

3. Select order (e.g., `3` for Patrol)

4. All marked fleets receive order

## Tips

### Reduce Micromanagement
- Use **templates** for common fleet types
- Set **smart defaults** for ROE per system
- Use **batch operations** for multiple fleets
- Enable **auto-assignment** during ship commissioning

### Handle Late-Game Fleet Explosion
- Use **Strategic Overview** (Ctrl+S) to see all at once
- Apply **filters** (Ctrl+F/O/L) to focus on specific fleets
- Use **command mode** (`:`) for direct fleet commands
- Group fleets with **naming conventions** (Alpha-1, Alpha-2, etc.)

### Efficient Keyboard Flow
```
S              → Switch to system list
↓↓↓ Enter     → Select Arrakis
→              → Switch to fleet list
↓ Enter        → Select Alpha Fleet
Q              → Squadron detail view
O              → Orders menu
3              → Patrol
Esc Esc        → Back to system list
```

### Search Shortcuts
```
/alpha         → Find fleets matching "alpha"
Ctrl+F combat  → Filter to fleets in combat
Ctrl+O patrol  → Filter to fleets on patrol
```

## Common Workflows

### Creating a New Fleet
```
S              → System list
↓ Enter        → Select system
n              → New fleet
[Enter fleet composition...]
O → 3          → Set to Patrol
R → 7          → Set ROE to 7
```

### Merging Fleets
```
F              → Fleet list
↓ Enter        → Select first fleet
m              → Merge
↓ Enter        → Select second fleet
Enter          → Confirm merge
```

### Splitting Fleet
```
F              → Fleet list
↓ Enter        → Select fleet
Q              → Squadron view
Space Space    → Mark 2 squadrons
p              → Split marked squadrons to new fleet
```

### Transferring Squadron
```
Q              → Squadron detail view
↓ Enter        → Select squadron
x              → Transfer
↓ Enter        → Select destination fleet
Enter          → Confirm
```

## Implementation Status

### ✅ M1: Complete
- Basic Ship type (Military/Spacelift)
- Basic Fleet (seq[Ship])
- Moderator CLI
- JSON persistence

### 🚧 M2: In Progress
- ✅ Squadron module created (squadron.nim)
- ✅ 15 ship classes defined
- ✅ Stats system (AS, DS, CC, CR)
- ✅ CR/CC validation
- ⏳ Update Fleet to use squadrons
- ⏳ Update combat system
- ⏳ Write tests

### ⏳ M3-M8: Planned
- M3: Basic TUI framework
- M4: Orders and operations
- M5: Advanced features (templates, batch, etc.)
- M6: Polish and help system
- M7: Integration with turn resolution
- M8: Playtesting and balance
