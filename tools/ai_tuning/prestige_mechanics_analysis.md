# Prestige Mechanics Analysis

**Game**: 4-player, 40 turns, seed 12345
**Date**: 2025-11-30

## Key Finding: Prestige Gains Overwhelm Losses

### The Observation

Prestige appears to only accumulate and never decrease, creating a monotonic growth pattern where all houses steadily gain prestige throughout the game.

### The Reality

Prestige **does decrease**, but losses are negligible compared to gains:

| House | Turns with Loss | Min Loss | Max Gain | Avg Change |
|-------|----------------|----------|----------|------------|
| Corrino | 7/40 (18%) | -25 | +642 | +126.8 |
| Atreides | 7/40 (18%) | -21 | +506 | +106.0 |
| Harkonnen | 8/40 (20%) | -25 | +506 | +132.9 |
| Ordos | 10/40 (25%) | -25 | +506 | +110.9 |

**Analysis**:
- Houses lose prestige 18-25% of turns
- Losses range from -21 to -25 prestige
- Gains range from +100 to +642 prestige
- **Gain/Loss Ratio: ~25:1** (gains are 25× larger than losses)

### Why Losses Are So Small

Based on `config/prestige.toml`, the penalty mechanics include:

1. **Military defeats**:
   - Lose planet: -100 prestige
   - Lose starbase: -50 prestige
   - Scout destroyed: -30 prestige
   - Ambushed by cloak: -10 prestige

2. **Espionage failures**:
   - Failed espionage: -20 prestige
   - Being victimized: -10 to -70 prestige

3. **Tax penalties**:
   - High tax (51-60%): -1 per turn
   - Very high tax (61-70%): -2 per turn
   - Extreme tax (71-80%): -4 per turn
   - Crushing tax (81-90%): -7 per turn
   - Maximum tax (91-100%): -11 per turn

4. **Maintenance shortfall**:
   - Base: -8 prestige
   - Escalating: -3 per consecutive turn

### What's Actually Happening

The small losses (-21 to -25) suggest:

1. **Minimal combat**: No planets being lost (-100 each)
2. **Tax penalties**: Likely -1 to -2 per turn from moderate taxation
3. **Espionage failures**: Occasional -20 from failed missions
4. **No catastrophic defeats**: No major military losses

### Why Gains Are So Large

From `config/prestige.toml`, the gain mechanics include:

1. **Economic achievements**:
   - Establish colony: +50 prestige
   - Tech advancement: +20 prestige
   - Max population: +30 prestige
   - IU milestones: +10 to +50 prestige

2. **Military victories**:
   - Invade planet: +100 prestige
   - System capture: +100 prestige
   - Destroy starbase: +50 prestige
   - Fleet victory: +30 prestige

3. **Dynamic multiplier**:
   - For this map size, likely 4-5× multiplier
   - Amplifies all prestige gains

### The Imbalance

**Root cause**: Prestige reward/penalty asymmetry

- **Establishing a colony**: +50 prestige
- **Losing a colony**: -100 prestige (2× penalty)
- **But**: Colonies are being established much more frequently than lost

In 40 turns:
- **Average gain**: +106 to +133 per turn
- **Average loss**: -21 to -25 per turn (when losses occur)
- **Net effect**: Prestige grows almost monotonically

### Turn-by-Turn Loss Pattern

**Corrino losses**:
- Turns: 13, 25, 26, 33, 34, 37, 41
- Pattern: Sporadic, late-game clustering

**Atreides losses**:
- Turns: 15, 22, 27, 29, 31, 32, 41
- Pattern: Mid-to-late game

**Harkonnen losses**:
- Turns: 15, 23, 30, 31, 35, 36, 38, 40
- Pattern: Late-game concentration (turns 30-40)

**Ordos losses** (most frequent):
- Turns: 9, 17, 18, 19, 23, 26, 28, 30, 31, 33
- Pattern: Consistent losses throughout, explains 4th place finish

---

## Implications for Game Balance

### Current State

1. **Prestige is predominantly additive**
   - Losses are cosmetic noise (~2% of gains)
   - Winner is determined by who gains prestige fastest, not who avoids losses

2. **No meaningful setbacks**
   - Losing a fight costs -25 prestige
   - But you gained +600 prestige from economic growth this turn
   - Net: Still +575 prestige despite "defeat"

3. **Runaway leaders are slowed, not stopped**
   - Harkonnen's lead narrowed from 14.9% to 2.6%
   - But Harkonnen never actually lost ground in absolute prestige
   - The gap narrowed because others gained faster, not because Harkonnen was penalized

### Game Design Questions

1. **Should prestige be more volatile?**
   - Currently: Smooth, predictable growth
   - Alternative: Big swings from combat/diplomacy

2. **Should losses be more punishing?**
   - Currently: -25 max penalty vs +600 max gain (25:1 ratio)
   - Alternative: -100 to -500 penalties for major defeats

3. **Should there be catch-up mechanics?**
   - Currently: All houses gain prestige at similar rates
   - Alternative: Leaders face penalties, underdogs get bonuses

4. **Is monotonic growth desirable?**
   - **Pro**: Players always feel progress, never reset
   - **Con**: Games are determined early, no comebacks possible

---

## Recommendations

### If Monotonic Growth Is Intentional

This is a **score accumulation** system similar to Civilization's victory points:
- Winner is who accumulates fastest
- Losses are minor speed bumps
- Early expansion advantage compounds over time

**No changes needed** - system is working as designed.

### If More Volatility Is Desired

Consider adjusting penalties:

1. **Increase military defeat penalties** (10× multiplier):
   - Lose planet: -100 → **-1000**
   - Lose starbase: -50 → **-500**
   - Make defeats truly catastrophic

2. **Add territory-based penalties**:
   - If you have 9 colonies but lose a battle: -200 prestige
   - If you have 5 colonies and lose a battle: -50 prestige
   - Scales with how much you have to lose

3. **Leader tax**:
   - 1st place: -5% prestige per turn
   - 2nd place: -2% prestige per turn
   - 3rd-4th place: No penalty
   - Creates rubber-banding

4. **Prestige decay**:
   - All prestige decays by 1-2% per turn
   - Forces continuous achievement to maintain position
   - Prevents early-game leads from being permanent

---

## Data Tables

### Prestige Change Distribution

```
Corrino:
  Negative changes: 7/40 turns (18%)
  Range: -25 to +642
  Average: +126.8/turn
  Turns with losses: 13, 25, 26, 33, 34, 37, 41

Atreides:
  Negative changes: 7/40 turns (18%)
  Range: -21 to +506
  Average: +106.0/turn
  Turns with losses: 15, 22, 27, 29, 31, 32, 41

Harkonnen:
  Negative changes: 8/40 turns (20%)
  Range: -25 to +506
  Average: +132.9/turn
  Turns with losses: 15, 23, 30, 31, 35, 36, 38, 40

Ordos:
  Negative changes: 10/40 turns (25%)
  Range: -25 to +506
  Average: +110.9/turn
  Turns with losses: 9, 17, 18, 19, 23, 26, 28, 30, 31, 33
```

### Gain/Loss Ratio Analysis

| Metric | Value |
|--------|-------|
| Max single-turn gain | +642 |
| Max single-turn loss | -25 |
| Gain/Loss ratio | 25.7:1 |
| Avg gain (all houses) | +119.1/turn |
| Avg loss (when occurring) | -23.5/turn |

---

**Conclusion**: Prestige DOES decrease, but the losses are so small compared to gains that the net effect is monotonic growth for all houses. Whether this is a problem depends on the intended game design - score accumulation vs dynamic competition.
