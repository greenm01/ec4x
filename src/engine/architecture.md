src/engine/
    │
    ├── game_engine.nim     # [MAIN APPLICATION ENTRY] Orchestrates game lifecycle.
    │                       #   - Initializes new games.
    │                       #   - Loads/Saves state via `@persistence`.
    │                       #   - Drives the main turn cycle via `@turn_cycle/turn_executor.nim`.
    │
    ├── @config/            # [GAME DATA CONFIGURATION] All static game rules and values.
    │   └── *.nim           #   - Loaded by `@init/config_resolver.nim`.
    │
    ├── @types/             # [DATA SCHEMA] Defines ALL pure data structures (Fleet, Ship, GameState).
    │   ├── capacity.nim    #   - Defines types for the capacity system.
    │   └── *.nim           #   - Universal data types for the entire engine.
    │
    ├── @init/              # [GAME SETUP & BOOTSTRAP]
    │   ├── config_resolver.nim # - Loads config files.
    │   ├── game.nim        #   - Entry for new game creation.
    │   ├── *.nim           #   - Factories/initializers for core entities during setup.
    │   └── validation.nim  #   - Validates initial game setup.
    │
    ├── @persistence/       # [SAVE/LOAD MANAGEMENT]
    │   ├── schema.nim      #   - Serialization/deserialization logic.
    │   ├── writer.nim      #   - Writes `GameState` to storage.
    │   ├── queries.nim     #   - Reads `GameState` from storage.
    │   └── types.nim       #   - Types specific to save data.
    │
    │                                     (READ-ONLY ACCESS)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    ├── @state/               # [STATE MANAGEMENT CORE - The "Database"]     ▼
    │   │                     # Provides generic, low-level mechanics for storing and accessing data.
    │   ├── entity_manager.nim#   - Implements the generic DoD storage pattern (data: seq, index: Table).
    │   ├── game_state.nim    #   - `initGameState` constructor, simple getters, and trackers (e.g., `GracePeriodTracker`).
    │   ├── id_gen.nim        #   - Logic for generating new, unique entity IDs.
    │   ├── iterators.nim     #   - The PRIMARY READ-ONLY API for the engine (e.g., `fleetsInSystem`, `coloniesOwned`).
    │   │                     #   - ALWAYS use iterators instead of `.entities.data` with manual filtering.
    │   │                     #   - Provides O(1) indexed lookups via `byHouse`, `byOwner`, `bySystem` tables.
    │   └── fog_of_war.nim    #   - A complex READ-ONLY query system that transforms `GameState` into a `PlayerView`.
    │
    │                                     (WRITE/MUTATION ACCESS)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    ├── @entities/            # [ENTITY-SPECIFIC MUTATORS - The "Write API"] ▼
    │   │                     # Handles complex state changes for specific entities, ensuring data consistency.
    │   │                     # **KEY PRINCIPLE**: Index-aware mutations only. NO business logic.
    │   │
    │   ├── fleet_ops.nim     #   - `createFleet`, `destroyFleet`, `moveFleet`, `changeFleetOwner`
    │   │                     #   - Maintains `bySystem` (spatial) and `byOwner` (ownership) indexes
    │   │
    │   ├── ship_ops.nim      #   - `add/remove` -> updates ship list AND `bySquadron` index
    │   ├── colony_ops.nim    #   - `establishColony`, `destroyColony`, `changeColonyOwner`
    │   │                     #   - Maintains `bySystem` and `byOwner` indexes
    │   ├── squadron_ops.nim  #   - `createSquadron`, `destroySquadron`, `transferSquadron`
    │   │                     #   - Maintains `byFleet` index
    │   ├── ground_unit_ops.nim
    │   ├── facility_ops.nim
    │   ├── project_ops.nim
    │   └── population_transfer_ops.nim
    │
    │
    │                         (Reads from @state, Writes via @entities)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    ├── @systems/             # [GAME LOGIC IMPLEMENTATION - The "Domain Experts"]
    │   │                     # Contains all the detailed algorithms for game features.
    │   │                     # **KEY PRINCIPLE**: Business logic, validation, algorithms. NO index manipulation.
    │   │
    │   ├── colony/           #   - Colony domain logic
    │   │   ├── engine.nim    #     - High-level API: `establishColony` (validation + prestige)
    │   │   ├── conflicts.nim #     - Simultaneous colonization resolution
    │   │   └── ...           #     - Other colony-specific systems
    │   │
    │   ├── fleet/            #   - Fleet domain logic
    │   │   ├── engine.nim    #     - High-level API: `createFleetCoordinated`, `mergeFleets`, `splitFleet`
    │   │   ├── entity.nim    #     - Fleet business logic: `canMergeWith`, `combatStrength`, `balanceSquadrons`
    │   │   └── ...           #     - Other fleet-specific systems
    │   │
    │   ├── squadron/         #   - Squadron domain logic
    │   │   ├── engine.nim    #     - High-level API (stub for future)
    │   │   ├── entity.nim    #     - Squadron business logic
    │   │   └── ...           #     - Other squadron-specific systems
    │   │
    │   ├── ship/             #   - Ship domain logic
    │   │   ├── engine.nim    #     - High-level API (stub for future)
    │   │   ├── entity.nim    #     - Ship business logic
    │   │   └── ...           #     - Other ship-specific systems
    │   │
    │   ├── economy/          #   - Logic for calculating income, production, maintenance
    │   ├── combat/           #   - Logic for resolving space and ground battles
    │   ├── research/         #   - Logic for tech tree advancement
    │   ├── capacity/         #   - Logic for enforcing squadron and ship capacity limits
    │   └── ...etc            #   - Each module takes `GameState`, performs reads via `@state/iterators`,
    │                         #     and writes changes via the `@entities` managers
    │
    │
    │                         (Orchestrates @systems)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    └── @turn_cycle/          # [ORCHESTRATION - The "Main Loop"]            ▼
        │                     # Lightweight modules that define the sequence of the game.
        ├── turn_executor.nim #   - The main driver. Calls each phase in order.
        ├── income_phase.nim  #   - Calls the relevant system(s), e.g., `systems/economy/engine.calculateIncome(state)`.
        ├── conflict_phase.nim#   - Calls `systems/combat/engine.resolveAllCombats(state)`.
        └── ...etc            #   - Passes the `GameState` from one system to the next.
