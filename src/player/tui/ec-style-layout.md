# EC4X Player TUI Modernization Spec

## 1. Purpose & Design Pillars

Design a modern text-based interface for EC4X that preserves the classic Esterian Conquest
(EC) atmosphere while delivering contemporary usability, responsiveness, and information
density. The target implementation lives under `src/player/` and drives the player experience
for strategic, planetary, and fleet interactions.

### Design Pillars

1. **Classic Feel, Modern Flow**: Embrace navy-on-black foundations, ANSI accents, and
   minimalist transitions reminiscent of BBS terminals while reducing modal friction through
   flattened navigation and batch operations.

2. **Always-On Awareness**: Present empire-critical data at all times (turn status, idle
   assets, alerts) so players never lose context when drilling into submenus.

3. **Command Fluidity**: Support keyboard-driven hotkeys (digits, letter mnemonics) and
   Expert Mode command palette (`:` prefix) for power users, with inline discoverability for
   newcomers.

4. **Composable Widgets**: Build reusable UI primitives (panels, tickers, card grids, command
   docks) to ensure consistent styling and future expansion (spectator mode, AI playback).

---

## 2. Layout Framework

### Viewport Budget

| Target        | Columns | Rows  | Notes                                    |
|---------------|---------|-------|------------------------------------------|
| **Primary**   | 120     | 32+   | Full information density, ASCII mockups  |
| **Fallback**  | 80      | 24    | Graceful degradation, column stacking    |

**Responsive behavior**: At 80 columns, multi-column layouts stack vertically. Tables truncate
long fields with ellipsis. Status bar items prioritized left-to-right (most critical first).

### Screen Regions

```
+------------------------------------------------------------------------------+
| HUD STRIP (2 lines)                                                          |
|   Left: Empire badge + turn    Center: Treasury/Prod/Dip    Right: Alerts    |
+------------------------------------------------------------------------------+
| BREADCRUMB LINE (1 line)                                                     |
|   Home > Fleets > Alpha Patrol                                               |
+------------------------------------------------------------------------------+
|                                                                              |
| MAIN CANVAS (variable height)                                                |
|   - Swappable panels: Overview, Planets, Fleets, Reports, Messages, Settings |
|   - Double-line borders (══) for primary contexts                            |
|   - Single-line borders (──) for dialogs and overlays                        |
|                                                                              |
+------------------------------------------------------------------------------+
| COMMAND DOCK (2-3 lines)                                                     |
|   Primary: [1] Overview [2] Planets [3] Fleets [4] Reports [5] Msgs [Q] Quit |
|   Context: Dynamic actions based on current view                             |
|   Expert:  `: ` command palette prompt when active                           |
+------------------------------------------------------------------------------+
```

---

## 3. Visual Language

### Classic EC ANSI Palette

| Element           | Foreground  | Background  | ANSI Code   |
|-------------------|-------------|-------------|-------------|
| HUD background    | Amber       | Navy        | 33 on 44    |
| Main canvas       | White/Gray  | Black       | 37/90 on 40 |
| Alert glyph       | Red         | —           | 91          |
| Selected row      | Black       | Cyan        | 30 on 46    |
| Disabled/fog      | Dark gray   | —           | 90          |
| Positive delta    | Green       | —           | 92          |
| Negative delta    | Red         | —           | 91          |

### Borders & Typography

- **Primary panels**: Double-line `═║╔╗╚╝╠╣╦╩╬`
- **Dialogs/overlays**: Single-line `─│┌┐└┘├┤┬┴┼`
- **Subtle grouping**: Dotted `···` or light box `╌`
- **Headings**: ALL CAPS, left-aligned
- **Monospace alignment**: 2-space gutters, 80-char line limit in content

### Glyphs & Icons

| Glyph | Meaning                  |
|-------|--------------------------|
| `●`   | OK / Undamaged           |
| `⚠`   | Needs Attention (idle OR crippled) |
| `RSV` | Reserve status           |
| `MTB` | Mothballed status        |
| `▲▼`  | Trend up/down            |
| `✉`   | Unread message/report    |
| `⌚`   | ETA indicator            |
| `▓░`  | Progress bar             |

---

## 4. Input Model

### Navigation Hierarchy

```
[1-6]           Switch primary views (Overview, Planets, Fleets, Reports, Msgs, Settings)
[Tab/S-Tab]     Cycle focusable widgets within view
[Enter]         Drill into selected item / confirm action
[Backspace]     Step up breadcrumb history
[Esc]           Cancel overlay / exit command mode
[?]             Show context help overlay
```

### Letter Mnemonics (Legacy EC Style)

Within views, single-letter hotkeys trigger common actions:

| Key | Context           | Action                              |
|-----|-------------------|-------------------------------------|
| `M` | Fleet selected    | Move command                        |
| `P` | Fleet selected    | Patrol command                      |
| `H` | Fleet selected    | Hold command                        |
| `G` | Fleet selected    | Guard (colony or starbase)          |
| `R` | Fleet selected    | ROE picker overlay                  |
| `J` | Fleet selected    | Join fleet                          |
| `B` | Colony selected   | Build (construction queue)          |
| `T` | Colony selected   | Tax rate adjustment                 |
| `A` | Any view          | Toggle automation / autopilot       |
| `D` | Reports           | Delete selected report              |
| `X` | Multi-select      | Toggle selection on current row     |

### Expert Mode (Command Palette)

Typing `:` enters command mode. Supports vim-style direct commands:

```
:move alpha B7          Move fleet "alpha" to system B7
:patrol delta           Set fleet "delta" to patrol current system
:tax bigun 55           Set colony "bigun" tax rate to 55%
:roe sigma 8            Set fleet "sigma" ROE to 8
:join alpha beta        Join fleet "alpha" into fleet "beta"
:build bigun cruiser 3  Queue 3 cruisers at colony "bigun"
:reserve omega          Put fleet "omega" into reserve
:mothball gamma         Mothball fleet "gamma"
```

