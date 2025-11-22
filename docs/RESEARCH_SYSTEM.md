# EC4X Research System - Critical Understanding

## IMPORTANT: For Future AI/Developer Reference

This document explains the EC4X research system to prevent confusion about tech advancement. **The naming in the codebase is confusing** - please read carefully!

## Core Concepts

### Research Point Categories (economy.md:4.0)

There are **THREE separate research categories**, NOT direct tech field allocation:

1. **ERP (Economic Research Points)** - Used to advance **Economic Level (EL)**
2. **SRP (Science Research Points)** - Used to advance **Science Level (SL)**
3. **TRP (Technology Research Points)** - Used to advance **specific technologies**

### The Confusing Type System

**WARNING**: `TechField` enum includes `EnergyLevel` and `ShieldLevel` but these are **NOT** what they seem:

```nim
type TechField {.pure.} = enum
  EnergyLevel          # This is actually Economic Level (EL), not energy tech!
  ShieldLevel          # This is actually Science Level (SL), not shield tech!
  ConstructionTech     # This IS construction technology (CST)
  WeaponsTech          # This IS weapons technology (WEP)
  TerraformingTech     # This IS terraforming technology (TER)
  ElectronicIntelligence  # This IS ELI
  CounterIntelligence  # This IS CIC
```

**The naming is a design flaw.** `EnergyLevel` should be renamed to `EconomicLevel` and `ShieldLevel` should be `ScienceLevel`. Planetary shields are a completely separate technology.

## Research Flow

### Step 1: Player Allocates PP

Players allocate Production Points (PP) from their production to research:

```nim
ResearchAllocation = object
  economic: int      # PP allocated to EL research
  science: int       # PP allocated to SL research
  technology: Table[TechField, int]  # PP allocated to specific technologies
```

**Example:**
```nim
allocation = ResearchAllocation(
  economic: 10,      # 10 PP towards EL
  science: 5,        # 5 PP towards SL
  technology: {
    TechField.WeaponsTech: 8,        # 8 PP towards WEP
    TechField.ConstructionTech: 7    # 7 PP towards CST
  }
)
```

### Step 2: PP Converted to RP

PP is converted to research points using formulas from economy.md:

#### ERP Conversion
```
1 ERP = (5 + log₁₀(GHO)) PP
```
Where GHO = Gross House Output (sum of all colony production)

#### SRP Conversion
```
1 SRP = (2 + SL × 0.5) PP
```
Where SL = current Science Level

#### TRP Conversion
```
1 TRP = ((5 + 4×SL)/10 + log₁₀(GHO) × 0.5) PP
```
Where SL = current Science Level, GHO = Gross House Output

**Key Point:** TRP cost depends on **current SL**! Higher SL makes TRP cheaper.

### Step 3: RP Accumulated

Research points accumulate in the tech tree:

```nim
ResearchPoints = object
  economic: int                      # Total ERP accumulated
  science: int                       # Total SRP accumulated
  technology: Table[TechField, int]  # Total TRP per tech field
```

### Step 4: Tech Advancement (Bi-Annual)

On upgrade turns (months 1 and 7), accumulated RP can be spent:

#### Economic Level Advancement
```
EL1→EL2 requires 50 ERP
EL2→EL3 requires 60 ERP
EL3→EL4 requires 70 ERP
```
Formula: `40 + EL × 10` (for EL1-5)

#### Science Level Advancement
```
SL1→SL2 requires 25 SRP
SL2→SL3 requires 30 SRP
SL3→SL4 requires 35 SRP
```
Formula: `20 + SL × 5` (for SL1-5)

#### Technology Advancement
Varies by technology field. See tech.toml for specific costs.

**Example:** CST1→CST2 requires 25 TRP

## Implementation Details

### Code Files

- `src/engine/research/types.nim` - Defines `ResearchAllocation`, `ResearchPoints`, `TechTree`
- `src/engine/research/costs.nim` - PP→RP conversion formulas
- `src/engine/research/advancement.nim` - Tech level advancement logic
- `src/engine/orders.nim` - `OrderPacket` contains `ResearchAllocation`
- `src/engine/resolve.nim` - Processes research allocation during Income Phase

### Correct Usage in AI

**WRONG WAY** (what was initially implemented):
```nim
# DO NOT DO THIS!
researchAllocation: Table[TechField, int] = {
  TechField.EnergyLevel: 100  # Directly allocating PP to "energy"
}
```

**RIGHT WAY**:
```nim
researchAllocation: ResearchAllocation = ResearchAllocation(
  economic: 50,      # 50 PP towards Economic Level
  science: 30,       # 30 PP towards Science Level
  technology: {
    TechField.ConstructionTech: 20  # 20 PP towards CST (will be converted to TRP)
  }
)
```

## Common Mistakes to Avoid

1. **Don't confuse EL with energy technology** - There is no "energy technology" in EC4X. `EnergyLevel` = Economic Level.

2. **Don't confuse SL with shields** - `ShieldLevel` = Science Level. Planetary shields (SLD) are a separate technology.

3. **Don't allocate PP directly to tech fields** - PP must go through ERP/SRP/TRP conversion.

4. **Remember TRP costs depend on SL** - You need SL advances to make TRP research affordable.

5. **Don't forget the bi-annual cycle** - Tech only advances on upgrade turns (months 1 and 7).

## Verification

To verify the research system is working correctly:

1. Check that PP allocations convert to correct RP amounts
2. Verify accumulated RP increases each turn
3. Confirm tech advances only on upgrade turns (1, 7, 13, 19, 25...)
4. Check logs show "ERP", "SRP", "TRP" not just "RP"
5. Verify EL and SL advance separately from technologies

## Example Log Output (Correct)

```
Turn 2 Income Phase:
  house-atreides allocated 9 PP → 1 ERP (total: 1 ERP)
  house-atreides allocated 7 PP → 2 SRP (total: 2 SRP)
  house-atreides allocated 6 PP → 3 TRP (ConstructionTech) (total: 3 TRP)

Turn 14 Tech Advancement (Upgrade Turn):
  Atreides: EL 1 → 2 (spent 50 ERP)
  Atreides: SL 1 → 2 (spent 25 SRP)
  Atreides: ConstructionTech 1 → 2 (spent 25 TRP)
```

## References

- Full research rules: `docs/specs/economy.md` Section 4.0
- Tech costs: `config/tech.toml`
- Research types: `src/engine/research/types.nim`
- Formulas: `src/engine/research/costs.nim`
