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

2. **Always-On Awareness**: Present empire-critical data at all times (turn status, prestige,
   idle assets, alerts) so players never lose context when drilling into submenus.

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

**Responsive behavior**: At 80 columns, multi-column layouts stack vertically. Tables
truncate long fields with ellipsis. Status bar uses shortened labels (OVR, PLN, FLT).

### Screen Regions

```
+------------------------------------------------------------------------------+
| HUD STRIP (2 lines)                                                          |
|   Left: Empire + Turn    Center: Prestige/Treasury/Prod/C2    Right: Alerts  |
+------------------------------------------------------------------------------+
| BREADCRUMB LINE (1 line)                                                     |
|   Home > Fleets > Alpha Patrol                                               |
+------------------------------------------------------------------------------+
|                                                                              |
| MAIN CANVAS (variable height)                                                |
|   - Centered floating modals for 9 primary views                             |
|   - Single-line borders (──) for modals and overlays                         |
|                                                                              |
+------------------------------------------------------------------------------+
| STATUS BAR (1 line) - Zellij/Helix hybrid                                    |
|   <1> OVR  <2> PLN  <3> FLT ... <:> EXPERT    or    :command input_          |
+------------------------------------------------------------------------------+
```

### Primary Views (9 Total)

| Key | View       | Description                                      |
|-----|------------|--------------------------------------------------|
| `1` | Overview   | Empire dashboard, leaderboard, alerts            |
| `2` | Planets    | Colony list and detail management                |
| `3` | Fleets     | Fleet management (system view, list, details)    |
| `4` | Research   | Tech levels, ERP/SRP/TRP allocation              |
| `5` | Espionage  | EBP/CIP budget, intelligence operations          |
| `6` | Economy    | House tax rate, treasury, income breakdown       |
| `7` | Reports    | Turn summaries, combat/intel reports             |
| `8` | Messages   | Diplomacy, inter-house communication             |
| `9` | Settings   | Display options, colony automation defaults      |
| `Q` | Quit       | Exit game                                        |

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
| Prestige          | Yellow      | —           | 93          |

### Borders & Typography

- **Primary panels**: Double-line `═║╔╗╚╝╠╣╦╩╬`
- **Dialogs/overlays**: Single-line `─│┌┐└┘├┤┬┴┼`
- **Subtle grouping**: Dotted `···` or light box `╌`
- **Headings**: ALL CAPS, left-aligned
- **Monospace alignment**: 2-space gutters, 80-char line limit in content

### Glyphs & Icons

| Glyph | Meaning                            |
|-------|------------------------------------|
| `★`   | Prestige                           |
| `●`   | OK / Neutral diplomatic status     |
| `⚠`   | Needs Attention / Hostile status   |
| `⚔`   | Enemy diplomatic status            |
| `☠`   | Eliminated                         |
| `RSV` | Reserve status                     |
| `MTB` | Mothballed status                  |
| `▲▼`  | Trend up/down                      |
| `✉`   | Unread message/report              |
| `▓░`  | Progress bar                       |

---

## 4. Input Model

### Navigation Hierarchy

```
[Alt+Key]       Switch primary views
[Tab/S-Tab]     Cycle focusable widgets within view
[Enter]         Drill into selected item / confirm action
[Esc]           Step up breadcrumb history / cancel overlay
[?]             Show context help overlay
[L]             Diplomatic matrix overlay (from Overview)
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
| `T` | Economy view      | Adjust tax rate                     |
| `L` | Overview          | Diplomatic matrix overlay           |
| `D` | Reports           | Delete selected report              |
| `X` | Multi-select      | Toggle selection on current row     |
| `A` | Proposals         | Accept proposal                     |
| `R` | Proposals         | Reject proposal                     |

### Expert Mode (Command Palette)

Typing `:` enters command mode in the status bar. The input appears in the bottom
status bar line, with a helix-style completion palette floating above. Supports
vim-style direct commands:

```
# Fleet Commands
:move alpha B7          Move fleet "alpha" to system B7
:patrol delta           Set fleet "delta" to patrol current system
:roe sigma 8            Set fleet "sigma" ROE to 8
:join alpha beta        Join fleet "alpha" into fleet "beta"
:reserve omega          Put fleet "omega" into reserve
:mothball gamma         Mothball fleet "gamma"

# Colony Commands
:build bigun cruiser 3  Queue 3 cruisers at colony "bigun"

# Economy Commands
:tax 45                 Set house-wide tax rate to 45%

# Research Commands
:research erp 50        Allocate 50 PP to Economic Research Pool
:research srp 30        Allocate 30 PP to Scientific Research Pool
:research trp 20        Allocate 20 PP to Technical Research Pool

# Espionage Commands
:buy ebp 3              Purchase 3 EBP (120 PP)
:buy cip 2              Purchase 2 CIP (80 PP)
:spy techtheft stratos nova    Tech theft on House Stratos at Nova

# Diplomacy Commands
:propose hostile stratos       Propose de-escalation to Hostile
:propose neutral stratos       Propose de-escalation to Neutral
:accept 1                      Accept pending proposal #1
:reject 1                      Reject pending proposal #1
:declare hostile stratos       Escalate to Hostile
:declare enemy stratos         Declare war (Enemy)
```

**UI Behavior**:
- Status bar switches from keybinding hints to `:` prompt
- Expert palette renders above status bar (max 8 rows)
- Tab completion with fuzzy matching
- Up/down arrows navigate command history
- Escape returns to normal mode

**Tab completion**: Fleet names, colony names, ship types, commands auto-complete.
**History**: Up/down arrows navigate command history.

### Status Bar Design (Zellij/Helix Hybrid)

A single-line status bar at the bottom of the screen combining Zellij-style keybinding
hints with Helix-style expert mode input.

#### Normal Mode Layout

```
 <1> OVERVIEW  <2> PLANETS  <3> FLEETS  <4> RESEARCH  ... <:> EXPERT