**Tab completion**: Fleet names, colony names, ship types, commands auto-complete.
**History**: Up/down arrows navigate command history.

---

## 5. Primary Views

### 5.1 Strategic Overview (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦   ⚠ 3 Alerts   ✉ 2 New Reports          ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Overview
┌────────────────────────────┬──────────────────────────────────────────┬───────────────────────────────────────────────┐
│ RECENT EVENTS              │ EMPIRE STATUS                            │ ACTION QUEUE                                  │
├────────────────────────────┤                                          │                                               │
│[T42] Fleet Sigma repelled  │  COLONIES          FLEETS                │ ⚠ 1 Idle shipyard at Bigun         [jump 2]   │
│      pirates @ Thera Gate  │  Owned   12  ▲2    Active    8           │ ⚠ 2 Fleets without orders           [jump 3]  │
│[T42] Colony Bigun starbase │  Raw      3  ▬0    Reserve   3           │ ✉ 1 Unread combat report            [jump 4]  │
│      construction complete │  Morale  87%       Mothball  2           │                                               │
│[T41] Scout Lambda spotted  │                                          │ CHECKLIST                                     │
│      warps @ sector 17,5   │  DIPLOMACY         INTEL                 │ ■ Shipyard A at Bigun idle                    │
│[T41] Taxes raised to 58%   │  Treaties   2      Known Systems  44     │ ■ Fleet Omicron awaiting orders               │
│      empire-wide           │  NAPs       1      Fogged         12     │ ■ Fleet Tau awaiting orders                   │
│[T40] Enemy fleet detected  │  Tension ▓▓▓░░░    Scout Missions  3     │ ■ Report: Zeta skirmish (unread)              │
│      approaching Ymir      │                                          │                                               │
└────────────────────────────┴──────────────────────────────────────────┴───────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [1] Overview  [2] Planets  [3] Fleets  [4] Reports  [5] Messages  [6] Settings  [Q] Quit
 [2-4] Jump to checklist item                                                     [: ] Expert Mode
```

**Layout**: Three columns (20% / 40% / 40%)
- **Recent Events**: Rolling log with turn tags, most recent at top
- **Empire Status**: Card grid (Colonies, Fleets, Diplomacy, Intel)
- **Action Queue**: Prioritized list of items needing attention with jump hotkeys

### 5.2 Planet Manager (120 columns)

#### 5.2.1 Planet List View

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ COLONY                SECTOR   CLASS    POP    IU   PROD   TAX   MORALE   FACILITIES          STATUS                 │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Valeria Prime (HW)    A3       Lush     48     52    104   45%   ▓▓▓▓▓▓░  SP SY SY DD DD SB   ●                      │
│ Bigun                 B7       Benign   32     38     76   55%   ▓▓▓▓▓░░  SP SY DD SB         ⚠ Idle shipyard        │
│ Thera Gate            C4       Hostile  18     22     44   40%   ▓▓▓▓░░░  SP SY DD            ●                      │
│ Ymir Relay            D2       Benign   24     28     56   50%   ▓▓▓▓▓░░  SP DD               ⚠ Under blockade       │
│ Nova Station          E9       Lush     28     34     68   50%   ▓▓▓▓▓▓░  SP SY DD            ●                      │
│ Frontier VII          F1       Hostile  12     15     30   35%   ▓▓▓░░░░  SP                  ●                      │
│                                                                                                                      │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
 12 colonies total  |  3 idle facilities  |  640 total production
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] View Colony  [T] Set Tax  [B] Build  [S] Sort  [F] Filter           [: ] Expert Mode
```

**Facility codes**: SP=Spaceport, SY=Shipyard, DD=Drydock, SB=Starbase

#### 5.2.2 Planet Detail View - Summary Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  [Summary]  Economy   Construction   Defense   Settings                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COLONY: Bigun                                                                                                        │
│ Location: Sector B7 (Benign)       Efficiency: 95.9%       Max Prod: 80       Current: 76       Stored: 63 PP        │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SURFACE                                        │ ORBITAL                                                             │
│   Population:  32 PU (1.6M souls)              │   Starbase:    1 (Undamaged)                                        │
│   Armies:      8 divisions                     │   Shipyard:    1 (10 docks)                                         │
│   Marines:     4 divisions                     │   Drydock:     1 (10 repair bays)                                   │
│   Batteries:   6 emplacements                  │   Spaceport:   1 (5 docks)                                          │
│   Shields:     SLD-4 (40% reduction)           │                                                                     │
│                                                │   Docked Fleets:                                                    │
│                                                │     Alpha Patrol (8 ships)                                          │
│                                                │     Supply Wing (3 transports)                                      │
├────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────┤
│ ECONOMY SNAPSHOT                               │ CONSTRUCTION QUEUE                                                  │
│   Tax Rate:   55%                              │   1. Cruiser      ▓▓▓░░ (3/5)   ETA 2 turns                         │
│   Revenue:    42 PP/turn                       │   2. Battleship   ▓░░░░░░ (1/7)   ETA 6 turns                       │
│   Morale:     ▓▓▓▓▓░░ (Stable)                 │   3. Army         DONE - ready to deploy                            │
│   Growth:     +0.8 PU/turn                     │                                                                     │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [B] Build  [T] Tax  [G] Garrison  [Backspace] Back   [: ] Expert Mode
```

#### 5.2.3 Planet Detail View - Economy Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun > Economy
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Summary  [Economy]  Construction   Defense   Settings                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ TAX RATE                                                                                                             │
│                                                                                                                      │
│   Current: 55%    Revenue: 42 PP/turn    Morale Impact: -2%/turn                                                     │
│                                                                                                                      │
│   0%       20%       40%       60%       80%      100%                                                               │
│   ├─────────┼─────────┼─────────┼─────────┼─────────┤                                                                │
│   ░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓█                                                                           │
│                               ▲                                                                                      │
│   [←/→] Adjust    [Enter] Confirm    [Esc] Cancel                                                                    │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ REVENUE FORECAST                               │ MORALE PROJECTION                                                   │
│                                                │                                                                     │
│   Gross Output:     80 PP                      │   Current:    ▓▓▓▓▓░░ 71%                                           │
│   Tax Collection:   44 PP (55%)                │   Next Turn:  ▓▓▓▓▓░░ 69% (▼2%)                                     │
│   Maintenance:      -2 PP                      │   Trend:      Declining (tax > 50%)                                 │
│   Net Revenue:      42 PP                      │                                                                     │
│                                                │   Warning: Morale below 50% triggers unrest                         │
│   If tax = 40%:     32 PP (+0.5% morale)       │                                                                     │
│   If tax = 60%:     48 PP (-3.0% morale)       │                                                                     │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [T] Quick tax input  [Backspace] Back                [: ] Expert Mode
```

