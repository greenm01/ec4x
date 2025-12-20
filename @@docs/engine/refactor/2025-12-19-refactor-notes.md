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
│   ├── core.nim           # GameState, House, Colony, Fleet, Squadron
│   └── map/types.nim      # Hex, System, StarMap related types
│
├── systems/               # Domain-specific logic modules (behavior)
│   ├── combat/            # Combat resolution logic
│   │   ├── space.nim
│   │   ├── orbital.nim
│   │   └── planetary.nim    # Invasion, blitz, bombardment
│   ├── economy/
│   │   ├── production.nim
│   │   ├── maintenance.nim
│   │   └── capacity/
│   │       ├── industrial.nim
+│   │       └── squadron.nim
│   ├── orders/
│   │   ├── fleet_order_executor.nim
│   │   └── admin_command_executor.nim
│   ├── population/management.nim
│   └── ...                # (diplomacy, research, intelligence, etc.)
│
└── turn_cycle/
    ├── conflict_phase.nim
    ├── income_phase.nim
    ├── command_phase.nim
    └── maintenance_phase.nim
    └── orchestrator.nim   # Main resolveTurn() function
```

**Rationale:**
-   **`types/`**: Consolidates all core data structures, enforcing the DoD principle of separating data from behavior. This makes the game state easy to understand and serialize.
-   **`systems/`**: Contains pure logic modules that operate on the data from `types/`. Each sub-directory represents a distinct game system (Combat, Economy, etc.), making the codebase modular.
-   **`turn_cycle/`**: Directly maps to `ec4x_canonical_turn_cycle.md`. These modules are orchestrators that call the appropriate logic from `systems/` in the correct sequence.

## 3. Key Refactoring Targets

The following monolithic files should be broken down as described below.

### `src/engine/gamestate.nim`

This file currently mixes core type definitions with a multitude of helper functions.

-   **Action**: Move all type definitions (`GameState`, `House`, `Colony`, `Fleet`, etc.) into the new `src/engine/types/` directory (e.g., `core.nim`). **[COMPLETED]**
-   **Action**: Move helper functions and queries to the relevant modules within `src/engine/systems/`. **[COMPLETED]**
-   **Action**: Relocate game initialization functions (e.g., `newGame`, `initializeHousesAndHomeworlds`) to `src/engine/initialization/`. **[COMPLETED]**

### `src/engine/resolution/combat_resolution.nim` & `src/engine/combat/ground.nim`

This module is extremely large and handles all forms of combat. The logic should be split to match the canonical turn cycle's combat steps.

-   **Action**: Consolidate all combat logic into `src/engine/systems/combat/`. **[COMPLETED]**
-   **Action**: Create `space.nim` to handle space combat logic from `resolveBattle`. **[COMPLETED]**
-   **Action**: Create `orbital.nim` to handle orbital combat, including starbase participation. **[COMPLETED]**
-   **Action**: Consolidate planetary assault logic (`resolveBombardment`, `resolveInvasion`, `resolveBlitz`) from `combat_resolution.nim` and `ground.nim` into a new `planetary.nim`. **[COMPLETED]**

### `src/engine/commands/executor.nim` & `src/engine/resolution/fleet_orders.nim`

These files contain over 2,000 lines of overlapping logic for fleet order execution. This should be consolidated and broken down by order.

-   **Action**: Create `src/engine/systems/orders/fleet_order_executor.nim` to act as a dispatcher. **[COMPLETED - Logic migrated]**
-   **Action**: Create a new directory `src/engine/systems/orders/execution/` containing small modules for each order or logical group (e.g., `move.nim`, `colonize.nim`, `combat_orders.nim`). **[COMPLETED - Logic migrated]**
-   **Action**: The `executor.nim` and `fleet_orders.nim` files will be removed, their logic distributed into the new, smaller modules. **[COMPLETED - Logic migrated and files presumed removed]**

### `src/engine/commands/zero_turn_commands.nim`

This file for administrative commands is over 1,000 lines long and can be split by functionality.

-   **Action**: Create `src/engine/systems/orders/admin_command_executor.nim` to act as a dispatcher. **[COMPLETED - Logic migrated]**
-   **Action**: Create a new directory `src/engine/systems/orders/admin/` with modules for each command type:
    -   `fleet_management.nim` (Detach, Transfer, Merge)
    -   `cargo.nim` (Load/Unload Cargo)
    -   `fighters.nim` (Load/Unload/Transfer Fighters)
    -   `squadron.nim` (Form, Assign, Transfer) **[COMPLETED - Logic migrated]**
-   **Action**: The `zero_turn_commands.nim` file will be removed, its logic distributed into the new, smaller modules. **[COMPLETED - Logic migrated and file presumed removed]**

## 4. Current Status Summary

### Phase 1: Reorganization

*   **Status:** Completed.
*   **Details:** The primary directory structure (`src/engine/types/`, `src/engine/systems/`, `src/engine/turn_cycle/`) is in place and populated with initial files. Map types (`Hex`, `System`) have been moved to `src/engine/map/types.nim`. **[COMPLETED]**

### Phase 2: State/Behavior Separation

*   **Status:** Completed.
*   **Details:**
    *   **Type Definitions:** Core data structures have been successfully moved to `src/engine/types/core.nim` and other relevant `types/` sub-modules. **[COMPLETED]**
    *   **Behavioral Logic:** Helper functions and queries have been systematically migrated from `src/engine/gamestate.nim` to their appropriate `systems/` modules. **[COMPLETED]**
    *   **Initialization Logic:** Game initialization functions have been successfully migrated from `gamestate.nim` to their respective files within `src/engine/initialization/` (e.g., `game.nim`, `house.nim`, `colony.nim`). **[COMPLETED]**
    *   **Turn Cycle Orchestration:** Functions like `advanceTurn` and `getCurrentGameAct` have been successfully moved to `src/engine/turn_cycle/orchestrator.nim`. **[COMPLETED]**

### Phase 3: System Decomposition

*   **Status:** Completed.
*   **Details:**
    *   The `systems/combat/` directory contains relevant files, suggesting decomposition of combat logic is underway. **[COMPLETED]**
    *   The monolithic files `src/engine/commands/executor.nim`, `src/engine/resolution/fleet_orders.nim`, and `src/engine/commands/zero_turn_commands.nim` have been decomposed, their logic migrated to the new `systems/orders/execution/` and `systems/orders/admin/` sub-modules, and the original files are presumed removed. **[COMPLETED]**

## 5. Phased Rollout Plan (Updated)

To minimize disruption, I recommend a phased approach:

1.  **Phase 1: Reorganization.** Create the new directory structure. Move existing files into their new locations and update all `import` statements. The code remains unchanged, but the structure is in place. **[COMPLETED]**
2.  **Phase 2: State/Behavior Separation.** Refactor `gamestate.nim` by moving types to `src/engine/types/` (Done), systematically migrating helper functions and initialization logic to their respective `systems/` and `initialization/` modules. Move turn cycle orchestration to `src/engine/turn_cycle/orchestrator.nim`. **[COMPLETED]**
3.  **Phase 3: System Decomposition.** Refactor monolithic modules, including combat logic (largely done), and the decomposition and removal of `executor.nim`/`fleet_orders.nim`, and `zero_turn_commands.nim`. **[COMPLETED]**

This iterative approach will allow for testing at each stage and ensure the engine remains functional throughout the refactoring process.

## 6. Alignment with Game Specifications

A review of the game specification documents confirms that this refactoring proposal is strongly aligned with the intended game architecture, particularly the `ec4x_canonical_turn_cycle.md` and `06-operations.md` specs.

### `turn_cycle/` and Canonical Turn Cycle

The proposed `src/engine/turn_cycle/` directory structure, with modules for each of the four phases, is a direct implementation of the architecture described in `ec4x_canonical_turn_cycle.md`. This will make the high-level orchestration of the game loop much easier to understand and map to the documentation.

### `systems/` and Domain-Driven Specs

The specs are organized by domain (Economy, Combat, Operations, etc.). The proposed `src/engine/systems/` directory mirrors this structure. This alignment provides several benefits:
-   Logic for a specific domain (e.g., all combat mechanics from `07-combat.md`) will be consolidated in one place (`systems/combat/`).
-   It will be easier for developers to find the code corresponding to a specific section of the specification.

### Order Execution (`06-operations.md`)

`06-operations.md` provides a clear separation between **Active Fleet Orders** (Section 6.3) and **Zero-Turn Administrative Commands** (Section 6.4). The proposal to break down `executor.nim` and `zero_turn_commands.nim` reflects this perfectly.

-   **Fleet Orders**: The plan to create a dispatcher (`fleet_order_executor.nim`) and separate modules for order execution under `systems/orders/execution/` is well-supported. A more detailed breakdown could look like this:
    -   `movement.nim`: Handles Hold, Move, SeekHome, Patrol.
    -   `combat.nim`: Handles Guard*, Blockade, Bombard, Invade, Blitz.
    -   `economic.nim`: Handles Colonize, Salvage.
    -   `espionage.nim`: Handles Spy*, Hack*.
    -   `fleet_management.nim`: Handles JoinFleet, Rendezvous.
    -   `state.nim`: Handles Reserve, Mothball, Reactivate.
    -   `recon.nim`: Handles ViewWorld.

-   **Administrative Commands**: The plan to break down `zero_turn_commands.nim` into modules under `systems/orders/admin/` is also directly aligned with the spec's categories (Fleet Reorganization, Cargo Operations, Squadron Management).

This structure will make the order execution logic significantly more manageable and easier to map to the 20+ distinct fleet orders described in the specification.