```

| Element | Description |
|---------|-------------|
| `<key>` | Angle-bracketed key in cyan/highlighted color |
| `LABEL` | Action label in standard text |
| `` | Powerline arrow separator between segments |
| Selection | Current view highlighted with inverted colors |

#### Expert Mode Layout

When `:` is pressed, the status bar switches to command input:

```
:move alpha B7_
```

- Prompt (`:`) in key color
- Input text in standard color
- Blinking cursor at end

The expert palette (helix-style completion menu) renders **above** the status bar,
floating over the canvas area.

#### Progressive Width Adaptation

| Width | Format |
|-------|--------|
| Full (120+) | `<1> OVERVIEW  <2> PLANETS  <3> FLEETS ...` |
| Medium (80-120) | `<1> OVR  <2> PLN  <3> FLT ...` |
| Narrow (<80) | Truncate from right, keeping `:` expert hint |

#### Color Scheme

| Element | Foreground | Background |
|---------|------------|------------|
| Bar background | #c0caf5 | #24283b |
| Key highlight | #7dcfff (cyan) | #24283b |
| Selected item | #1a1b26 | #7aa2f7 (blue) |
| Disabled | #565f89 | #24283b |
| Cursor | #24283b | #7dcfff |

---

## 5. Entry Screen Modal

The entry screen modal is a centered overlay that appears on application launch. It handles
identity management and game selection before the player enters the main game interface.

### 5.1 Design Principles

- **Centered modal**: DOS/BBS-era index card aesthetic, single-line borders
- **Persistent identity**: Auto-generated keypair on first launch, persists across sessions
- **Minimal friction**: One-click to join a game or resume existing game
- **No game creation**: Only the moderator can create games (via `bin/ec4x`)

### 5.2 Identity Model

Players are identified by Nostr keypairs (secp256k1). Two identity types:

| Type       | Description                                      | Label      |
|------------|--------------------------------------------------|------------|
| `local`    | Auto-generated on first launch, stored locally   | (local)    |
| `imported` | User-provided nsec from existing Nostr identity  | (imported) |

**Storage location**: `~/.local/share/ec4x/identity.kdl`

```kdl
identity {
  nsec "nsec1..."
  type "local"
  created "2026-01-17T12:00:00Z"
}
```

**Display format**: Truncated npub with ellipsis: `npub1q3z...7xkf`

### 5.3 Modal Layout (72 columns max)

```
┌────────────────────────────────────────────────────────────────────────┐
│                              E C 4 X                                   │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  ███████╗ ██████╗██╗  ██╗██╗  ██╗                                      │
│  ██╔════╝██╔════╝██║  ██║╚██╗██╔╝                                      │
│  █████╗  ██║     ███████║ ╚███╔╝                                       │
│  ██╔══╝  ██║     ╚════██║ ██╔██╗                                       │
│  ███████╗╚██████╗     ██║██╔╝ ██╗                                      │
│  ╚══════╝ ╚═════╝     ╚═╝╚═╝  ╚═╝                                      │
│                                                                        │
│  IDENTITY ─────────────────────────────────────────────────────────    │
│  npub1q3z...7xkf (local)                          [I] Import nsec      │
│                                                                        │
│  YOUR GAMES ───────────────────────────────────────────────────────    │
│► Alpha Campaign    T42   House Valerian                                │
│  Beta Skirmish     T18   House Stratos                                 │
│                                                                        │
│  OPEN LOBBIES ─────────────────────────────────────────────────────    │
│  New Galaxy        (3/6 players)                                       │
│                                                                        │
├────────────────────────────────────────────────────────────────────────┤
│  [↑/↓] Select   [Enter] Play   [I] Import   [Q] Quit       v0.1.0      │
└────────────────────────────────────────────────────────────────────────┘
```

**Responsive width**: `min(termWidth - 4, 72)`

### 5.4 Modal Sections

#### Header
- Title bar: "E C 4 X" centered with letter spacing
- ASCII art logo using Unicode block characters (██, ╗, ╔, etc.)

#### Identity Section
- Truncated npub display with type label in parentheses
- `[I]` hotkey hint for import action (right-aligned)

#### Your Games List
- Games where player's identity is already registered
- Columns: Game name, Turn number (T##), House name
- `►` cursor indicates selected row
- Empty state: "No active games" (dimmed)

#### Open Lobbies List
- Games accepting new players
- Columns: Game name, Player count (current/max)
- Empty state: "No open lobbies" (dimmed)

#### Footer
- Hotkey reference: `[↑/↓] Select   [Enter] Play   [I] Import   [Q] Quit`
- Version number right-aligned

### 5.5 Input Handling

| Key      | Action                                           |
|----------|--------------------------------------------------|
| `↑`/`↓`  | Navigate game list (Your Games, then Lobbies)   |
| `Enter`  | Play selected game / Join selected lobby         |
| `I`      | Open nsec import dialog                          |
| `Q`      | Quit application                                 |

### 5.6 Import Flow

When `[I]` is pressed:

1. Modal displays inline input field: `Enter nsec: _______________`
2. User pastes/types nsec (Bech32 format starting with `nsec1`)
3. On Enter:
   - Validate nsec format
   - If valid: Save to identity.kdl with type "imported", refresh display
   - If invalid: Show error message, return to input
4. Escape cancels import, returns to main modal

### 5.7 State Transitions

```
┌─────────────────┐
│  App Launch     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     identity.kdl exists?
│  Load Identity  │────────────────────────────┐
└────────┬────────┘                            │
         │ No                                  │ Yes
         ▼                                     ▼
┌─────────────────┐                  ┌─────────────────┐
│ Generate Keypair│                  │ Read Keypair    │
│ Save as "local" │                  │ from file       │
└────────┬────────┘                  └────────┬────────┘
         │                                    │
         └──────────────┬─────────────────────┘
                        ▼
              ┌─────────────────┐
              │ Fetch Game List │
              │ from Relay      │
              └────────┬────────┘
                       ▼
              ┌─────────────────┐
              │ Show Entry Modal│
              └────────┬────────┘
                       │
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
    [I] Import    [Enter] Play   [Q] Quit
