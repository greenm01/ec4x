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
├── types/                 # Core data structures (replaces gamestate.nim)
│   ├── core.nim           # GameState, House, Colony, Fleet, Squadron
│   ├── combat.nim         # Combat-specific types
│   ├── economy.nim        # Economy-specific types
│   └── ...                # Other domain types (orders, intelligence, etc.)
│
├── systems/               # Domain-specific logic modules (behavior)
│   ├── combat/            # Combat resolution logic
│   │   ├── space.nim
│   │   ├── orbital.nim
│   │   └── planetary.nim    # Invasion, blitz, bombardment
│   ├── economy/           # Economic calculations
│   │   ├── production.nim
│   │   ├── maintenance.nim
│   │   └── capacity/      # (existing modules)
│   ├── orders/            # Order execution logic
│   │   ├── fleet_order_executor.nim
│   │   └── admin_command_executor.nim
│   └── ...                # (diplomacy, research, intelligence, etc.)
│
└── turn_cycle/            # Orchestration of the turn cycle
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

-   **Action**: Move all type definitions (`GameState`, `House`, `Colony`, `Fleet`, etc.) into the new `src/engine/types/` directory (e.g., `core.nim`).
-   **Action**: Move helper functions and queries to the relevant modules within `src/engine/systems/`. For example, `getSquadronLimit` would move to `src/engine/systems/economy/capacity/total_squadrons.nim`. The existing `iterators.nim` is a good pattern to follow and expand.

### `src/engine/resolution/combat_resolution.nim` & `src/engine/combat/ground.nim`

This module is extremely large and handles all forms of combat. The logic should be split to match the canonical turn cycle's combat steps.

-   **Action**: Consolidate all combat logic into `src/engine/systems/combat/`.
-   **Action**: Create `space.nim` to handle space combat logic from `resolveBattle`.
-   **Action**: Create `orbital.nim` to handle orbital combat, including starbase participation.
-   **Action**: Consolidate planetary assault logic (`resolveBombardment`, `resolveInvasion`, `resolveBlitz`) from `combat_resolution.nim` and `ground.nim` into a new `planetary.nim`.

### `src/engine/commands/executor.nim` & `src/engine/resolution/fleet_orders.nim`

These files contain over 2,000 lines of overlapping logic for fleet order execution. This should be consolidated and broken down by order.

-   **Action**: Create `src/engine/systems/orders/fleet_order_executor.nim` to act as a dispatcher.
-   **Action**: Create a new directory `src/engine/systems/orders/execution/` containing small modules for each order or logical group (e.g., `move.nim`, `colonize.nim`, `combat_orders.nim`).
-   **Action**: The `executor.nim` and `fleet_orders.nim` files will be removed, their logic distributed into the new, smaller modules.

### `src/engine/commands/zero_turn_commands.nim`

This file for administrative commands is over 1,000 lines long and can be split by functionality.

-   **Action**: Create `src/engine/systems/orders/admin_command_executor.nim` to act as a dispatcher.
-   **Action**: Create a new directory `src/engine/systems/orders/admin/` with modules for each command type:
    -   `fleet_management.nim` (Detach, Transfer, Merge)
    -   `cargo.nim` (Load/Unload Cargo)
    -   `fighters.nim` (Load/Unload/Transfer Fighters)
    -   `squadron.nim` (Form, Assign, Transfer)

## 4. Phased Rollout Plan

To minimize disruption, I recommend a phased approach:

1.  **Phase 1: Reorganization.** Create the new directory structure. Move existing files into their new locations and update all `import` statements. The code remains unchanged, but the structure is in place.
2.  **Phase 2: State/Behavior Separation.** Refactor `gamestate.nim` by moving types to `src/engine/types/` and helper functions to their respective `systems/` modules.
3.  **Phase 3: System Decomposition.** Refactor one monolithic module at a time, starting with `combat_resolution.nim`, followed by `executor.nim`/`fleet_orders.nim`, and finally `zero_turn_commands.nim`.

This iterative approach will allow for testing at each stage and ensure the engine remains functional throughout the refactoring process.
