# EC4X Engine Architecture & Context

## 1. Core Mandates (Non-Negotiable)
- **Data-Oriented Design (DoD):** Use `EntityManager` and Tables. Avoid heavy OOP or inheritance chains.
- **Enum Safety:** All enums MUST be `{.pure.}` per NEP-1.
- **Logging:** Use `std/logging`. Never use `echo` in engine code.
- **Information Leakage:** Code must respect Fog of War. Use `house.intelligence` records rather than reading global `GameState` directly.

## 2. Nim Style Guide
- **Indentation:** 2 spaces.
- **Line Length:** Max 80 characters.
- **Naming:** Follow NEP-1 (camelCase for vars/procs, PascalCase for types).
- **Operators:** Always use spaces around operators (e.g., `a + b`).

## 3. Tech Stack Context
- **Language:** Nim (targeting C/C++ backend).
- **Architecture:** 4X Space Strategy with a turn-based execution model.
- **Key Modules:** - `game_state.nim`: The source of truth.
  - `player_view.nim`: The filtered visibility layer.
  - `intelligence_db.nim`: Historical record of entity states.

## 4. Development Workflow
- **No Hardcoding:** Always pull parameters from TOML configs.
- **Verification:** When modifying engine systems, ensure the 100+ existing integration tests are considered.
- **Documentation:** Always update `docs/api/api.json` if public procs are changed.
