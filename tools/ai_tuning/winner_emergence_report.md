# Winner Emergence Analysis Report

**Game**: 4-player, 40 turns, seed 12345
**Winner**: House Harkonnen (6200 prestige)
**Date**: 2025-11-30

## Executive Summary

In this 40-turn game, **House Harkonnen won with 6200 prestige**, but the victory was **never decisive**. Despite leading for 37 consecutive turns (from turn 5 onwards), Harkonnen never achieved a 20%+ sustained lead that would indicate a clear winner.

**Key Finding**: The winner does NOT become clear until very late in the game. Even at turn 40, Harkonnen only held a 2.6% lead, suggesting competitive balance throughout.

---

## Winner Emergence Timeline

### Turn-by-Turn Analysis

- **Turns 2-4**: Corrino and Harkonnen tied for lead (0% margin)
- **Turn 5**: Harkonnen takes lead with 4.5% margin
- **Turn 6**: **First significant lead** - Harkonnen at 14.5% ahead
- **Turns 6-14**: Harkonnen maintains 10-15% lead (most competitive phase)
- **Turns 15-40**: Lead gradually shrinks from 11% to 2.6%

### Lead Strength Over Time

| Turn Range | Average Lead | Status |
|------------|-------------|--------|
| 6-10 | 12.6% | Strong lead |
| 11-20 | 11.2% | Moderate lead |
| 21-30 | 9.0% | Weakening lead |
| 31-40 | 5.8% | Narrow lead |

### Winner Never Became "Clear"

Using the criteria of **15%+ lead for 3+ consecutive turns**:
- **Achieved**: Turn 6 (14.5%), Turn 7 (14.9%), Turn 9 (14.2%)
- **But NOT sustained**: Lead dropped below 15% on turn 8 (10.7%), breaking the streak

The closest Harkonnen came to a decisive victory was **turns 6-7** (14.5-14.9% lead), but this was never sustained long enough to be considered "clear."

---

## Final Standings (Turn 41)

| Rank | House | Prestige | Colonies | Gap from Winner |
|------|-------|----------|----------|-----------------|
| 1 | **Harkonnen** | 6200 | 9 | - |
| 2 | Corrino | 5954 | 7 | -4.0% |
| 3 | Ordos | 5042 | 7 | -18.7% |
| 4 | Atreides | 5028 | 5 | -18.9% |

**Observations**:
- Top 2 houses (Harkonnen, Corrino) very close (4% gap)
- Bottom 2 houses (Ordos, Atreides) nearly tied
- Clear stratification into two tiers

---

## Key Metrics at Critical Turns

### Turn 6: Harkonnen's Strongest Lead (14.5%)

When Harkonnen first established dominance:

| Metric | Corrino | Atreides | Harkonnen | Ordos | Leader |
|--------|---------|----------|-----------|-------|--------|
| Prestige | 2078 | 2216 | **2538** | 2078 | Harkonnen |
| Colonies | 3 | 4 | **5** | 3 | Harkonnen |

Harkonnen's advantage was built on **territorial expansion** - they claimed 5 colonies while others had 3-4.

### Turn 20: Mid-Game Status (8.8% lead)

| House | Prestige | Colonies | Trend |
|-------|----------|----------|-------|
| Harkonnen | 4695 | 7 | Leading but shrinking |
| Corrino | 4315 | 6 | Closing gap |
| Atreides | 3499 | 5 | Falling behind |
| Ordos | 3788 | 5 | Mid-pack |

By turn 20, the gap was already narrowing. Corrino was mounting a comeback.

### Turn 40: End-Game Status (2.6% lead)

| House | Prestige | Colonies | Status |
|-------|----------|----------|--------|
| Harkonnen | 6112 | 9 | Narrow victory |
| Corrino | 5956 | 7 | Strong second |
| Ordos | 5012 | 7 | Distant third |
| Atreides | 5030 | 5 | Collapsed |

The final margin was razor-thin (2.6%). Corrino nearly caught up despite having 2 fewer colonies.

---

## Strategic Insights

### What Won the Game for Harkonnen?

1. **Early territorial expansion** (turn 5-10)
   - Secured 5 colonies by turn 6 vs 3-4 for others
   - Maintained colony advantage throughout (9 vs 5-7)

2. **Sustained consistency**
   - Never lost the lead after turn 5
   - Maintained 37-turn winning streak

3. **Colony advantage**
   - Final: 9 colonies (28% more than second place)
   - This translated to persistent prestige generation

### Why Was the Victory Never Decisive?

1. **Corrino's strong comeback**
   - Despite fewer colonies (7 vs 9), kept prestige competitive
   - Suggests superior colony quality or economic efficiency

2. **Prestige mechanics favor close games**
   - No exponential snowballing visible
   - Colony count advantage doesn't translate to overwhelming prestige lead

3. **Late-game compression**
   - Lead actually *decreased* over time (14.9% → 2.6%)
   - Suggests catch-up mechanics or diminishing returns for leaders

### What About the Losers?

**Atreides (4th place, 5028 prestige)**:
- Collapsed from early competitiveness (tied 2nd on turn 6)
- Only 5 colonies at end (least of all houses)
- Failed to maintain expansion pace

**Ordos (3rd place, 5042 prestige)**:
- Consistently mid-pack (never led, never last)
- 7 colonies at end (same as Corrino)
- Adequate performance but never threatened leaders

---

## Conclusions

### How Many Turns Until Clear Winner?

**Answer**: Winner was **NEVER clear** in 40 turns.