#### 5.2.4 Planet Detail View - Construction Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun > Construction
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Summary   Economy  [Construction]  Defense   Settings                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ CONSTRUCTION QUEUE                             │ REPAIR QUEUE                                                        │
│ Shipyard: 7/10 docks in use                    │ Drydock: 2/10 bays in use                                           │
│                                                │                                                                     │
│  #  PROJECT       COST   PROGRESS      ETA     │  #  SHIP            COST   STATUS                                   │
│  1. Cruiser        35    ▓▓▓░░ (3/5)   2 trn   │  1. DD Falcon        8     Repairing (1 turn)                       │
│  2. Battleship     70    ▓░░░░░░ (1/7)   6 trn │  2. CR Hawk         12     Repairing (1 turn)                       │
│  3. Destroyer      20    Queued         3 trn  │                                                                     │
│  4. Destroyer      20    Queued         3 trn  │                                                                     │
│  ─────────────────────────────────────────     │                                                                     │
│  [+] Add project                               │  [+] Add to repair queue                                            │
│                                                │                                                                     │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ AVAILABLE TO BUILD                                                                                                   │
│                                                                                                                      │
│  TYPE           COST   TIME   DOCKS   DESCRIPTION                                                                    │
│  Scout            8     1       1     Reconnaissance vessel, intel missions                                          │
│  Destroyer       20     3       1     Fast escort, anti-fighter                                                      │
│  Cruiser         35     5       2     Balanced warship, patrol duty                                                  │
│  Battleship      70     7       3     Heavy capital ship, fleet actions                                              │
│  Dreadnought    120    10       4     Flagship class, devastating firepower                                          │
│  Troop Transp    25     3       2     Marine carrier, invasion ops                                                   │
│  ETAC            40     4       3     Colony ship, carries PTUs                                                      │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] Build  [D] Delete from queue  [P] Prioritize  [Backspace] Back      [: ] Expert Mode
```

#### 5.2.5 Planet Detail View - Defense Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun > Defense
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Summary   Economy   Construction  [Defense]  Settings                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ORBITAL DEFENSES                               │ PLANETARY DEFENSES                                                  │
│                                                │                                                                     │
│  Starbase                                      │  Shields:    SLD-4 (40% bombardment reduction)                      │
│    Status:   Undamaged                         │  Batteries:  6 emplacements                                         │
│    AS/DS:    40 / 60                           │               AS: 30  DS: 36                                        │
│    Sensors:  +2 detection bonus                │                                                                     │
│                                                │  Ground Forces:                                                     │
│  Guard Fleets:                                 │    Armies:   8 divisions (AS: 16, DS: 24)                           │
│    Alpha Patrol   8 ships   AS: 64   ROE: 6    │    Marines:  4 divisions (AS: 12, DS: 12)                           │
│                                                │                                                                     │
│  Reserve Fleets:                               │  Garrison Strength: 46 AS / 72 DS                                   │
│    Beta Reserve   4 ships   AS: 24   ROE: 8    │                                                                     │
│    (50% effectiveness while in reserve)        │                                                                     │
│                                                │                                                                     │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ DEFENSE ASSESSMENT                                                                                                   │
│                                                                                                                      │
│  Orbital Defense Rating:    ████████░░  Strong (starbase + guard fleet)                                              │
│  Planetary Defense Rating:  ██████░░░░  Moderate (shields + batteries + garrison)                                    │
│  Invasion Resistance:       ██████████  High (+2 DRM prepared defenses)                                              │
│                                                                                                                      │
│  Recommendation: Consider adding 2 more batteries for balanced defense                                               │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [G] Manage garrison  [Backspace] Back                [: ] Expert Mode
```

