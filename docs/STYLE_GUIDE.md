# EC4X Style Guide

**Version:** 1.0
**Last Updated:** 2025-11-21

This document defines the code standards for the EC4X project. All code must follow these conventions.

---

## 1. Core Standards

**Base Standard:** [NEP-1 (Nim Enhancement Proposal 1)](https://nim-lang.org/docs/nep1.html)

All code follows NEP-1 conventions with project-specific additions below.

---

## 2. Naming Conventions

### Types and Enums

**PascalCase** for all type names:

```nim
type
  GameState* = object
  HouseId* = distinct string
  PrestigeSource* {.pure.} = enum
    TechAdvancement
    ColonyEstablishment
    VictoryAchieved
```

### Constants

**camelCase** for constants (per NEP-1):

```nim
const
  maxFleetSize = 100
  defaultPrestigeThreshold = 5000
  researchCostMultiplier = 1.5
```

❌ **NOT** `UPPER_SNAKE_CASE` (not NEP-1 compliant)

### Procedures and Variables

**camelCase** for procedures and variables:

```nim
proc calculatePrestige(source: PrestigeSource): int =
  let baseValue = 10
  let modifier = 1.5
  return int(float(baseValue) * modifier)

var totalPrestige = 0
let houseId = "house1".HouseId
```

### Boolean Prefixes

Use `is`, `has`, `can` for boolean identifiers:

```nim
let isEliminated = true
let hasColony = false
let canResearch = true
```

---

## 3. Enums

### Pure Enums Requirement

**ALL enums MUST be `{.pure.}`:**

```nim
type
  MoraleLevel* {.pure.} = enum
    Collapsing
    VeryLow
    Low
    Normal
    High
    VeryHigh
    Exceptional
```

**Usage - Always Fully Qualified:**

```nim
# ✅ Correct
let morale = MoraleLevel.High
if morale == MoraleLevel.VeryHigh:
  applyBonus()

# ❌ Wrong
let morale = High  # Will not compile
```

### In Specifications

In markdown specs, use **short enum names** for readability:

```markdown
When morale is **High**, tax efficiency increases by 10%.
The **TechAdvancement** prestige source awards +50 prestige.
```

---

## 4. Code Organization

### File Structure

```
src/
├── common/          # Shared types, utilities (source of truth)
│   └── types/
│       └── core.nim # HouseId, PlayerId, SystemId, etc.
├── engine/          # Game engine modules
│   ├── module_name/
│   │   ├── types.nim    # Type definitions
│   │   └── engine.nim   # Implementation
│   └── config/          # TOML config loaders
└── main.nim
```

### Module Organization

Each engine module follows this pattern:

```
engine/module_name/
├── types.nim     # Type definitions, enums, objects
└── engine.nim    # Implementation, procedures, logic
```

**Import order:**

```nim
# 1. Standard library
import std/[tables, options, algorithm]

# 2. Project common types
import ../../common/types/core

# 3. Project engine modules
import ../gamestate
import types

# 4. Export public API
export types
```

---

## 5. Configuration System

### No Hardcoded Game Values

**ALL game balance values MUST be in TOML config files:**

```nim
# ❌ Wrong - Hardcoded values
proc awardPrestige(): int =
  return 50  # Don't do this!

# ✅ Correct - Use TOML config
proc awardPrestige(source: PrestigeSource): int =
  let config = globalPrestigeConfig
  case source
  of PrestigeSource.TechAdvancement:
    return config.techAdvancement
  of PrestigeSource.ColonyEstablishment:
    return config.colonyEstablishment
  else:
    return 0
```

### Config File Pattern

**Location:** `config/module_name.toml`

**Example:** `config/prestige.toml`

```toml
[sources]
tech_advancement = 50
colony_establishment = 5
diplomatic_pact = 10
```

**Loader pattern:**

```nim
# In src/engine/config/prestige_config.nim
import std/parsecfg

type
  PrestigeConfig* = object
    techAdvancement*: int
    colonyEstablishment*: int
    diplomaticPact*: int

var globalPrestigeConfig*: PrestigeConfig

proc loadPrestigeConfig*(path: string) =
  let config = loadConfig(path)
  globalPrestigeConfig.techAdvancement = config.getSectionValue("sources", "tech_advancement").parseInt
  # ... etc
```

---

## 6. Code Formatting

### Indentation

**2 spaces** (per NEP-1):

```nim
proc example() =
  if condition:
    doSomething()
  else:
    doOtherThing()
```

### Line Length

**80 characters maximum** (per NEP-1)

Break long lines naturally:

```nim
# ✅ Good
let result = calculatePrestige(
  source = PrestigeSource.TechAdvancement,
  modifier = 1.5,
  baseValue = 100
)

# ❌ Too long
let result = calculatePrestige(source = PrestigeSource.TechAdvancement, modifier = 1.5, baseValue = 100)
```

### Spacing

**Spaces around operators:**

```nim
let total = value + modifier * 2
if count >= threshold:
  return true
```

**No trailing whitespace**

---

## 7. Documentation

### Module Headers

Every module starts with a doc comment:

```nim
## Victory Condition Engine
##
## Evaluate victory conditions and determine game winner
##
## Public API:
## - checkVictoryConditions()
## - generateLeaderboard()
```

### Procedure Documentation

Document public procedures:

```nim
proc checkPrestigeVictory*(houses: Table[HouseId, House],
                           condition: VictoryCondition,
                           currentTurn: int): VictoryCheck =
  ## Check if any house has reached prestige threshold
  ##
  ## Returns VictoryCheck with victoryOccurred=true if threshold met
  result = VictoryCheck(victoryOccurred: false)
  # ... implementation
```

**Private procedures:** Optional documentation

---

## 8. Testing

### Test Requirements

**Before ANY commit:**

```bash
# Run all integration tests
nim c -r tests/integration/test_*.nim

# Verify project builds
nimble build
```

**Current test coverage:** 76+ integration tests (all must pass)

### Test File Naming

```
tests/
├── unit/
│   └── test_module_name.nim
├── integration/
│   └── test_system_integration.nim
├── balance/
│   └── test_game_balance.nim
└── scenarios/
    └── test_specific_scenario.nim
```

### Test Structure

```nim
import std/unittest
import ../../src/engine/module_name/[types, engine]

suite "Module Name Tests":

  test "should do expected behavior":
    # Arrange
    let input = setupInput()

    # Act
    let result = functionUnderTest(input)

    # Assert
    check result == expectedValue
```

---

## 9. Git Workflow

### Commit Messages

**Format:**

```
Brief description (50 chars max)

- Detailed bullet point if needed
- Another detail
- Reference to issue if applicable
```

**Examples:**

```
Add victory condition system

- Implements prestige, last standing, turn limit victories
- Adds leaderboard generation
- 9 integration tests passing
```

### Pre-Commit Checklist

- [ ] All enums are `{.pure.}`
- [ ] No hardcoded game values (check TOML)
- [ ] Tests pass: `nim c -r tests/integration/test_*.nim`
- [ ] Project builds: `nimble build`
- [ ] No binaries committed
- [ ] Updated STATUS.md if milestone complete
- [ ] Followed NEP-1 naming conventions
- [ ] Line length ≤ 80 characters
- [ ] No trailing whitespace

---

## 10. Common Patterns

### Error Handling

Use `Option[T]` for nullable results:

```nim
import std/options

proc findHouse(id: HouseId): Option[House] =
  if houses.hasKey(id):
    return some(houses[id])
  return none(House)
```

### Iteration

Prefer iterator-based patterns:

```nim
# ✅ Good
for houseId, house in state.houses:
  if not house.eliminated:
    processHouse(houseId, house)

# ❌ Avoid manual indexing when possible
for i in 0..<houses.len:
  processHouse(houses[i])
```

### Immutability

Use `let` by default, `var` only when mutation needed:

```nim
let config = loadConfig()  # Immutable
var prestige = 0           # Will be modified
```

---

## 11. Audit Commands

### Check for Violations

```bash
# Find non-pure enums
grep -r "enum$" src/ --include="*.nim" | grep -v "{.pure.}"

# Find hardcoded prestige values
grep -r "prestige.*= [0-9]" src/engine/

# Find UPPER_SNAKE_CASE constants (should be camelCase)
grep -r "^const$" -A 5 src/ --include="*.nim" | grep "[A-Z_][A-Z_]"

# Find lines over 80 characters
find src -name "*.nim" -exec awk 'length > 80 {print FILENAME":"NR":"$0}' {} \;
```

---

## 12. References

**Official Nim Resources:**
- [NEP-1 Style Guide](https://nim-lang.org/docs/nep1.html)
- [Nim Manual](https://nim-lang.org/docs/manual.html)
- [Nim Standard Library](https://nim-lang.org/docs/lib.html)

**Project Documentation:**
- `docs/CLAUDE_CONTEXT.md` - Session context and quick reference
- `docs/STATUS.md` - Current implementation status
- `docs/specs/` - Game design specifications
- `docs/architecture/` - Technical design documents

---

## 13. Exceptions and Clarifications

### When to Deviate

**Never deviate from:**
- Pure enum requirement
- TOML config requirement for game values
- NEP-1 naming conventions

**May deviate with justification:**
- Line length (if breaking would reduce readability)
- Documentation density (very simple private procs)

**Always document exceptions in code comments:**

```nim
# Line exceeds 80 chars to preserve URL readability
const apiEndpoint = "https://very-long-domain-name.com/api/v1/endpoint"
```

---

## Version History

- **1.0** (2025-11-21): Initial style guide based on NEP-1 + EC4X conventions