```

### 5.8 Color Palette

Uses Tokyo Night palette from `ec_palette.nim`:

| Element              | Color                              |
|----------------------|------------------------------------|
| Modal border         | `tokyoFg` (foreground)             |
| Modal background     | `tokyoBgDark` (dark background)    |
| Title                | `tokyoCyan` (accent)               |
| ASCII logo           | `tokyoBlue` (primary)              |
| Section headers      | `tokyoFg` with horizontal rule     |
| Identity npub        | `tokyoGreen` (success/identity)    |
| Type label           | `tokyoComment` (dimmed)            |
| Selected row `►`     | `tokyoCyan` cursor                 |
| Game names           | `tokyoFg`                          |
| Turn/house info      | `tokyoComment` (secondary)         |
| Empty state text     | `tokyoComment` (dimmed italic)     |
| Hotkeys `[X]`        | `tokyoYellow` (action)             |
| Version number       | `tokyoComment`                     |

---

## 6. Primary Views

### 6.1 Strategic Overview (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Overview
┌────────────────────────────┬──────────────────────────────────────────┬───────────────────────────────────────────────┐
│ RECENT EVENTS              │ EMPIRE STATUS                            │ LEADERBOARD                                   │
├────────────────────────────┤                                          ├───────────────────────────────────────────────┤
│[T42] Fleet Sigma repelled  │  COLONIES          FLEETS                │  #  HOUSE       ★PRESTIGE  COLONIES  STATUS   │
│      pirates @ Thera Gate  │  Owned   12  ▲2    Active    8           │  1. Valerian       487       12       YOU     │
│[T42] Colony Bigun starbase │  Growth +1.4 PU    Reserve   3           │  2. Stratos        412        9       ⚔ ENM   │
│      construction complete │  Tax Rate  52%     Mothball  2           │  3. Corvus         356        8       ● NEU   │
│[T41] Scout Lambda spotted  │                                          │  4. Lyra           298        7       ● NEU   │
│      warps @ sector 17,5   │  DIPLOMACY         INTEL                 │  5. Aquila         201        5       ⚠ HOS   │
│[T41] Research breakthrough │  Neutral    3      Known Systems  44     │  6. Draco         ELIM        0       ☠       │
│      WEP 2 → 3             │  Hostile    1      Fogged         12     │                                               │
│[T40] Enemy fleet detected  │  Enemy      1      Scout Missions  3     │  Map: 41/64 systems colonized                 │
│      approaching Ymir      │  Proposals  2                            │  [L] Diplomatic matrix                        │
├────────────────────────────┴──────────────────────────────────────────┼───────────────────────────────────────────────┤
│ ACTION QUEUE                                                          │ CHECKLIST                                     │
│                                                                       │                                               │
│ ⚠ 1 Idle shipyard at Bigun                                  [jump 2]  │ ■ Shipyard A at Bigun idle                    │
│ ⚠ 2 Fleets without orders                                   [jump 3]  │ ■ Fleet Omicron awaiting orders               │
│ ✉ 1 Unread combat report                                    [jump 7]  │ ■ Fleet Tau awaiting orders                   │
│                                                                       │ ■ Report: Zeta skirmish (unread)              │
└───────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [1]Ovrvw [2]Planets [3]Fleets [4]Research [5]Espionage [6]Economy [7]Reports [8]Msgs [9]Settings [Q]Quit
 [2,3,7] Jump to action item    [L] Diplomatic matrix                                          [: ] Expert Mode
```

**HUD Strip Elements:**
- `★ 487 (2nd)` - Prestige with standing (rank among all houses)
- `CR: 1,820` - Treasury (credits/production points)
- `PROD: 640` - Net House Value (total production income)
- `C2: 82/120 ●` - Command capacity (used/total) with status indicator
  - `●` = OK (within capacity)
  - `⚠` = STRAIN (over capacity, logistical penalties)

**Leaderboard Status Column:**
- `YOU` - Your house
- `● NEU` - Neutral relations with you
- `⚠ HOS` - Hostile relations with you
- `⚔ ENM` - Enemy (at war) with you
- `☠` - Eliminated from game

### 6.1.1 Diplomatic Matrix Overlay

Accessible via `[L]` from Overview. Shows all inter-house diplomatic relations:

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ DIPLOMATIC RELATIONS MATRIX                                    Legend: ● Neutral  ⚠ Hostile  ⚔ Enemy  ☠ Eliminated   │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                                      │
│                    Valerian   Stratos    Corvus     Lyra       Aquila     Draco                                      │
│  ─────────────────────────────────────────────────────────────────────────────────                                   │
│  Valerian (YOU)       —         ⚔          ●          ●          ⚠          ☠                                        │
│  Stratos              ⚔         —          ●          ⚠          ●          ☠                                        │
│  Corvus               ●         ●          —          ●          ●          ☠                                        │
│  Lyra                 ●         ⚠          ●          —          ⚔          ☠                                        │
│  Aquila               ⚠         ●          ●          ⚔          —          ☠                                        │
│  Draco                ☠         ☠          ☠          ☠          ☠          —                                        │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ PENDING PROPOSALS                                                                                                    │
│                                                                                                                      │
│  FROM         TO           PROPOSAL                          SUBMITTED   EXPIRES                                     │
│  Stratos  →  Valerian     De-escalate Enemy → Hostile        Turn 41     Turn 44                                     │
│  Lyra     →  Aquila       De-escalate Enemy → Neutral        Turn 40     Turn 43                                     │
│                                                                                                                      │
│  [A] Accept proposal to you    [Esc] Close                                                                           │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Planet Manager (120 columns)

#### 6.2.1 Planet List View

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ COLONY                SECTOR   CLASS    POP    IU    GCO    NCV   GROWTH    FACILITIES          STATUS               │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Valeria Prime (HW)    A3       Lush     48     52    104     54   +1.4 PU   SP SY SY DD DD SB   ●                    │
│ Bigun                 B7       Benign   32     38     80     42   +0.8 PU   SP SY DD SB         ⚠ Idle shipyard      │
│ Thera Gate            C4       Hostile  18     22     44     23   +0.4 PU   SP SY DD            ●                    │
│ Ymir Relay            D2       Benign   24     28     56     15   +0.6 PU   SP DD               ⚠ Blockaded (-60%)   │
│ Nova Station          E9       Lush     28     34     68     35   +0.7 PU   SP SY DD            ●                    │
│ Frontier VII          F1       Hostile  12     15     30     16   +0.3 PU   SP                  ●                    │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
 12 colonies  |  GHO: 640 PP  |  NHV: 333 PP (52% tax)  |  3 idle facilities
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] View Colony  [B] Build  [S] Sort  [F] Filter  [6] Economy view          [: ] Expert Mode
```

**Column definitions:**
- `GCO` - Gross Colony Output (total production before tax)
- `NCV` - Net Colony Value (GCO × tax rate, your income from this colony)
- `GROWTH` - Population growth rate (PU/turn)
- **Facility codes**: SP=Spaceport, SY=Shipyard, DD=Drydock, SB=Starbase

#### 6.2.2 Planet Detail View - Summary Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  [Summary]  Economy   Construction   Defense   Settings                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COLONY: Bigun                                                                                                        │
│ Location: Sector B7    Class: Benign    RAW Index: Abundant (0.80)                                                   │
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
│   House Tax Rate: 52% (set in [6] Economy)     │   1. Cruiser      ▓▓▓░░ (3/5)   ETA 2 turns                         │
│   GCO: 80 PP    NCV: 42 PP                     │   2. Battleship   ▓░░░░░░ (1/7)   ETA 6 turns                       │
│   PU Growth:  +0.8/turn                        │   3. Army         DONE - ready to deploy                            │
│   IU Growth:  +0.3/turn                        │                                                                     │
│   Starbase Bonus: +5%                          │                                                                     │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [B] Build  [G] Garrison  [Backspace] Back              [: ] Expert Mode
```