#### 5.2.6 Planet Detail View - Settings Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun > Settings
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Summary   Economy   Construction   Defense  [Settings]                                                             │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COLONY AUTOMATION                                                                                                    │
│                                                                                                                      │
│  These settings control automatic actions for this colony. Override global defaults.                                 │
│                                                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  SETTING                COLONY VALUE    GLOBAL DEFAULT    DESCRIPTION                                           │ │
│  ├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤ │
│  │  Auto-Repair Ships      [ON ]           ON                Automatically queue crippled ships for repair         │ │
│  │  Auto-Load Marines      [OFF]           ON                Load marines onto docked troop transports             │ │
│  │  Auto-Load Fighters     [ON ]           OFF               Load fighters onto docked carriers                    │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                                                      │
│  [Space] Toggle selected    [R] Reset to global default    [A] Apply to all colonies                                 │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COLONY NOTES                                                                                                         │
│                                                                                                                      │
│  Player notes for this colony (optional):                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│  │ Main shipbuilding hub. Keep 2 cruisers in reserve for emergency response.                                       │ │
│  │ Priority: battleship production until T50.                                                                      │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
│  [E] Edit notes                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [Backspace] Back                                     [: ] Expert Mode
```

### 5.3 Fleet Console (120 columns)

#### 5.3.1 Fleet Console - System View

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640           ⚠ Fleet Omega idle  ⚠ Fleet Tau idle      ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Fleets (System View)
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ [System View]  List View                                                                                             │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SYSTEM: Thera Gate (C4) ─────────────────────────────────────────────────────────────────────────────────────────────│
│                                                                                                                      │
│  ► Fleet Sigma         12 ships    Command: Patrol         ETA: ▓▓▓░░ to D5 (2 turns)                    ● OK        │
│      DD×6  CR×4  BS×2   Morale 82%   ROE: 6                                                                          │
│      Last contact: Enemy scouts detected (Fog 48%)                                                                   │
│                                                                                                                      │
│    Fleet Tau            4 ships    Command: Hold            Status: Idle                                 ⚠ IDLE      │
│    Fleet Omega          8 ships    Command: (none)          Status: Awaiting orders                      ⚠ IDLE      │
│                                                                                                                      │
│ SYSTEM: Ymir Relay (D2) ─────────────────────────────────────────────────────────────────────────────────────────────│
│                                                                                                                      │
│    Fleet Lambda         1 scout    Command: Scout System    ETA: ▓░░░░ to E3 (4 turns)                   ●           │
│    Fleet Petra          5 ships    Command: Colonize        ETA: ▓▓░░░ to F1 (3 turns)                   ●           │
│      TT×3  ETAC×2                                                                                                    │
│                                                                                                                      │
│ SYSTEM: Bigun (B7) ──────────────────────────────────────────────────────────────────────────────────────────────────│
│                                                                                                                      │
│    Fleet Alpha          8 ships    Command: Guard Colony    Status: Docked                               ●           │
│    Fleet Beta           4 ships    Command: Reserve         Status: 50% readiness                        RSV         │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
 13 fleets  |  52 ships  |  2 idle fleets  |  3 in transit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] Fleet Details  [L] List View  [M] Move  [P] Patrol  [H] Hold  [R] ROE  [: ] Expert Mode
```

#### 5.3.2 Fleet Console - List View (Table with Multi-Select)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640           ⚠ Fleet Omega idle  ⚠ Fleet Tau idle      ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Fleets (List View)
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  System View  [List View]                                                                        [X] Multi-select: 2 │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ [ ] FLEET           LOCATION       SHIPS  AS    COMMAND         DESTINATION    ETA    ROE   STATUS                   │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│     Alpha           Bigun (B7)        8    64   Guard Colony    —              —       6    ●                        │
│     Beta            Bigun (B7)        4    24   Reserve         —              —       8    RSV                      │
│ ►►► Sigma           Thera (C4)       12    96   Patrol          D5             2 trn   6    ●                        │
│ [X] Tau             Thera (C4)        4    32   Hold            —              —       6    ⚠ IDLE                   │
│ [X] Omega           Thera (C4)        8    64   (none)          —              —       6    ⚠ IDLE                   │
│     Lambda          Ymir (D2)         1     4   Scout System    E3             4 trn   2    ●                        │
│     Petra           Ymir (D2)         5    20   Colonize        F1             3 trn   6    ●                        │
│     Gamma           Valeria (A3)      6    48   Mothball        —              —       —    MTB                      │
│     Delta           Valeria (A3)      3    18   Patrol          —              —       7    ●                        │
│     Epsilon         Nova (E9)         4    28   Guard Starbase  —              —       8    ●                        │
│     Zeta            Nova (E9)         2    12   Hold            —              —       6    ⚠ CRIPPLED               │
│     Eta             Frontier (F1)     3    16   Patrol          —              —       5    ●                        │
│     Theta           In Transit        7    56   Move            Thera (C4)     1 trn   6    ●                        │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
 13 fleets  |  2 selected  |  Batch: [M] Move  [J] Join  [V] Rendezvous
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [X] Toggle select  [Enter] Fleet Details  [S] Sort  [F] Filter               [: ] Expert Mode
 Multi-select (2): [M] Move all  [J] Join into one  [V] Rendezvous at...
```

**Multi-select rules**:
- `[X]` toggles selection on current row (bounce bar)
- Selected fleets shown with `[X]` prefix
- Current cursor shown with `►►►`
- Batch commands limited to: **Move**, **Join**, **Rendezvous**
- All other commands require single fleet selection

**Status column legend**:
- `●` = OK (Undamaged, has valid command)
- `⚠ IDLE` = Awaiting orders (Hold or no command)
- `⚠ CRIPPLED` = Contains crippled ships needing repair
- `RSV` = Reserve status (50% readiness)
- `MTB` = Mothballed status (offline)

#### 5.3.3 Fleet Details Panel

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Fleets > Sigma
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ FLEET: Sigma                                                                                                         │
│ Location: Thera Gate (C4)          Command: Patrol          Destination: D5          ETA: 2 turns                    │
│ ROE: 6 (Fight if equal or superior)                                                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COMPOSITION                                    │ COMBAT STATS                                                        │
│                                                │                                                                     │
│  SHIP CLASS      QTY   STATUS       AS    DS   │  Total Attack Strength:    96                                       │
│  Destroyer        6    Undamaged    24    18   │  Total Defense Strength:   72                                       │
│  Cruiser          4    Undamaged    32    28   │  Fleet Morale:             82%                                      │
│  Battleship       2    Undamaged    40    26   │                                                                     │
│  ────────────────────────────────────────────  │  Maintenance Cost:         12 PP/turn                               │
│  TOTAL           12                 96    72   │  Command Cost (CC):        8                                        │
│                                                │                                                                     │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COMMAND HISTORY                                │ INTEL                                                               │
│                                                │                                                                     │
│  T42: Patrol to D5 (current)                   │  Last Contact: T41                                                  │
│  T41: Engaged pirates at C4 (victory)          │  Enemy scouts detected at C4                                        │
│  T40: Move from B7 to C4                       │  Fog level: 48% (limited visibility)                                │
│  T39: Guard Colony at Bigun                    │                                                                     │
│                                                │  Nearby threats: Unknown fleet at D6 (suspected)                    │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [M] Move  [P] Patrol  [H] Hold  [G] Guard  [R] ROE  [J] Join  [D] Detach ships  [Backspace] Back  [: ] Expert Mode
```

