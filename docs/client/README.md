# EC4X Player Client Architecture

The EC4X player client is a desktop application built with Sokol (windowing,
graphics) and Nuklear (immediate-mode UI). It uses the SAM (State-Action-Model)
pattern for state management.

## Technology Stack

- **Sokol App** - Cross-platform window/input management
- **Sokol GFX** - Low-level GPU abstraction (OpenGL/Metal/D3D11/WebGPU)
- **Sokol GL** - Immediate-mode 2D/3D drawing on GPU
- **Sokol Nuklear** - Nuklear UI integration with Sokol
- **Nuklear** - Immediate-mode UI widgets

## File Structure

```
src/client/
├── main.nim                 # Entry point, Sokol callbacks, frame loop
├── c_impl.c                 # C implementations for Sokol/Nuklear headers
│
├── bindings/                # Nim bindings for C libraries
│   ├── sokol.nim            # Sokol App + GFX types and functions
│   ├── sokol_gl.nim         # Sokol GL immediate-mode 2D drawing
│   ├── sokol_nuklear.nim    # Nuklear integration with Sokol
│   └── nuklear.nim          # Nuklear UI primitives
│
├── core/                    # Framework components
│   └── sam.nim              # Generic SAM pattern implementation
│
├── model/                   # Application state
│   └── state.nim            # ClientModel, UiState, StarmapState, etc.
│
├── logic/                   # State mutations and side effects
│   ├── actions.nim          # Action creators (return Proposals)
│   ├── acceptors.nim        # State mutation functions
│   └── reactors.nim         # Side effects, async responses
│
├── starmap/                 # Starmap rendering and interaction
│   ├── hex_math.nim         # Hex coordinate <-> pixel conversions
│   ├── camera.nim           # Camera2D, zoom/pan, screen<->world transforms
│   ├── theme.nim            # Load colors from config/dynatoi.kdl
│   ├── renderer.nim         # Draw starmap with sokol_gl
│   └── input.nim            # Mouse/keyboard handling for starmap
│
├── ui/                      # Nuklear UI views
│   └── view.nim             # Screen rendering (login, dashboard, etc.)
│
├── reports/                 # Game data presentation
│   └── turn_report.nim      # Format turn events for display
│
└── vendor/                  # Third-party C headers
    ├── sokol_app.h
    ├── sokol_gfx.h
    ├── sokol_gl.h
    ├── sokol_glue.h
    └── nuklear.h
```

## Data Flow (SAM Pattern)

The client uses the SAM (State-Action-Model) pattern for unidirectional data
flow:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Frame Loop                                    │
│                                                                          │
│   sokol_app callbacks:                                                   │
│   - init()    → Initialize Sokol GFX, Sokol GL, Nuklear, SAM loop       │
│   - frame()   → Process SAM queue, render starmap, render UI            │
│   - event()   → Convert Sokol events to SAM proposals                   │
│   - cleanup() → Shutdown resources                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            SAM Loop                                      │
│                                                                          │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────────────────┐  │
│   │   Actions    │      │   Acceptors  │      │       Model          │  │
│   │              │      │              │      │                      │  │
│   │ zoomStarmap  │─────▶│   Execute    │─────▶│  ClientModel         │  │
│   │ panStarmap   │      │   payload    │      │  ├─ ui: UiState      │  │
│   │ selectSystem │      │   procs      │      │  ├─ starmap: ...     │  │
│   │ navigateTo   │      │              │      │  └─ playerState: ... │  │
│   │ login        │      └──────────────┘      │                      │  │
│   └──────────────┘             │              └──────────────────────┘  │
│          ▲                     │                         │              │
│          │                     ▼                         │              │
│          │              ┌──────────────┐                 │              │
│          │              │   Reactors   │                 │              │
│          │              │              │                 │              │
│          └──────────────│ Observe model│◀────────────────┘              │
│                         │ Dispatch new │                                │
│                         │ proposals    │                                │
│                         └──────────────┘                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Rendering                                      │
│                                                                          │
│   1. sg_begin_pass()     ─── Clear screen to background color           │
│   2. renderStarmap()     ─── sokol_gl: lanes, hexes, selection          │
│   3. sgl_draw()          ─── Submit sokol_gl draw commands              │
│   4. snk_render()        ─── Nuklear UI on top (windows, buttons, etc.) │
│   5. sg_end_pass()       ─── Finalize frame                             │
│   6. sg_commit()         ─── Present to screen                          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Starmap Rendering Pipeline