#### 6.2.3 Planet Detail View - Economy Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun > Economy
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Summary  [Economy]  Construction   Defense   Settings                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COLONY REVENUE                                                                                                       │
│                                                                                                                      │
│   Gross Colony Output (GCO):    80 PP                                                                                │
│     Population contribution:    26 PP  (32 PU × 0.80 RAW index)                                                      │
│     Industrial contribution:    54 PP  (38 IU × 1.26 EL modifier × 1.02 productivity)                                │
│                                                                                                                      │
│   House Tax Rate:               52%  (set in [6] Economy view)                                                       │
│   Net Colony Value (NCV):       42 PP  (GCO × tax rate, rounded up)                                                  │
│                                                                                                                      │
│   Starbase Economic Bonus:      +5%  (1 starbase, max 15% from 3)                                                    │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ GROWTH PROJECTIONS                                                                                                   │
│                                                                                                                      │
│   POPULATION GROWTH                            │ INDUSTRIAL GROWTH                                                   │
│                                                │                                                                     │
│   Base rate:        30%/turn                   │ Base rate:       +2 IU/turn (floor(PU/50))                          │
│   Tax modifier:     ×0.95 (52% rate)           │ Tax modifier:    ×0.48 (1 - tax rate)                               │
│   Starbase bonus:   ×1.05 (+5%)                │ Starbase bonus:  ×1.05 (+5%)                                        │
│   ─────────────────────────────────────────    │ ─────────────────────────────────────────                           │
│   Projected:        +0.8 PU next turn          │ Projected:       +1 IU next turn                                    │
│                                                │                                                                     │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ TAX RATE IMPACT (House-wide: 52%)                                                                                    │
│                                                                                                                      │
│   Current bracket:  51-100% — No growth bonus, prestige penalty applies                                              │
│   Prestige impact:  -1/turn house-wide (high tax penalty, rate > 50%)                                                │
│                                                                                                                      │
│   Lower tax benefits:                                                                                                │
│     ≤40%: +5% pop growth, no penalty          ≤30%: +10% pop growth, +1 prestige/colony                              │
│     ≤20%: +15% pop growth, +2 prestige/colony ≤10%: +20% pop growth, +3 prestige/colony                              │
│                                                                                                                      │
│   [6] Go to Economy view to adjust House tax rate                                                                    │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [6] Economy view  [Backspace] Back                     [: ] Expert Mode
```

#### 6.2.4 Planet Detail View - Construction Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun > Construction
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Summary   Economy  [Construction]  Defense   Settings                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ CONSTRUCTION QUEUE                             │ REPAIR QUEUE                                                        │
│ Shipyard: 7/10 docks in use                    │ Drydock: 2/10 bays in use                                           │
│                                                │                                                                     │
│  #  PROJECT       COST   PROGRESS      ETA     │  #  SHIP            COST   STATUS                                   │
│  1. Cruiser        35    ▓▓▓░░ (3/5)   2 trn   │  1. DD Falcon        5     Repairing (1 turn)                       │
│  2. Battleship     70    ▓░░░░░░ (1/7) 6 trn   │  2. CR Hawk          9     Repairing (1 turn)                       │
│  3. Destroyer      20    Queued        3 trn   │                                                                     │
│  4. Destroyer      20    Queued        3 trn   │                                                                     │
│  ─────────────────────────────────────────     │                                                                     │
│  [+] Add project                               │  [+] Add to repair queue                                            │
│                                                │                                                                     │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ AVAILABLE TO BUILD                                                                                                   │
│                                                                                                                      │
│  TYPE           COST   TIME   DOCKS   DESCRIPTION                               CST REQ                              │
│  Scout            8     1       1     Reconnaissance, intel missions             1                                   │
│  Corvette        20     2       1     Light escort, screening                    1                                   │
│  Frigate         25     2       1     Anti-fighter escort                        1                                   │
│  Destroyer       30     3       1     Fast escort, patrol duty                   1                                   │
│  Light Cruiser   40     4       2     Light capital ship                         2                                   │
│  Cruiser         50     5       2     Balanced warship                           2                                   │
│  Battlecruiser   70     6       2     Heavy cruiser                              3                                   │
│  Battleship      90     7       3     Capital ship, fleet actions                3                                   │
│  Dreadnought    120     9       4     Heavy capital, devastating firepower       4                                   │
│  Carrier         80     6       3     Fighter platform                           3                                   │
│  Troop Transport 30     3       2     Marine carrier, invasion ops               1                                   │
│  ETAC            50     4       3     Colony ship, carries PTUs                  2                                   │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] Build  [D] Delete from queue  [P] Prioritize  [Backspace] Back        [: ] Expert Mode
```

#### 6.2.5 Planet Detail View - Defense Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
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
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [G] Manage garrison  [Backspace] Back                  [: ] Expert Mode
```

#### 6.2.6 Planet Detail View - Settings Tab

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Planets > Bigun > Settings
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Summary   Economy   Construction   Defense  [Settings]                                                             │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ COLONY AUTOMATION                                                                                                    │
│                                                                                                                      │
│  These settings control automatic actions for this colony. Override global defaults from [9] Settings.               │
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
│  │ Main shipbuilding hub. Priority: battleship production until T50.                                               │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
│  [E] Edit notes                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [Tab] Next section  [1-5] Switch tab  [Backspace] Back                                       [: ] Expert Mode
```

### 6.3 Fleet Console (120 columns)