### 5.4 Reports Inbox (120 columns)

Email-style 3-column layout with folder/category sidebar, report list, and preview pane.

#### 5.4.1 Reports Inbox - Main View

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦              ✉ 3 Unread Reports         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Reports
┌───────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ CATEGORIES    │ REPORTS                                                                                   [F] Filter │
├───────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────┤
│               │                                                                                                      │
│  All (15)     │  ✉ TURN  CATEGORY      SUBJECT                                              DATE                     │
│  ────────     │  ──────────────────────────────────────────────────────────────────────────────────────────────────  │
│  Turn Sum (1) │  ✉  42   Turn Summary  Turn 42 Summary - 3 events, 2 alerts                 Today                    │
│  Combat   (2) │  ✉  42   Combat        Victory at Thera Gate - Fleet Sigma                  Today                    │
│  Intel    (3) │  ✉  42   Intel         Scout Report: Enemy fleet detected at D6             Today                    │
│  Construct(4) │     42   Construction  Starbase completed at Bigun                          Today                    │
│  Colony   (2) │     41   Combat        Skirmish at Ymir - Fleet Zeta damaged                Yesterday                │
│  Diplomacy(1) │     41   Intel         Recon Report: System E3 surveyed                     Yesterday                │
│  Alerts   (2) │     41   Colony        Population growth at Nova Station (+2 PU)            Yesterday                │
│               │     40   Construction  Cruiser commissioned at Valeria Prime                2 days ago               │
│  ────────     │     40   Diplomacy     House Stratos proposes trade agreement               2 days ago               │
│  Archive  (8) │     40   Alert         Fleet Omega low on fuel - requires attention         2 days ago               │
│               │     39   Intel         Scout mission failed at F4                           3 days ago               │
│               │     39   Construction  Battleship commissioned at Bigun                     3 days ago               │
│               │                                                                                                      │
│               │                                                                                                      │
│               │                                                                                                      │
└───────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────┘
 15 reports  |  3 unread  |  Filter: All
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] View Report  [D] Delete  [A] Archive  [M] Mark read/unread            [: ] Expert Mode
```

**Category sidebar**:
- Turn Summary - Auto-generated each turn (auto-opens on new turn)
- Combat - Battle reports, skirmishes
- Intel - Scout reports, recon data
- Construction - Build completions, repairs
- Colony - Population, morale, economic events
- Diplomacy - Treaties, proposals, violations
- Alerts - Items requiring attention
- Archive - Manually archived reports

**Report lifecycle**:
- Reports kept forever until manually deleted or archived
- Unread reports marked with `✉`
- Turn Summary auto-opens when player first views Reports on a new turn

#### 5.4.2 Turn Summary Report (Auto-opens on new turn)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Reports > Turn 42 Summary
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ TURN 42 SUMMARY                                                                          Generated: 2342.042.1800 UTC│
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ EMPIRE OVERVIEW                                                                                                      │
│                                                                                                                      │
│  Colonies: 12 (+2)      Treasury: 1,820 PP (+142)     Prestige: 487 (+12)     Standing: 2nd of 6                     │
│  Fleets:   13           Production: 640 PP/turn       Morale: Good                                                   │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ KEY EVENTS THIS TURN                                                                                                 │
│                                                                                                                      │
│  COMBAT                                                                                                              │
│    ● Victory at Thera Gate - Fleet Sigma repelled pirate raiders                              [View Full Report]     │
│    ● Skirmish at Ymir Relay - Fleet Zeta took damage, enemy retreated                         [View Full Report]     │
│                                                                                                                      │
│  CONSTRUCTION                                                                                                        │
│    ● Starbase completed at Bigun                                                                                     │
│    ● Cruiser "Hawk" commissioned at Valeria Prime                                                                    │
│                                                                                                                      │
│  INTEL                                                                                                               │
│    ● Scout Lambda detected enemy fleet massing at D6 (est. 8-12 ships)                        [View Full Report]     │
│    ● System E3 surveyed: Benign planet, suitable for colonization                                                    │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ACTION REQUIRED                                                                                                      │
│                                                                                                                      │
│  ⚠ 2 fleets awaiting orders (Tau, Omega)                                              [Jump to Fleet Console]        │
│  ⚠ 1 idle shipyard at Bigun                                                           [Jump to Colony]               │
│  ⚠ Fleet Zeta has crippled ships - consider repair orders                             [Jump to Fleet Details]        │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [1-3] Jump to action item  [N] Next unread report  [Backspace] Back to inbox               [: ] Expert Mode
```

