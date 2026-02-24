# EC4X TUI Expert Mode Specification

**Status:** Draft / Conceptual
**Version:** 1.0

## 1. Philosophy and Design Goals

The Expert Mode (`:` command palette) provides power users with a keyboard-driven, lightning-fast way to execute game commands without navigating the visual TUI panes. 

### Core Principles
1.  **Explicit Targets Only:** Commands never rely on the current UI highlight or selection. This ensures commands are unambiguous, repeatable, and safe from UI-state desyncs. (e.g., `:fleet "1st Fleet" move Nova` instead of just `:move Nova`).
2.  **Helix-Style Fuzzy Autocomplete:** As the user types, the palette aggressively fuzzy-matches against valid categories, actions, and game entity names (systems, fleets, technologies). This aids discovery and minimizes typing.
3.  **Zero-Dependency Parsing:** The parser will be hand-written in pure Nim using the standard library (`strutils`, `parseutils`). No heavy external C-libraries, ensuring fast cross-platform compilation and easy maintainability.
4.  **Category-Driven:** Commands are grouped by major gameplay concepts (mapping roughly to the primary views).

---

## 2. Syntax Structure

All commands follow a standard hierarchical structure, prioritizing the target entity first:

```
:[category] [target] [action] [arguments...]
```

*   **category**: The major gameplay domain (e.g., `fleet`, `colony`, `tech`, `spy`, `gov`). Short aliases (e.g., `f`, `c`, `t`) are supported.
*   **target**: The explicit game entity ID, Name, or subsystem (e.g., `Sol`, `"1st Strike Fleet"`, `wep`, `ebp`). *Note: Multi-word targets must be wrapped in quotes.*
*   **action**: The specific verb or operation (e.g., `move`, `build`, `alloc`).
*   **arguments**: Additional parameters required by the action.

---

## 3. Command Reference

### 🚀 Fleet Operations (`fleet` or `f`)
*Manage fleet movements, combat postures, and zero-turn commands.*

| Command | Description | Example |
| :--- | :--- | :--- |
| `:f <fleet> move <system>` | Issue a move order to a system. | `:f "1st Fleet" move Nova` |
| `:f <fleet> hold` | Cancel orders, hold position. | `:f "1st Fleet" hold` |
| `:f <fleet> roe <level>` | Set Rules of Engagement (1-10). | `:f "1st Fleet" roe 8` |
| `:f <fleet> split <qty> <class>` | ZTC: Detach ships into a new fleet. | `:f "1st Fleet" split 5 interceptor` |
| `:f <source> merge <target>` | ZTC: Merge source fleet into target. | `:f "2nd Fleet" merge "1st Fleet"` |
| `:f <fleet> load <qty> <cargo>` | ZTC: Load cargo/troops at colony. | `:f "Transport Alpha" load 200 marines` |
| `:f <fleet> status <state>` | Change fleet status. | `:f "Reserve Fleet" status mothball` |

### 🪐 Colony Management (`colony` or `c`)
*Manage planetary queues, automation, and facilities.*

| Command | Description | Example |
| :--- | :--- | :--- |
| `:c <colony> build <qty> <item>` | Add item(s) to construction queue. | `:c Sol build 5 interceptor` |
| `:c <colony> qrm <index>` | Remove item at index from queue. | `:c Sol qrm 1` |
| `:c <colony> qup <index>` | Move queue item up priority list. | `:c Sol qup 3` |
| `:c <colony> auto <system> <state>` | Toggle automation systems (rep/mar/fig). | `:c Sol auto rep on` |

### 🔬 Research & Tech (`tech` or `t`)
*Allocate research points (PP).*

| Command | Description | Example |
| :--- | :--- | :--- |
| `:t <field> alloc <amount>` | Allocate points to a tech field. | `:t wep alloc 50` |
| `:t <eco\|sci> alloc <amount>` | Allocate to Foundation levels. | `:t eco alloc 100` |
| `:t clear` | Clear all pending allocations. | `:t clear` |

### 🕵️ Espionage (`spy` or `s`)
*Manage intelligence budgets and black ops.*

| Command | Description | Example |
| :--- | :--- | :--- |
| `:s <ebp\|cip> budget <amount>` | Set espionage budgets. | `:s ebp budget 50` |
| `:s <house> op <operation>` | Stage a spy operation. | `:s Lyra op theft` |
| `:s clear` | Clear all staged ops and budgets. | `:s clear` |

### 🏛️ Government & Economy (`gov` or `g`)
*Manage empire-wide policies and diplomacy.*

| Command | Description | Example |
| :--- | :--- | :--- |
| `:g empire tax <rate>` | Set empire tax rate (0-100). | `:g empire tax 40` |
| `:g <house> dip <stance>` | Propose diplomatic stance change. | `:g Lyra dip neutral` |

### 🗺️ System & Meta (`map` or `m`)
*Client-side utilities and intel notes.*

| Command | Description | Example |
| :--- | :--- | :--- |
| `:m <system> note "<text>"` | Save an intel note for a system. | `:m Nova note "Heavily defended"` |
| `:m export` | Export the current starmap to SVG. | `:m export` |

---

## 4. Parser and Autocomplete Design

### The Lexer/Parser (`src/player/sam/expert_parser.nim`)
We will use a custom, lightweight recursive-descent parser built with `std/parseutils`. 
1. **Tokenization:** Split the input string by spaces, respecting double-quotes for multi-word entity names (e.g., `"1st Strike Fleet"`).
2. **AST Generation:** Map the tokens into a strongly-typed Nim variant object (`ExpertCommand`).
3. **Validation:** Ensure numbers are valid integers, and enums match game constants. If validation fails, return a precise error message ("Expected integer for tax rate").

### The Autocomplete Engine (`src/player/tui/expert_autocomplete.nim`)
To emulate the Helix experience, autocomplete must be **fuzzy and context-aware**.

1. **Fuzzy Matching Mechanism:**
   For a 4X game with hundreds of systems and custom fleet names, fuzzy matching is vastly superior to exact string matching. 
   *Example:* Typing `:f 1st mv` will match `:fleet "1st Strike Fleet" move`. 

2. **Contextual Suggestions:**
   The suggestions provided by the palette depend on the cursor position and parsed AST depth:
   *   **Depth 0 (Empty):** Suggest categories (`fleet`, `colony`, `tech`, etc.).
   *   **Depth 1 (Category entered):** Suggest valid actions for that category, OR if it's a `fleet` or `colony` command, suggest valid entity names.
   *   **Depth 2 (Target/Action entered):** Depending on the command structure, suggest either actions (e.g., if a fleet target was entered) or arguments (if an action was entered).
   *   **Depth 3 (Argument entered):** Suggest valid arguments (e.g., Ship Classes, Cargo Types, Operations).

### Integration with SAM (`src/player/sam/acceptors.nim`)
When the user hits `Enter`:
1. The raw string is passed to `actionExpertSubmit()`.
2. The SAM acceptor parses the string.
3. If valid, the resulting `ExpertCommand` AST is mapped to standard `StagedXCommands` (e.g., `BuildCommand`, `FleetCommand`) and injected directly into the TUI Model.
4. If invalid, the UI model's `expertModeFeedback` string is updated with the parse error (e.g., "Fleet 'Ghost' not found").