#### 6.3.1 Fleet Console - System View

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Fleets (System View)
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ [System View]  List View                                                                                             │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SYSTEM: Thera Gate (C4) ─────────────────────────────────────────────────────────────────────────────────────────────│
│                                                                                                                      │
│  ► Fleet Sigma         12 ships    Command: Patrol         ETA: ▓▓▓░░ to D5 (2 turns)                    ● OK        │
│      DD×6  CR×4  BS×2   ROE: 6                                                                                       │
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

#### 6.3.2 Fleet Console - List View (Table with Multi-Select)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
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
- `[X]` toggles selection on current row
- Selected fleets shown with `[X]` prefix
- Current cursor shown with `►►►`
- Batch commands limited to: **Move**, **Join**, **Rendezvous**

**Status column legend**:
- `●` = OK (Undamaged, has valid command)
- `⚠ IDLE` = Awaiting orders (Hold or no command)
- `⚠ CRIPPLED` = Contains crippled ships needing repair
- `RSV` = Reserve status (50% readiness)
- `MTB` = Mothballed status (offline)

#### 6.3.3 Fleet Details Panel

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
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
│  Cruiser          4    Undamaged    32    28   │                                                                     │
│  Battleship       2    Undamaged    40    26   │  Maintenance Cost:         12 PP/turn                               │
│  ────────────────────────────────────────────  │  Command Cost (CC):        8                                        │
│  TOTAL           12                 96    72   │                                                                     │
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

### 6.4 Research & Technology (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Research
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ RESEARCH ALLOCATION                                          │ CURRENT TECH LEVELS                                   │
│                                                              │                                                       │
│ Treasury: 1,820 PP    Allocate this turn: [120] PP           │  FOUNDATION           COMBAT            SPECIAL       │
│ GHO: 640 PP (research efficiency bonus: +100%)               │  ────────────────────────────────────────────────     │
│                                                              │  EL  Economic Lv    3  WEP Weapons     3  TER         │
│ Economic Pool (ERP):     ▓▓▓▓░░░░░░  40 PP   [E+][E-]        │  SL  Science Lv     2  ELI Electronics 2  CLK         │
│   → Improves: EL (Economic Level)                            │                        SLD Shields     2  CIC         │
│   → Current: 120 ERP accumulated, 200 for next level         │                                                       │
│                                                              │  LOGISTICS            DOCTRINE                        │
│ Scientific Pool (SRP):   ▓▓▓▓▓▓░░░░  60 PP   [S+][S-]        │  ────────────────────────────────────────────────     │
│   → Improves: SL (Science Level)                             │  STL Strategic Lift 1  FC  Fleet Cmd    2             │
│   → Gates all other tech research                            │  SC  Strategic Cmd  2  FD  Fighter Doc  1             │
│   → Current: 80 SRP accumulated, 150 for next level          │  CST Construction   2  ACO Adv Carrier  0             │
│                                                              │                                                       │
│ Technical Pool (TRP):    ▓▓░░░░░░░░  20 PP   [T+][T-]        │                                                       │
│   → Improves: WEP, CST, TER, ELI, CLK, SLD, CIC,             │                                                       │
│               STL, FC, SC, FD, ACO                           │                                                       │
│   → Current: 45 TRP accumulated                              │                                                       │
│                                                              │                                                       │
├──────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────┤
│ RECENT BREAKTHROUGHS                                                                                                 │
│                                                                                                                      │
│  T41: Minor breakthrough in Weapons Tech (WEP 2 → 3)  — +10% AS/DS for all ships                                     │
│  T38: Moderate breakthrough in Science (SL 1 → 2)  — New tech trees unlocked                                         │
│  T35: Revolutionary breakthrough in Construction (CST 1 → 2)  — Light Cruiser class unlocked                         │
│                                                                                                                      │
│ TECH EFFECTS SUMMARY                                                                                                 │
│  EL 3: +30% industrial output modifier    WEP 3: +30% AS/DS (compound)    CST 2: +10% dock capacity                  │
│  SL 2: Enables all tech research          ELI 2: +2 detection rolls       SLD 2: 30% bombardment reduction           │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [E/S/T] Adjust pools  [Enter] Confirm allocation  [?] Tech tree details                      [: ] Expert Mode
```

### 6.5 Espionage (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Espionage
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ESPIONAGE BUDGET                                             │ COUNTER-INTELLIGENCE                                  │
│                                                              │                                                       │
│ Espionage Budget Points (EBP): 5 available                   │ CIC Tech Level: 1                                     │
│ Purchase EBP: [___] @ 40 PP each    [B] Buy                  │ Counter-Intel Points (CIP): 3                         │
│                                                              │ Purchase CIP: [___] @ 40 PP each    [C] Buy           │
│ Note: Spending >5% of income on espionage incurs             │                                                       │
│       prestige penalty                                       │ Detection Threshold: 5 (CIC 1 + CIP 3 + base 1)       │
│                                                              │ Enemy ops need to roll > 5 to succeed                 │
├──────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────┤
│ AVAILABLE OPERATIONS                                                                                                 │
│                                                                                                                      │
│  OPERATION               COST   TARGET          EFFECT                                                               │
│  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────   │
│► Tech Theft               5     Enemy Colony    Steal 10 SRP from target house                                       │
│  Sabotage (Low)           2     Enemy Colony    Deal 1d6 IU damage to colony infrastructure                          │
│  Sabotage (High)          7     Enemy Colony    Deal 1d20 IU damage to colony infrastructure                         │
│  Assassination           10     Enemy House     Reduce target SRP gain by 50% for 1 turn                             │
│  Cyber Attack             6     Enemy Starbase  Cripple target starbase                                              │
│  Economic Manipulation    6     Enemy Colony    Halve Net Colony Value for 1 turn                                    │
│  Psyops Campaign          3     Enemy Colony    Reduce tax revenue by 25% for 1 turn                                 │
│  Counter-Intel Sweep      4     Self            Block enemy intel operations for 1 turn                              │
│  Intel Theft              8     Enemy House     Steal intel database (copy their fog-of-war data)                    │
│  Plant Disinformation     6     Enemy House     Add 20-40% variance to their intel for 2 turns                       │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ QUEUED OPERATIONS THIS TURN                                                                                          │
│                                                                                                                      │
│  #   OPERATION          TARGET                    COST                                                               │
│  1.  Tech Theft         House Stratos @ Nova       5 EBP                                                             │
│                                                                                                                      │
│  Total EBP committed: 5    Remaining: 0                                                                              │
│  [+] Add operation    [D] Delete selected                                                                            │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] Queue operation  [T] Select target  [B] Buy EBP  [C] Buy CIP           [: ] Expert Mode
```