#### 5.4.3 Combat Report Detail

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Reports > Combat Report: Victory at Thera Gate
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ COMBAT REPORT: Victory at Thera Gate                                                         Turn 42 - Space Combat  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ENGAGEMENT SUMMARY                                                                                                   │
│                                                                                                                      │
│  Location:    Thera Gate (C4)                                                                                        │
│  Date:        Turn 42, Phase 3 (Combat Resolution)                                                                   │
│  Result:      VICTORY - Enemy forces destroyed                                                                       │
│  Prestige:    +8 (combat victory)                                                                                    │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ FORCES ENGAGED                                                                                                       │
│                                                                                                                      │
│  YOUR FORCES (Fleet Sigma)                     │ ENEMY FORCES (Pirate Raiders)                                       │
│  ─────────────────────────────────────────     │ ─────────────────────────────────────────                           │
│  Destroyer       6    Undamaged                │  Raider          4    Destroyed                                     │
│  Cruiser         4    Undamaged                │  Corsair         2    Destroyed                                     │
│  Battleship      2    Undamaged                │                                                                     │
│  ─────────────────────────────────────────     │ ─────────────────────────────────────────                           │
│  Total AS:      96                             │  Total AS:       32                                                 │
│  Losses:        None                           │  Losses:         All destroyed                                      │
│                                                │                                                                     │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COMBAT LOG                                                                                                           │
│                                                                                                                      │
│  Round 1: Detection check - Intercept (no surprise)                                                                  │
│           Your roll: 7 + DRM 0 = 7 (CER 1.0x) → 96 hits                                                              │
│           Enemy roll: 3 + DRM 0 = 3 (CER 0.5x) → 16 hits                                                             │
│           Result: 4 Raiders crippled, by our fire. 2 Destroyers take minor damage.                                   │
│                                                                                                                      │
│  Round 2: Enemy AS reduced to 16 (all crippled)                                                                      │
│           Your roll: 8 (CER 1.0x) → 96 hits. Enemy destroyed.                                                        │
│           Combat ends - Victory                                                                                      │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [J] Jump to Fleet Sigma  [N] Next report  [D] Delete  [A] Archive  [Backspace] Back        [: ] Expert Mode
```

#### 5.4.4 Scout Intel Report Detail

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Reports > Intel Report: Enemy Fleet at D6
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ INTEL REPORT: Enemy Fleet Detected                                                           Turn 42 - Scout Colony  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ MISSION SUMMARY                                                                                                      │
│                                                                                                                      │
│  Mission Type:   Scout System (Command 12)                                                                           │
│  Target:         System D6 (House Stratos territory)                                                                 │
│  Agent:          Fleet Lambda (1 scout)                                                                              │
│  Result:         SUCCESS - Scout undetected, intelligence gathered                                                   │
│  Scout Status:   Consumed (per mission rules)                                                                        │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ INTELLIGENCE GATHERED (Perfect Quality)                                                                              │
│                                                                                                                      │
│  FLEET COMPOSITION AT D6                                                                                             │
│  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────     │
│  Fleet Name       Ships    Composition                    Command           Status                                   │
│  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────     │
│  Stratos Prime      8      DD×4, CR×3, BS×1               Hold              Stationary                               │
│  Stratos Aux        4      TT×3, ETAC×1                   Hold              Loaded (marines detected)                │
│                                                                                                                      │
│  ASSESSMENT                                                                                                          │
│    Total AS: ~72        Threat Level: MODERATE                                                                       │
│    Likely Intent: Staging for invasion (troop transports loaded)                                                     │
│    Recommended Action: Reinforce Thera Gate (C4), closest friendly system                                            │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ CONFIDENCE                                                                                                           │
│                                                                                                                      │
│  Data Quality:   ████████████ Perfect (undetected scout)                                                             │
│  Data Age:       Current (Turn 42)                                                                                   │
│  Decay:          Intel degrades 20% per turn without refresh                                                         │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [J] Jump to target system on map  [N] Next report  [D] Delete  [A] Archive  [Backspace] Back  [: ] Expert Mode
```

### 5.5 Messages & Diplomacy (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Messages
┌───────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ HOUSES        │ CONVERSATION: House Stratos                                                                          │
├───────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────┤
│               │                                                                                                      │
│  Stratos  (3) │  DIPLOMATIC STATUS: Hostile                                                                          │
│  ────────     │  Treaties: None                   NAPs: None                    Trade: None                          │
│  Corvus   (1) │                                                                                                      │
│  Lyra     (0) │  ────────────────────────────────────────────────────────────────────────────────────────────────    │
│  Aquila   (0) │                                                                                                      │
│  Draco    (0) │  [T40] FROM STRATOS:                                                                                 │
│               │  "Your scouts have been detected in our territory. Consider this a warning.                          │
│               │   Further incursions will be met with force."                                                        │
│               │                                                                                                      │
│               │  [T40] TO STRATOS:                                                                                   │
│               │  "We seek only to ensure the security of our borders. Perhaps we can discuss                         │
│               │   a mutual non-aggression arrangement?"                                                              │
│               │                                                                                                      │
│               │  [T42] FROM STRATOS:                                                                                 │
│               │  "Your 'security concerns' look suspiciously like preparation for war.                               │
│               │   We are mobilizing. You have been warned."                                                          │
│               │                                                                                                      │
│               │  ────────────────────────────────────────────────────────────────────────────────────────────────    │
│               │  [C] Compose reply    [T] Propose treaty    [W] Declare war                                          │
│               │                                                                                                      │
└───────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select house  [Enter] View conversation  [C] Compose  [T] Treaty  [Backspace] Back   [: ] Expert Mode
```

### 5.6 Game Settings (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42         CR: 1,820  ⚙ PROD: 640  ⚖ DIP: ••◦                                         ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Settings
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ GAME SETTINGS                                                                                                        │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                                      │
│  GLOBAL COLONY AUTOMATION DEFAULTS                                                                                   │
│  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────   │
│  These defaults apply to newly colonized worlds. Existing colonies can override in their Settings tab.               │
│                                                                                                                      │
│    Auto-Repair Ships        [ON ]     Automatically queue crippled ships for repair at drydocks                      │
│    Auto-Load Marines        [ON ]     Load marines onto docked troop transports                                      │
│    Auto-Load Fighters       [OFF]     Load fighters onto docked carriers                                             │
│                                                                                                                      │
│  DISPLAY OPTIONS                                                                                                     │
│  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────   │
│                                                                                                                      │
│    Color Theme              [Classic EC]    Classic EC / High Contrast / Monochrome                                  │
│    Show Coordinates         [ON ]           Display sector coordinates in fleet/colony views                         │
│    Compact Tables           [OFF]           Reduce row spacing in list views                                         │
│    Animation Speed          [Normal]        Off / Slow / Normal / Fast                                               │
│                                                                                                                      │
│  NOTIFICATION PREFERENCES                                                                                            │
│  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────   │
│                                                                                                                      │
│    Auto-open Turn Summary   [ON ]           Open turn summary report at start of each turn                           │
│    Alert on Idle Fleets     [ON ]           Show alert when fleets have no orders                                    │
│    Alert on Idle Facilities [ON ]           Show alert when shipyards/drydocks are idle                              │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Space] Toggle  [Enter] Change value  [R] Reset to defaults  [Backspace] Back  [: ] Expert Mode
```

