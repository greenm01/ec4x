# SVG Starmap Export Specification

## Overview

The TUI focuses on what terminals do best: data entry, lists, status displays,
and command input. For spatial reference, players export an SVG starmap that
visualizes system positions and jump lane connections as a **node-edge graph**.

**Design Rationale**: 

1. ANSI terminals can't render arbitrary angles (hex topology needs 60°)
2. Hex polygon outlines add visual noise without information value
3. A node-edge graph shows exactly what matters: systems and connections
4. SVG scales cleanly for any map size

---

## Coordinate System

Human-friendly **ring + position** labels derived from axial coordinates:

| Ring | Label Pattern | Hex Count | Example |
|------|---------------|-----------|---------|
| 0 (Hub) | `H` | 1 | `H` |
| 1 | `A1` - `A6` | 6 | `A3` |
| 2 | `B1` - `B12` | 12 | `B7` |
| 3 | `C1` - `C18` | 18 | `C12` |
| N | `[letter][1-6N]` | 6N | ... |

**Position numbering**: Starts at 12 o'clock, proceeds clockwise.

**Letter assignment**: Ring 1 = A, Ring 2 = B, ... Ring 26 = Z.

**Node positioning**: Uses hex-to-pixel math to place nodes in concentric rings:
- Hub at center
- Ring 1 forms inner hexagon of 6 nodes
- Ring 2 forms outer hexagon of 12 nodes
- etc.

---

## Output

### File Location

```
~/.ec4x/maps/<game_id>/turn_<N>.svg
```

- Creates directory hierarchy if needed
- Each turn generates a new file (preserves history)
- TUI command prints path for easy access

### TUI Commands

```
map export    # Generate SVG for current turn, print file path
map open      # Generate + open in default viewer (xdg-open on Linux)
```

---

## Visual Design: Node-Edge Graph

### Layout