Even after 37 consecutive turns of leading, Harkonnen never established a decisive (15%+, 3-turn) advantage. The final 2.6% margin means Corrino could theoretically have won with a single good turn.

### Game Length Implications

If "clear winner" means 15%+ sustained lead:
- This game would need **50+ turns** minimum
- Possibly never reaches decisive state if balance is tight

If "clear winner" means 10%+ sustained lead:
- Harkonnen achieved this turns 6-19 (14 turns)
- Lost it turns 20-40 (21 turns)
- Even relaxed criteria shows competitive balance

### Recommended Analysis

To better understand winner emergence, we should:

1. **Run more 40-turn games** with different seeds
   - Is this competitive balance typical, or did seed 12345 produce an outlier?

2. **Analyze 50-60 turn games**
   - Does a clear winner emerge with more time?
   - Or does prestige compression continue?

3. **Examine prestige calculation**
   - Why does colony advantage (9 vs 7) not translate to larger prestige gap?
   - Are there diminishing returns or catch-up mechanics?

4. **Study Corrino's comeback**
   - How did they nearly catch Harkonnen with fewer colonies?
   - What metrics (tech, economy, military) compensated for territory deficit?

---

## Detailed Turn-by-Turn Prestige Log

```
Turn |  Corrino | Atreides | Harkonnen |    Ordos |     Leader | Lead
   2 |      882 |      790 |      882 |      606 |    Corrino | +  0.0%
   3 |     1388 |     1204 |     1388 |     1112 |    Corrino | +  0.0%
   4 |     1802 |     1526 |     1802 |     1618 |    Corrino | +  0.0%
   5 |     1894 |     2032 |     2124 |     1986 |  Harkonnen | +  4.5%
   6 |     2078 |     2216 |     2538 |     2078 |  Harkonnen | + 14.5%  ← First strong lead
   7 |     2352 |     2450 |     2814 |     2262 |  Harkonnen | + 14.9%  ← Peak lead
   8 |     2380 |     2542 |     2814 |     2354 |  Harkonnen | + 10.7%
   9 |     2472 |     2542 |     2904 |     2352 |  Harkonnen | + 14.2%
  10 |     2788 |     2722 |     3034 |     2710 |  Harkonnen | +  8.8%
  11 |     3014 |     2812 |     3444 |     2978 |  Harkonnen | + 14.3%
  12 |     3656 |     2990 |     3862 |     3275 |  Harkonnen | +  5.6%
  13 |     3652 |     3078 |     4130 |     3405 |  Harkonnen | + 13.1%
  14 |     3834 |     3165 |     4402 |     3496 |  Harkonnen | + 14.8%
  15 |     3944 |     3163 |     4379 |     3588 |  Harkonnen | + 11.0%
  16 |     4064 |     3255 |     4563 |     3720 |  Harkonnen | + 12.3%
  17 |     4154 |     3255 |     4583 |     3699 |  Harkonnen | + 10.3%
  18 |     4154 |     3275 |     4583 |     3674 |  Harkonnen | + 10.3%
  19 |     4225 |     3275 |     4695 |     3670 |  Harkonnen | + 11.1%
  20 |     4315 |     3499 |     4695 |     3788 |  Harkonnen | +  8.8%  ← Lead shrinking
  21 |     4499 |     3591 |     4827 |     3814 |  Harkonnen | +  7.3%
  22 |     4517 |     3570 |     5101 |     3901 |  Harkonnen | + 12.9%
  23 |     4555 |     3700 |     5099 |     3895 |  Harkonnen | + 11.9%
  24 |     4829 |     3910 |     5099 |     4075 |  Harkonnen | +  5.6%
  25 |     4825 |     3940 |     5283 |     4215 |  Harkonnen | +  9.5%
  26 |     4823 |     4124 |     5373 |     4213 |  Harkonnen | + 11.4%
  27 |     4823 |     4120 |     5373 |     4213 |  Harkonnen | + 11.4%
  28 |     5007 |     4272 |     5441 |     4212 |  Harkonnen | +  8.7%
  29 |     5099 |     4270 |     5621 |     4392 |  Harkonnen | + 10.2%
  30 |     5191 |     4382 |     5598 |     4390 |  Harkonnen | +  7.8%
  31 |     5371 |     4380 |     5594 |     4388 |  Harkonnen | +  4.2%
  32 |     5409 |     4376 |     5777 |     4415 |  Harkonnen | +  6.8%
  33 |     5406 |     4560 |     5866 |     4412 |  Harkonnen | +  8.5%
  34 |     5385 |     4560 |     5884 |     4594 |  Harkonnen | +  9.3%
  35 |     5568 |     4580 |     5859 |     4594 |  Harkonnen | +  5.2%
  36 |     5678 |     4794 |     5856 |     4663 |  Harkonnen | +  3.1%
  37 |     5653 |     4832 |     6032 |     4773 |  Harkonnen | +  6.7%
  38 |     5703 |     4832 |     6028 |     4801 |  Harkonnen | +  5.7%
  39 |     5772 |     4942 |     6116 |     4984 |  Harkonnen | +  6.0%
  40 |     5956 |     5030 |     6112 |     5012 |  Harkonnen | +  2.6%  ← Very narrow
  41 |     5954 |     5028 |     6200 |     5042 |  Harkonnen | +  4.1%  ← Final
```

---

**Report Generated**: 2025-11-30
**Tool**: analyze_winner_emergence.py (polars-based)
**Data Source**: balance_results/diagnostics/game_12345.csv