---

## 6. Fleet Commands Reference

All 20 fleet commands from `docs/specs/06-operations.md`:

| #  | Command        | Key | Requirements                             | Description                              |
|----|----------------|-----|------------------------------------------|------------------------------------------|
| 00 | Hold           | `H` | None                                     | Hold position, await orders              |
| 01 | Move           | `M` | None                                     | Move to destination, then hold           |
| 02 | Seek Home      | `K` | None                                     | Return to nearest friendly drydock       |
| 03 | Patrol         | `P` | None                                     | Patrol single system                     |
| 04 | Guard Starbase | `G` | Combat ship(s)                           | Defend starbase in orbital combat        |
| 05 | Guard Colony   | `G` | Combat ship(s)                           | Defend colony in orbital combat          |
| 06 | Blockade       | `B` | Combat ship(s)                           | Blockade planet (40% prod penalty)       |
| 07 | Bombard        | `O` | Combat ship(s)                           | Orbital bombardment                      |
| 08 | Invade         | `I` | Combat ships + loaded TTs                | Ground invasion (batteries must be 0)    |
| 09 | Blitz          | `Z` | Loaded TTs                               | Rapid assault (land under fire)          |
| 10 | Colonize       | `C` | One ETAC with PTUs                       | Establish new colony                     |
| 11 | Scout Colony   | `S` | Scout-only fleet                         | Intel on colony (scouts consumed)        |
| 12 | Scout System   | `S` | Scout-only fleet                         | Intel on system fleets (consumed)        |
| 13 | Hack Starbase  | `S` | Scout-only fleet                         | Cyber op on starbase (consumed)          |
| 14 | Join Fleet     | `J` | None                                     | Merge into target fleet                  |
| 15 | Rendezvous     | `V` | None                                     | Move to system, auto-merge on arrival    |
| 16 | Salvage        | `X` | Friendly colony system                   | Scrap fleet for 50% PP                   |
| 17 | Reserve        | `E` | At friendly colony                       | 50% readiness, 50% cost                  |
| 18 | Mothball       | `L` | At colony with Spaceport                 | Offline, 10% maint, 0 CC                 |
| 19 | View           | `W` | Any ship type                            | Long-range recon (safe, non-consumable)  |

**Batch operations** (multi-select): Only **Move (01)**, **Join (14)**, **Rendezvous (15)**

---

## 7. Zero-Turn Administrative Commands

Execute instantly during command submission (before turn resolution):

| Command         | Description                                      |
|-----------------|--------------------------------------------------|
| DetachShips     | Split ships from fleet into new fleet            |
| TransferShips   | Move ships between two fleets at same colony     |
| MergeFleets     | Combine two fleets into one                      |
| Reactivate      | Return Reserve/Mothball fleet to Active          |
| LoadCargo       | Load marines/colonists onto transports/ETACs     |
| UnloadCargo     | Unload cargo to colony                           |
| ScrapCommand    | Scrap individual ships/units/facilities for PP   |

---

## 8. ROE Quick Picker Overlay

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ SET RULES OF ENGAGEMENT: Fleet Sigma                                                  │
├───────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                       │
│  ROE   THRESHOLD   BEHAVIOR                           USE CASE                        │
│  ───────────────────────────────────────────────────────────────────────────────────  │
│   0      0.0       Avoid all hostile forces           Pure scouts                     │
│   1    999.0       Engage only defenseless            Extreme caution                 │
│   2      4.0       Need 4:1 advantage                 Scout fleets                    │
│   3      3.0       Need 3:1 advantage                 Cautious patrols                │
│   4      2.0       Need 2:1 advantage                 Conservative ops                │
│   5      1.5       Need 3:2 advantage                 Defensive posture               │
│  [6]     1.0       Fight if equal or superior         Standard combat    ← Current    │
│   7      0.67      Fight at 2:3 disadvantage          Aggressive fleets               │
│   8      0.5       Fight at 1:2 disadvantage          Battle fleets                   │
│   9      0.33      Fight at 1:3 disadvantage          Desperate defense               │
│  10      0.0       Fight regardless of odds           Suicidal / homeworld            │
│                                                                                       │
│  [↑/↓] Select    [Enter] Confirm    [Esc] Cancel                                      │
│                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**Combat State Reference** (from `docs/specs/07-combat.md`):
- **Undamaged**: 100% AS/DS
- **Crippled**: 50% AS/DS, 50% maintenance, cannot use restricted lanes
- **Destroyed**: Eliminated

---

## 9. Colony Automation Flags

From `src/engine/types/colony.nim`:

| Flag               | Default | Description                                        |
|--------------------|---------|----------------------------------------------------|
| `autoRepair`       | ON      | Automatically queue crippled ships for repair      |
| `autoLoadMarines`  | ON      | Load marines onto docked troop transports          |
| `autoLoadFighters` | OFF     | Load fighters onto docked carriers                 |

**Configuration hierarchy**:
1. Global defaults in Game Settings (apply to new colonies)
2. Per-colony overrides in Planet Manager > Settings tab

---

## 10. Data & Engine Hooks

### State Inputs