The starmap is rendered directly to the GPU using sokol_gl for smooth zoom/pan:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       Starmap Render Pipeline                            │
│                                                                          │
│   Game State (read-only)                                                 │
│   ├─ Systems: Table[SystemId, System]                                   │
│   ├─ Lanes: JumpLanes (adjacency + lane types)                          │
│   └─ Colonies: Table[ColonyId, Colony] (for ownership colors)           │
│                          │                                               │
│                          ▼                                               │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                    Camera Transform                               │  │
│   │                                                                   │  │
│   │   sgl_matrix_mode_projection()                                    │  │
│   │   sgl_ortho(0, width, height, 0, -1, 1)                          │  │
│   │   sgl_translate(camera.offset.x, camera.offset.y, 0)             │  │
│   │   sgl_translate(-camera.target.x * zoom, -camera.target.y * zoom)│  │
│   │   sgl_scale(camera.zoom, camera.zoom, 1)                         │  │
│   │                                                                   │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                          │                                               │
│                          ▼                                               │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                     Draw Order                                    │  │
│   │                                                                   │  │
│   │   1. Jump Lanes (lines)                                           │  │
│   │      - Major:      darkgoldenrod (#B8860B)                        │  │
│   │      - Minor:      steelblue (#4682B4)                            │  │
│   │      - Restricted: darkred (#8B0000)                              │  │
│   │                                                                   │  │
│   │   2. Hex Grid Outlines (6-vertex line loops)                      │  │
│   │      - gridLineColor: charcoal (#404040)                          │  │
│   │                                                                   │  │
│   │   3. System Markers (filled hexes or dots)                        │  │
│   │      - Owned: house color from dynatoi.kdl                        │  │
│   │      - Unowned: ivory (#FFFFF0)                                   │  │
│   │                                                                   │  │
│   │   4. Selection/Hover Highlight                                    │  │
│   │      - Thicker outline on hovered/selected system                 │  │
│   │                                                                   │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                          │                                               │
│                          ▼                                               │
│                     sgl_draw()                                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Coordinate Systems

### Hex Coordinates (Axial)

The starmap uses axial hex coordinates (q, r) from the game engine:

```
        ___
    ___/   \___
   /   \ 0,0/   \
   \___/   \___/
   /   \___/   \
   \-1,1   \ 1,0
       \___/
```

### Pixel Coordinates (Flat-Top Hex)

Conversion for flat-top hexes:

```nim
proc hexToPixel(hex: Hex, size: float32): Vec2 =
  let x = size * (3.0/2.0 * hex.q.float32)
  let y = size * (sqrt(3.0)/2.0 * hex.q.float32 + sqrt(3.0) * hex.r.float32)
  vec2(x, y)

proc pixelToHex(point: Vec2, size: float32): Hex =
  let q = (2.0/3.0 * point.x) / size
  let r = (-1.0/3.0 * point.x + sqrt(3.0)/3.0 * point.y) / size
  hexRound(q, r)
```

### Screen vs World Coordinates

```
Screen Space                    World Space
(0,0)────────────▶ x           Camera transforms:
  │                            - offset: screen center point
  │    [Nuklear UI]            - target: world position to look at
  │                            - zoom: scale factor (1.0 = default)
  │    [Starmap]
  ▼                            screenToWorld(pos) = (pos - offset) / zoom + target
  y                            worldToScreen(pos) = (pos - target) * zoom + offset
```

## Input Handling

Starmap input is processed in the Sokol event callback:

| Input | Action |
|-------|--------|
| Mouse wheel | Zoom toward cursor position |
| Middle-drag | Pan the camera |
| Mouse move | Update hovered system |
| Left click | Select system |
| Escape | Deselect / close panels |

## Configuration

Starmap colors are loaded from `config/dynatoi.kdl`:

```kdl
theme name="dynatoi" {
    starmap {
        backgroundColor "#000000"
        majorLaneColor "#B8860B"
        minorLaneColor "#4682B4"
        restrictedLaneColor "#8B0000"
        unownedColonyColor "#FFFFF0"
        gridLineColor "#404040"
    }
    
    house0Name "Valerian"
    house0Color "#4169E1"
    // ... 11 more houses
}
```

## See Also

- [Engine Architecture](../architecture/overview.md) - Server-side game engine
- [Game Specification](../specs/index.md) - Game rules and mechanics
- [SAM Pattern](https://sam.js.org/) - State-Action-Model pattern reference
