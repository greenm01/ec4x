# Engine Refactoring Proposal (2025-12-19)

## 1. Introduction & Goals

This document outlines a refactoring plan for the EC4X engine. The current structure contains several large, monolithic files (`combat_resolution.nim`, `executor.nim`, `zero_turn_commands.nim`) where responsibilities are cluttered.

The primary goals of this refactoring are to:

1.  **Align with Canonical Turn Cycle**: Structure the codebase to directly mirror the phases and steps defined in `ec4x_canonical_turn_cycle.md`.
2.  **Adhere to DoD & DRY**: Strictly follow the Data-Oriented Design and Don't Repeat Yourself principles from `CLAUDE.md`.
3.  **Improve Maintainability**: Break down large files into smaller, single-responsibility modules.
4.  **Clarify Separation of Concerns**: Create clear boundaries between core data types, domain-specific game systems, and the turn cycle orchestration.

## 2. Proposed Directory Structure

I recommend reorganizing the `src/engine/` directory to better separate data, systems, and orchestration.

```
src/engine/
├── types/                 # Core data structures
│   ├── core.nim           # GameState, House, Colony
│   ├── map/               # Map-related asset types
│   │   ├── types.nim      # Hex, System, JumpLane, PathResult, StarMapError
│   │   └── starmap_definition.nim # StarMap object definition
│   └── military/          # Military asset types
│       ├── ship_types.nim
│       ├── squadron_types.nim
│       ├── fleet_types.nim
│       └── ground_unit_types.nim
│
├── systems/               # Domain-specific logic modules (behavior)
│   ├── combat/            # Combat resolution logic
│   ├── economy/           # Economic calculations
│   ├── orders/            # Order execution logic
│   ├── starmap_engine/      # Starmap generation, pathfinding, and validation
│   └── military_assets/   # Logic for ship/squadron/fleet operations
│
└── turn_cycle/            # Orchestration of the turn cycle
```

**Rationale:**
-   **`types/`**: Consolidates all core data structures, enforcing the DoD principle of separating data from behavior. This makes the game state easy to understand and serialize.
-   **`systems/`**: Contains pure logic modules that operate on the data from `types/`. Each sub-directory represents a distinct game system (Combat, Economy, etc.), making the codebase modular.
-   **`turn_cycle/`**: Directly maps to `ec4x_canonical_turn_cycle.md`. These modules are orchestrators that call the appropriate logic from `systems/` in the correct sequence.

## 3. Key Refactoring Targets

### `src/engine/gamestate.nim`

This file currently mixes core type definitions with a multitude of helper functions.

-   **Action**: Move all type definitions (`GameState`, `House`, `Colony`) into the new `src/engine/types/` directory (e.g., `core.nim`). **[COMPLETED]**
-   **Action**: Move helper functions and queries to the relevant modules within `src/engine/systems/`. **[COMPLETED]**
-   **Action**: Relocate game initialization functions to `src/engine/initialization/`. **[COMPLETED]**

### `src/engine/starmap.nim` (and map types)

This file mixes data definitions (`Hex`, `System`, `StarMap`) with complex logic.

-   **Action**: Create `src/engine/types/map/` directory for all map-related data definitions. **[COMPLETED]**
-   **Action**: Move `Hex`, `System`, `JumpLane`, `PathResult`, and `StarMapError` to `src/engine/types/map/types.nim`. **[COMPLETED]**
-   **Action**: Move `StarMap` object definition to `src/engine/types/map/starmap_definition.nim`. **[COMPLETED]**
-   **Action**: Create `src/engine/systems/starmap_engine/` and move all generation, pathfinding, and validation logic from `starmap.nim` to `engine.nim` within it. **[COMPLETED]**
-   **Action**: Delete the original `starmap.nim`. **[COMPLETED]**

### `src/engine/ship.nim`, `squadron.nim`, `fleet.nim` (and military types)

These files mix data definitions with operational logic and are not integrated into the `types`/`systems` structure.

-   **Action**: Create `src/engine/types/military/` directory for all military asset data definitions. **[IN PROGRESS]**
-   **Action**: Move `Ship`, `ShipCargo`, `CargoType` to `src/engine/types/military/ship_types.nim`.
-   **Action**: Move `Squadron`, `SquadronType`, `SquadronFormation` to `src/engine/types/military/squadron_types.nim`.
-   **Action**: Move `Fleet`, `FleetStatus` to `src/engine/types/military/fleet_types.nim`.
-   **Action**: Move `GroundUnit` and related types from `planetary.nim` to `src/engine/types/military/ground_unit_types.nim`.
-   **Action**: Create `src/engine/systems/military_assets/` and move remaining logic from `ship.nim`, `squadron.nim`, and `fleet.nim` into new modules within it (e.g., `ship_ops.nim`, `squadron_ops.nim`, `fleet_ops.nim`).
-   **Action**: Delete the original `ship.nim`, `squadron.nim`, and `fleet.nim` files.

## 4. Current Status Summary

### Phase 1: Reorganization

*   **Status:** [COMPLETED]
*   **Details:** The primary directory structure is in place and populated with initial files.

### Phase 2: State/Behavior Separation

*   **Status:** [IN PROGRESS]
*   **Details:**
    *   **`gamestate.nim`**: Fully decomposed. **[COMPLETED]**
    *   **`starmap.nim`**: Fully decomposed into `types/map/` and `systems/starmap_engine/`. **[COMPLETED]**
    *   **`ship.nim`, `squadron.nim`, `fleet.nim`**: Pending decomposition into `types/military/` and `systems/military_assets/`.

### Phase 3: System Decomposition

*   **Status:** [COMPLETED - Structural Refactoring]
*   **Details:** All monolithic files related to turn resolution and order execution (`combat_resolution.nim`, `fleet_orders.nim`, `executor.nim`, `zero_turn_commands.nim`) have been fully decomposed into single-responsibility modules under `systems/`.

## 5. Phased Rollout Plan

1.  **Phase 1: Reorganization.** Create the new directory structure. **[COMPLETED]**
2.  **Phase 2: State/Behavior Separation.** Refactor monolithic modules to separate data (`types`) from logic (`systems`). This is the current focus for `ship.nim`, `squadron.nim`, and `fleet.nim`. **[IN PROGRESS]**
3.  **Phase 3: System Decomposition.** Decompose large systems into smaller, single-responsibility modules. **[COMPLETED]**

This iterative approach will allow for testing at each stage and ensure the engine remains functional throughout the refactoring process.

## 6. Alignment with Game Specifications

The new structure with `types/military/` and `systems/military_assets/` will bring `Ship`, `Squadron`, and `Fleet` assets into alignment with the DoD principles and the rest of the refactored engine.