### 6.6 Empire Economy (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Economy
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ HOUSE TAX RATE                                                                                                       │
│                                                                                                                      │
│   Current Rate: 52%         Gross House Output (GHO): 640 PP         Net House Value (NHV): 333 PP                   │
│                                                                                                                      │
│   0%       20%       40%       60%       80%      100%                                                               │
│   ├─────────┼─────────┼─────────┼─────────┼─────────┤                                                                │
│   ░░░░░░░░░░░░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓█░░░░░░░░░░              50% ↑ penalty threshold                             │
│                             ▲                                                                                        │
│   [←/→] Adjust    [Enter] Confirm    [Esc] Cancel                                                                    │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ TAX RATE EFFECTS                                             │ TREASURY & INCOME                                     │
│                                                              │                                                       │
│ CURRENT (52%):                                               │ Treasury Balance:     1,820 PP                        │
│   Prestige:     -1/turn (high tax penalty)                   │                                                       │
│   Pop Growth:   ×0.95 modifier                               │ LAST TURN:                                            │
│   IU Growth:    ×0.48 modifier (1 - rate)                    │   Tax Collection:     +333 PP                         │
│                                                              │   Maintenance:        -142 PP                         │
│ IF 40%:                                                      │   Research:           -120 PP                         │
│   Revenue:      256 PP (-77 PP)                              │   Construction:       -200 PP                         │
│   Prestige:     No penalty                                   │   ──────────────────────────────                      │
│   Pop Growth:   ×1.05 (+5% bonus)                            │   Net Change:         -129 PP                         │
│                                                              │                                                       │
│ IF 30%:                                                      │ PROJECTED THIS TURN:                                  │
│   Revenue:      192 PP (-141 PP)                             │   Income:             +333 PP                         │
│   Prestige:     +12/turn (+1 per colony)                     │   Commitments:        -280 PP                         │
│   Pop Growth:   ×1.10 (+10% bonus)                           │   Ending Treasury:    ~1,873 PP                       │
│                                                              │                                                       │
├──────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────┤
│ COLONY INCOME BREAKDOWN                                                                                              │
│                                                                                                                      │
│  COLONY                GCO      NCV     PU GROWTH    IU GROWTH    STATUS                                             │
│  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────   │
│  Valeria Prime (HW)    104       54     +1.4/turn    +0.5/turn    ●                                                  │
│  Bigun                  80       42     +0.8/turn    +0.3/turn    ●                                                  │
│  Thera Gate             44       23     +0.4/turn    +0.2/turn    ●                                                  │
│  Ymir Relay             56       15     +0.6/turn    +0.2/turn    ⚠ Blockaded (-60% NCV)                             │
│  Nova Station           68       35     +0.7/turn    +0.3/turn    ●                                                  │
│  ... (6 more)          288      164                                                                                  │
│  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────   │
│  TOTAL                 640      333                              12 colonies                                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [←/→] Adjust tax  [Enter] Confirm  [I] Industrial investment  [G] Guild transfer             [: ] Expert Mode
```

### 6.7 Reports Inbox (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
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
│  Intel    (3) │     42   Intel         Scout Report: Enemy fleet detected at D6             Today                    │
│  Research (1) │     42   Research      Breakthrough: WEP 2 → 3                              Today                    │
│  Construct(4) │     42   Construction  Starbase completed at Bigun                          Today                    │
│  Colony   (2) │     41   Combat        Skirmish at Ymir - Fleet Zeta damaged                Yesterday                │
│  Diplomacy(1) │     41   Intel         Recon Report: System E3 surveyed                     Yesterday                │
│  Alerts   (1) │     41   Colony        Population growth at Nova Station (+2 PU)            Yesterday                │
│               │     40   Construction  Cruiser commissioned at Valeria Prime                2 days ago               │
│  ────────     │     40   Diplomacy     House Stratos proposes de-escalation                 2 days ago               │
│  Archive  (8) │     40   Alert         Fleet Omega idle - requires orders                   2 days ago               │
│               │                                                                                                      │
└───────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────┘
 15 reports  |  2 unread  |  Filter: All
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select  [Enter] View Report  [D] Delete  [A] Archive  [M] Mark read/unread            [: ] Expert Mode
```