Panels consume read-only snapshots via UFCS patterns:
- `state.playerView(houseId)` - Fog-of-war filtered view
- `state.fleetsOwned(houseId)` - Iterator over house fleets
- `state.coloniesOwned(houseId)` - Iterator over house colonies
- `state.colony(colonyId)` - Single colony access
- `state.fleet(fleetId)` - Single fleet access

### Event Bus

UI subscribes to `TurnEvents` channel for real-time updates:
- Construction completion
- Combat resolution
- Intel changes
- Diplomatic status changes

### Configuration

Colors, hotkeys, animation toggles from `config/ui.toml`:
```toml
[colors]
hud_background = "navy"
hud_foreground = "amber"
alert = "red"
selected = "cyan"

[hotkeys]
move = "m"
patrol = "p"
hold = "h"

[animations]
speed = "normal"  # off, slow, normal, fast
```

### Testing Harness

Deterministic mock data in `samples/tui/` for layout validation without full simulation.

---

## 11. Milestones

1. **Widget Library** (Sprint 1-2)
   - HUD Strip component
   - Panel with borders (double/single)
   - Command Dock
   - Table with multi-select

2. **Strategic Overview MVP** (Sprint 3)
   - Three-column layout
   - Recent events ticker
   - Empire status cards
   - Action queue with jump hotkeys

3. **Planet Manager MVP** (Sprint 4-5)
   - Colony list view
   - Detail view with all 5 tabs
   - Tax slider interaction
   - Construction queue management

4. **Fleet Console MVP** (Sprint 6-7)
   - System view (grouped by location)
   - List view with multi-select
   - Fleet detail panel
   - ROE picker overlay

5. **Reports Inbox MVP** (Sprint 8)
   - Email-style 3-column layout
   - Category filtering
   - Turn summary auto-open
   - Report detail views

6. **Expert Mode** (Sprint 9)
   - Command palette (`:` prefix)
   - Tab completion
   - Command history
   - Error feedback

7. **Polish & Nostalgia Pass** (Sprint 10)
   - Animation system
   - Sound effects (optional)
   - Classic layout toggle
   - Accessibility review

---

## 12. Risks & Mitigations

| Risk                      | Mitigation                                              |
|---------------------------|---------------------------------------------------------|
| Information overload      | Progressive disclosure; default to summary, drill down  |
| Input latency             | Buffered rendering, differential updates                |
| 80-col degradation        | Explicit fallback layouts tested, column stacking       |
| Legacy expectations       | Classic Layout toggle, legacy hotkey support            |
| Expert mode complexity    | Tab completion, inline help, error messages             |

---

## 13. Success Metrics

1. **Onboarding**: New players complete full turn (taxes + fleet orders) without manual
2. **Recognition**: EC veterans identify classic references (colors, stat slabs, hotkeys)
3. **Responsiveness**: <100ms feedback on all input actions
4. **Readability**: Interface legible on 80x24 terminals without horizontal scrolling
5. **Expert efficiency**: Power users issue 5+ commands/minute via Expert Mode

---

## Appendix: 80-Column Fallback Examples

### Strategic Overview (80 columns)

```
╔════════════════════════════════════════════════════════════════════════════╗
║ VALERIAN ▸ T42    CR:1820  PROD:640  DIP:••◦   ⚠3 Alerts  ✉2 Reports      ║
╚════════════════════════════════════════════════════════════════════════════╝
 Home > Overview
┌──────────────────────────────────────────────────────────────────────────────┐
│ EMPIRE STATUS                          │ ACTION QUEUE                        │
│                                        │                                     │
│ Colonies: 12  Fleets: 13               │ ⚠ 1 Idle shipyard        [jump 2]   │
│ Treasury: 1,820 PP  Prod: 640/turn     │ ⚠ 2 Fleets w/o orders    [jump 3]   │
│ Prestige: 487 (2nd)  Morale: Good      │ ✉ 1 Unread combat rpt    [jump 4]   │
│                                        │                                     │
│ RECENT EVENTS                          │ CHECKLIST                           │
│ [T42] Victory at Thera Gate            │ ■ Shipyard A idle                   │
│ [T42] Starbase completed @ Bigun       │ ■ Fleet Omega - no orders           │
│ [T41] Scout detected enemy @ D6        │ ■ Fleet Tau - no orders             │
└──────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [1]Ovrvw [2]Planets [3]Fleets [4]Rpts [5]Msgs [6]Set [Q]Quit  [:] Expert
```

### Fleet List (80 columns)

```
╔════════════════════════════════════════════════════════════════════════════╗
║ VALERIAN ▸ T42                              ⚠ Omega idle  ⚠ Tau idle       ║
╚════════════════════════════════════════════════════════════════════════════╝
 Home > Fleets (List)
┌──────────────────────────────────────────────────────────────────────────────┐
│ FLEET        LOC      SHIPS  AS   COMMAND      DEST     ETA  ROE  STATUS     │
├──────────────────────────────────────────────────────────────────────────────┤
│ Alpha        B7          8   64   Guard Col    —        —     6   ●          │
│ Beta         B7          4   24   Reserve      —        —     8   RSV        │
│►►Sigma       C4         12   96   Patrol       D5       2t    6   ●          │
│[X]Tau        C4          4   32   Hold         —        —     6   ⚠IDLE      │
│[X]Omega      C4          8   64   (none)       —        —     6   ⚠IDLE      │
│ Lambda       D2          1    4   Scout Sys    E3       4t    2   ●          │
│ Petra        D2          5   20   Colonize     F1       3t    6   ●          │
│ Gamma        A3          6   48   Mothball     —        —     —   MTB        │
└──────────────────────────────────────────────────────────────────────────────┘
 13 fleets | 2 selected | Batch: [M]Move [J]Join [V]Rndzvs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑↓]Sel [X]Toggle [Enter]Details [S]Sort [F]Filter        [:] Expert
```

---

**Document Version**: 2.0
**Last Updated**: 2026-01-15
**Status**: Design specification ready for implementation