- **Background**: Black (#000000)
- **Center**: Hub node at SVG center
- **Rings**: Concentric circles of nodes, spacing increases per ring
- **Scale**: Auto-fit to viewport with padding

### Nodes (Systems)

Systems rendered as **circles** with size/style by type:

| System Type | Radius | Fill | Stroke |
|-------------|--------|------|--------|
| Hub | 14px | Gold (#B8860B) | White 2px |
| Your Homeworld | 12px | House color | White 2px |
| Your Colony | 10px | House color | None |
| Enemy Colony | 10px | Transparent | Enemy house color 2px |
| Neutral/Unknown | 6px | Dark gray (#333) | White 1px |

**Ownership colors** (outline for enemies, fill for own):
- Unowned/unknown: White outline
- Owned colony: House color fill
- Enemy colony: Enemy house color outline (if intel gathered)

### Edges (Jump Lanes)

Lines connecting system centers:

| Lane Type | Color | Line Style | Width |
|-----------|-------|------------|-------|
| Major | Gold (#B8860B) | Solid | 3px |
| Minor | Steel Blue (#4682B4) | Dashed (8,4) | 2px |
| Restricted | Dark Red (#8B0000) | Dotted (3,3) | 1.5px |

**Rendering order**: Lanes drawn first (behind nodes).

### Labels

Each system has a label showing:
- Line 1: System name (e.g., "Arcturus")
- Line 2: Coordinate (e.g., "A3")
- Line 3: Planet info if known (e.g., "LU/VR")

**Label placement**: Below node, centered. For dense areas, labels may need
smart positioning to avoid overlap.

**Label visibility**: All system names and coordinates shown (topology is
public knowledge). Planet details only shown if intel gathered.

### Legend

Embedded in SVG corner containing:

**Node Types**:
- Hub (large gold circle)
- Your colony (medium filled)
- Enemy colony (medium outline)
- Neutral (small gray)

**Lane Types**:
- Major (gold solid)
- Minor (blue dashed)
- Restricted (red dotted)

**Planet Class Codes**:
- `EX` = Extreme, `DE` = Desolate, `HO` = Hostile
- `HA` = Harsh, `BE` = Benign, `LU` = Lush, `ED` = Eden

**Resource Codes**:
- `VP` = Very Poor, `P` = Poor, `A` = Abundant
- `R` = Rich, `VR` = Very Rich

**House Colors**: Colored squares with house names

---

## Fog-of-War Handling

The SVG shows **what the player knows**:

| Visibility Level | Node Style | Label | Planet Details |
|------------------|------------|-------|----------------|
| Owned | Filled, house color | Name + Coord | Class + Resources |
| Occupied | Filled, house color | Name + Coord | Class + Resources |
| Scouted | Outline only | Name + Coord | Class + Resources |
| Adjacent | Small gray | Name + Coord | Omitted |
| None | Small gray | Name + Coord | Omitted |

**Key principle**: Topology (node positions, lane connections, system names,
coordinates) is always visible. Planet details and ownership colors only
appear if the house has gathered intel.

---

## Implementation

### Modules

```
src/player/svg/
├── starmap_export.nim   # Main SVG generation
├── node_layout.nim      # Hex-to-pixel positioning
├── svg_builder.nim      # SVG string building utilities
└── export.nim           # File I/O, directory creation
```

### Dependencies

- **None external** - pure Nim string generation
- Reuses: `hex_labels.nim` (coordinates), `adapters.nim` (fog-of-war)

### Key Functions

```nim
# Node positioning (hex coords to pixel coords)
proc hexToPixel*(q, r: int, scale: float, center: Point): Point

# SVG generation
proc generateStarmap*(state: GameState, houseId: HouseId): string

# File export
proc exportToFile*(svg: string, gameId: string, turn: int): string
```

### Hex-to-Pixel Algorithm

For flat-top hex layout:

```nim
proc hexToPixel*(q, r: int, scale: float, cx, cy: float): (float, float) =
  let x = scale * (3.0/2.0 * float(q))
  let y = scale * (sqrt(3.0)/2.0 * float(q) + sqrt(3.0) * float(r))
  (cx + x, cy + y)
```

This positions nodes so that:
- Hub (0,0) is at center
- Ring 1 nodes form a hexagon around hub
- Lanes connecting neighbors are roughly equal length

---

## SVG Structure

```svg
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     viewBox="0 0 1000 1000"
     style="background-color: #000000">
  
  <defs>
    <style>
      /* Lane styles */
      .lane { stroke-linecap: round; }
      .lane-major { stroke: #B8860B; stroke-width: 3; }
      .lane-minor { stroke: #4682B4; stroke-width: 2; 
                    stroke-dasharray: 8,4; }
      .lane-restricted { stroke: #8B0000; stroke-width: 1.5; 
                         stroke-dasharray: 3,3; }
      
      /* Node styles */
      .node { }
      .node-hub { fill: #B8860B; stroke: #FFF; stroke-width: 2; }
      .node-own { stroke: none; }
      .node-enemy { fill: transparent; stroke-width: 2; }
      .node-neutral { fill: #333; stroke: #FFF; stroke-width: 1; }
      
      /* Label styles */
      .label { fill: #FFF; font-family: monospace; 
               text-anchor: middle; font-size: 10px; }
      .label-name { font-weight: bold; }
      .label-coord { fill: #AAA; font-size: 9px; }
      .label-info { fill: #888; font-size: 8px; }
    </style>
  </defs>
  
  <!-- Jump lanes (rendered first, behind nodes) -->
  <g id="lanes">
    <line class="lane lane-major" x1="500" y1="500" x2="560" y2="450"/>
    <line class="lane lane-minor" x1="500" y1="500" x2="440" y2="450"/>
    <!-- ... more lanes ... -->
  </g>
  
  <!-- System nodes -->
  <g id="nodes">
    <circle class="node node-hub" cx="500" cy="500" r="14"/>
    <circle class="node node-own" cx="560" cy="450" r="10" 
            style="fill: #4169E1"/>
    <circle class="node node-neutral" cx="440" cy="450" r="6"/>
    <!-- ... more nodes ... -->
  </g>
  
  <!-- Labels -->
  <g id="labels">
    <g transform="translate(500, 530)">
      <text class="label label-name" y="0">Sol</text>
      <text class="label label-coord" y="12">H</text>
      <text class="label label-info" y="22">ED/VR</text>
    </g>
    <!-- ... more labels ... -->
  </g>
  
  <!-- Legend -->
  <g id="legend" transform="translate(30, 30)">
    <!-- Node type examples -->
    <!-- Lane type examples -->
    <!-- Code key -->
  </g>
  
</svg>
```

---

## TUI System List View

In addition to SVG export, the TUI provides a **text-mode system list** for
viewing connectivity without graphics.

### Display Format

```
═══ Systems ═══════════════════════════════════════════════════
 H   Hub         ━━ A1 A2 A3 A4 A5 A6
 A1  Arcturus    ━━ H ┄┄ A2 A6 ━━ B1 ·· B2    [You: Valerian]
 A2  Vega        ┄┄ H A1 A3 ━━ B2 B3
 A3  Rigel       ━━ H ┄┄ A2 A4 ━━ B4 B5       [Harkonnen]
 ...

═══ Selected: A1 Arcturus ═════════════════════════════════════
 Owner:     House Valerian (You)
 Planet:    Lush (Level VI)
 Resources: Very Rich
 
 Connections:
   ━━ H   Hub           Major
   ┄┄ A2  Vega          Minor
   ┄┄ A6  Deneb         Minor
   ━━ B1  Altair        Major
   ·· B2  Capella       Restricted
```

### Lane Symbols

- `━━` Major lane
- `┄┄` Minor lane  
- `··` Restricted lane

### View Mode

Accessed via `S` key in TUI (Systems view), or integrated into Map mode.

---

## Status

**Implementation Status:**

- [x] Coordinate label conversion (`hex_labels.nim`)
- [x] TUI detail panel shows labels
- [x] Specification complete (this document)
- [x] SVG generation module (`starmap_export.nim`)
- [x] Hex-to-pixel node positioning (`node_layout.nim`)
- [x] File I/O and directory management (`file_export.nim`)
- [x] SAM actions/acceptors for export command
- [x] TUI system list widget (`system_list.nim`)
- [x] Command integration in TUI (`X` = export, `S` = export & open)

---

## Future Enhancements

- Interactive SVG with hover tooltips (embedded JS)
- PDF export option
- Turn-over-turn animation/diff visualization
- Print-friendly version (white background)
- Zoom to region of interest
- Path highlighting (show route between two systems)