#### 6.7.1 Turn Summary Report

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Reports > Turn 42 Summary
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ TURN 42 SUMMARY                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ EMPIRE OVERVIEW                                                                                                      │
│                                                                                                                      │
│  Colonies: 12 (+2)      Treasury: 1,820 PP (+142)     Prestige: 487 (+12)     Standing: 2nd of 6                     │
│  Fleets:   13           Production: 640 PP/turn       Tax Rate: 52%                                                  │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ KEY EVENTS THIS TURN                                                                                                 │
│                                                                                                                      │
│  COMBAT                                                                                                              │
│    ● Victory at Thera Gate - Fleet Sigma repelled pirate raiders                              [View Report]          │
│                                                                                                                      │
│  RESEARCH                                                                                                            │
│    ● Breakthrough: Weapons Tech WEP 2 → 3 (+10% AS/DS for all ships)                          [View Report]          │
│                                                                                                                      │
│  CONSTRUCTION                                                                                                        │
│    ● Starbase completed at Bigun                                                                                     │
│    ● Cruiser "Hawk" commissioned at Valeria Prime                                                                    │
│                                                                                                                      │
│  INTEL                                                                                                               │
│    ● Scout Lambda detected enemy fleet massing at D6 (est. 8-12 ships)                        [View Report]          │
│                                                                                                                      │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ ACTION REQUIRED                                                                                                      │
│                                                                                                                      │
│  ⚠ 2 fleets awaiting orders (Tau, Omega)                                              [3] Fleet Console              │
│  ⚠ 1 idle shipyard at Bigun                                                           [2] Planet Manager             │
│  ⚠ Fleet Zeta has crippled ships - consider repair orders                             [3] Fleet Details              │
│                                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [2,3] Jump to action  [N] Next report  [Backspace] Back to inbox                             [: ] Expert Mode
```

### 6.8 Messages & Diplomacy (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
 Home > Messages
┌───────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ HOUSES        │ HOUSE STRATOS                                                                                        │
├───────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────┤
│               │                                                                                                      │
│► Stratos  ⚔   │  DIPLOMATIC STATUS: Enemy (since Turn 38)                                                            │
│  Corvus   ●   │  Pending Proposals: 1 received                                                                       │
│  Lyra     ●   │                                                                                                      │
│  Aquila   ⚠   │  ────────────────────────────────────────────────────────────────────────────────────────────────    │
│  Draco    ☠   │  PENDING PROPOSAL (Turn 41, expires Turn 44):                                                        │
│               │  House Stratos proposes: De-escalate Enemy → Hostile                                                 │
│               │                                                                                                      │
│               │  [A] Accept    [R] Reject                                                                            │
│               │  ────────────────────────────────────────────────────────────────────────────────────────────────    │
│               │                                                                                                      │
│               │  MESSAGE HISTORY                                                                                     │
│               │                                                                                                      │
│               │  [T40] FROM STRATOS:                                                                                 │
│               │  "Your scouts have been detected in our territory. Consider this a warning.                          │
│               │   Further incursions will be met with force."                                                        │
│               │                                                                                                      │
│               │  [T40] TO STRATOS:                                                                                   │
│               │  "We seek only to ensure the security of our borders. Perhaps we can discuss                         │
│               │   a mutual arrangement?"                                                                             │
│               │                                                                                                      │
│               │  [T41] FROM STRATOS:                                                                                 │
│               │  "Your 'security concerns' brought war. We offer a cease-fire. Consider it."                         │
│               │                                                                                                      │
│               │  ────────────────────────────────────────────────────────────────────────────────────────────────    │
│               │  [C] Compose message    [P] Propose de-escalation    [N] Set Neutral    [W] Declare Enemy            │
└───────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑/↓] Select house  [L] Diplomatic matrix  [C] Compose  [P] Propose  [A] Accept             [: ] Expert Mode
```

**Diplomatic Actions:**
- `[C]` Compose message - Send text message to house
- `[P]` Propose de-escalation - Offer to reduce hostility (Enemy→Hostile or Hostile→Neutral)
- `[A]` Accept proposal - Accept pending de-escalation proposal
- `[R]` Reject proposal - Reject pending proposal
- `[H]` Declare Hostile - Escalate from Neutral to Hostile
- `[W]` Declare Enemy - Escalate to full war (Enemy status)
- `[N]` Set Neutral - Unilaterally de-escalate (if conditions allow)

### 6.9 Settings (120 columns)

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ EMPIRE: House Valerian  ▸ Turn 42       ★ 487 (2nd)    CR: 1,820    PROD: 640    C2: 82/120 ●       ⚠ 3    ✉ 2       ║
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

## 7. Fleet Commands Reference

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

## 8. Zero-Turn Administrative Commands

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

## 9. ROE Quick Picker Overlay

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

## 10. Colony Automation Flags

From `src/engine/types/colony.nim`:

| Flag               | Default | Description                                        |
|--------------------|---------|----------------------------------------------------|
| `autoRepair`       | ON      | Automatically queue crippled ships for repair      |
| `autoLoadMarines`  | ON      | Load marines onto docked troop transports          |
| `autoLoadFighters` | OFF     | Load fighters onto docked carriers                 |

**Configuration hierarchy**:
1. Global defaults in [9] Settings (apply to new colonies)
2. Per-colony overrides in Planet Manager > Settings tab

---

## 11. Data & Engine Hooks

### State Inputs

Panels consume read-only snapshots via UFCS patterns:
- `state.playerView(houseId)` - Fog-of-war filtered view
- `state.fleetsOwned(houseId)` - Iterator over house fleets
- `state.coloniesOwned(houseId)` - Iterator over house colonies
- `state.colony(colonyId)` - Single colony access
- `state.fleet(fleetId)` - Single fleet access
- `generateLeaderboard(state)` - Public rankings with prestige/colonies

### Public Information (No Fog-of-War)

Available to all players via `PlayerTurnState`:
- `housePrestige: Table[HouseId, int32]` - All house prestige
- `houseColonyCounts: Table[HouseId, int32]` - All house colony counts
- `diplomaticRelations: Table[(HouseId, HouseId), DiplomaticState]` - All relations
- `eliminatedHouses: seq[HouseId]` - Eliminated houses

### Configuration

Colors, hotkeys, animation toggles from `config/ui.kdl`:

```kdl
colors {
    hud_background "navy"
    hud_foreground "amber"
    alert "red"
    selected "cyan"
    prestige "yellow"
}

hotkeys {
    move "m"
    patrol "p"
    hold "h"
    guard "g"
    roe "r"
}

animations {
    speed "normal"  // off, slow, normal, fast
}

notifications {
    auto_open_turn_summary true
    alert_idle_fleets true
    alert_idle_facilities true
}
```

### Testing Harness

Deterministic mock data in `samples/tui/` for layout validation without full simulation.

---

## 12. Milestones

1. **Widget Library** (Sprint 1-2)
   - HUD Strip component with prestige/C2 display
   - Panel with borders (double/single)
   - Status Bar with 9 view keybindings
   - Table with multi-select
   - Leaderboard component

2. **Strategic Overview MVP** (Sprint 3)
   - Three-column layout with leaderboard
   - Recent events ticker
   - Empire status cards (no morale)
   - Action queue with jump hotkeys
   - Diplomatic matrix overlay

3. **Planet Manager MVP** (Sprint 4-5)
   - Colony list view (GCO, NCV, Growth columns)
   - Detail view with all 5 tabs
   - Economy tab with growth projections
   - Construction queue management

4. **Fleet Console MVP** (Sprint 6-7)
   - System view (grouped by location)
   - List view with multi-select
   - Fleet detail panel
   - ROE picker overlay

5. **Research Screen MVP** (Sprint 8)
   - Tech level display grid
   - ERP/SRP/TRP allocation controls
   - Breakthrough history

6. **Espionage Screen MVP** (Sprint 9)
   - EBP/CIP budget management
   - Operation queue
   - Target selection

7. **Economy Screen MVP** (Sprint 10)
   - House tax rate slider with impact preview
   - Treasury and income breakdown
   - Colony income table
   - Industrial investment interface

8. **Reports Inbox MVP** (Sprint 11)
   - Email-style 3-column layout
   - Category filtering
   - Turn summary auto-open
   - Report detail views

9. **Messages & Diplomacy MVP** (Sprint 12)
   - House list with status icons
   - Conversation history
   - De-escalation proposals
   - Diplomatic actions

10. **Expert Mode & Polish** (Sprint 13-14)
    - Command palette (`:` prefix)
    - Tab completion
    - Command history
    - 80-column fallback layouts
    - Accessibility review

---

## 13. Risks & Mitigations

| Risk                      | Mitigation                                              |
|---------------------------|---------------------------------------------------------|
| Information overload      | Progressive disclosure; default to summary, drill down  |
| Input latency             | Buffered rendering, differential updates                |
| 80-col degradation        | Explicit fallback layouts tested, column stacking       |
| Legacy expectations       | Classic Layout toggle, legacy hotkey support            |
| Expert mode complexity    | Tab completion, inline help, error messages             |
| 9 views too many          | Clear categorization, hotkey shortcuts, breadcrumbs     |

---

## 14. Success Metrics

1. **Onboarding**: New players complete full turn (set tax, research, fleet orders) without manual
2. **Recognition**: EC veterans identify classic references (colors, stat slabs, hotkeys)
3. **Responsiveness**: <100ms feedback on all input actions
4. **Readability**: Interface legible on 80x24 terminals without horizontal scrolling
5. **Expert efficiency**: Power users issue 5+ commands/minute via Expert Mode
6. **Strategic awareness**: Players can assess competitive standing (leaderboard) at a glance

---

## Appendix: 80-Column Fallback Examples

### Strategic Overview (80 columns)

```
╔════════════════════════════════════════════════════════════════════════════╗
║ VALERIAN ▸ T42  ★487 (2nd)  CR:1820  PROD:640  C2:82/120●  ⚠3  ✉2          ║
╚════════════════════════════════════════════════════════════════════════════╝
 Home > Overview
┌──────────────────────────────────────────────────────────────────────────────┐
│ LEADERBOARD              │ EMPIRE STATUS                                     │
│ 1.Valerian ★487 12 YOU   │ Colonies: 12    Fleets: 13                        │
│ 2.Stratos  ★412  9 ⚔ENM  │ Tax: 52%        Growth: +1.4 PU/turn              │
│ 3.Corvus   ★356  8 ●NEU  │ Neutral:3 Hostile:1 Enemy:1                       │
│ 4.Lyra     ★298  7 ●NEU  │                                                   │
│ 5.Aquila   ★201  5 ⚠HOS  │ ACTION QUEUE                                      │
│ 6.Draco    ELIM  0 ☠     │ ⚠ 1 Idle shipyard             [C]                 │
│ Map: 41/64 colonized     │ ⚠ 2 Fleets w/o orders         [F]                 │
│ [L] Diplomatic matrix    │ ✉ 1 Unread report             [R]                 │
└──────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Alt+Key Views  [Alt+Q]Quit  [L]Diplo Matrix                  [:] Expert Mode
```

### Fleet List (80 columns)

```
╔════════════════════════════════════════════════════════════════════════════╗
║ VALERIAN ▸ T42  ★487 (2nd)  CR:1820  PROD:640  C2:82/120●  ⚠3  ✉2          ║
╚════════════════════════════════════════════════════════════════════════════╝
 Home > Fleets
┌──────────────────────────────────────────────────────────────────────────────┐
│ FLEET        LOC      SHIPS  AS   COMMAND      DEST   ETA  ROE  STATUS       │
├──────────────────────────────────────────────────────────────────────────────┤
│ Alpha        B7          8   64   Guard Col    —      —     6   ●            │
│ Beta         B7          4   24   Reserve      —      —     8   RSV          │
│►►Sigma       C4         12   96   Patrol       D5     2t    6   ●            │
│[X]Tau        C4          4   32   Hold         —      —     6   ⚠IDLE        │
│[X]Omega      C4          8   64   (none)       —      —     6   ⚠IDLE        │
│ Lambda       D2          1    4   Scout Sys    E3     4t    2   ●            │
│ Petra        D2          5   20   Colonize     F1     3t    6   ●            │
│ Gamma        A3          6   48   Mothball     —      —     —   MTB          │
└──────────────────────────────────────────────────────────────────────────────┘
 13 fleets | 2 selected | Batch: [M]Move [J]Join [V]Rndzvs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [↑↓]Sel [X]Toggle [Enter]Details [S]Sort [F]Filter           [:] Expert Mode
```

### Economy View (80 columns)

```
╔════════════════════════════════════════════════════════════════════════════╗
║ VALERIAN ▸ T42  ★487 (2nd)  CR:1820  PROD:640  C2:82/120●  ⚠3  ✉2          ║
╚════════════════════════════════════════════════════════════════════════════╝
 Home > Economy
┌──────────────────────────────────────────────────────────────────────────────┐
│ HOUSE TAX RATE: 52%           GHO: 640 PP       NHV: 333 PP                  │
│ 0%━━━━━━━20%━━━━━━━40%━━━━━━━60%━━━━━━━80%━━━━━100%                          │
│ ░░░░░░░░░░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓█░░░░░░░░░░░    [←/→] Adjust               │
│                         ▲ 50% penalty threshold                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ EFFECTS (52%):                 │ TREASURY:                                   │
│   Prestige: -1/turn penalty    │   Balance:    1,820 PP                      │
│   Pop Growth: ×0.95            │   Last turn:  -129 PP                       │
│   IU Growth: ×0.48             │   Projected:  +53 PP                        │
├──────────────────────────────────────────────────────────────────────────────┤
│ COLONY          GCO   NCV  GROWTH  STATUS                                    │
│ Valeria Prime   104    54  +1.4    ●                                         │
│ Bigun            80    42  +0.8    ●                                         │
│ Thera Gate       44    23  +0.4    ●                                         │
│ ... (9 more)    412   214                                                    │
│ TOTAL           640   333          12 colonies                               │
└──────────────────────────────────────────────────────────────────────────────┘
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [←/→]Tax [Enter]Confirm [I]Invest [G]Guild                   [:] Expert Mode
```

---

**Document Version**: 2.1
**Last Updated**: 2026-01-17
**Status**: Design specification - added Entry Screen Modal (Section 5)
