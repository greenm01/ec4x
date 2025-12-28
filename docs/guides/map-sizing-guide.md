# Map Sizing Guide for EC4X Administrators

## Overview

The map size in EC4X is controlled by the `numRings` parameter in
`game_setup/*.kdl` files. This parameter is **independent of player count**,
allowing flexible scenario design.

## Ring Size Formula

Total systems = 3n² + 3n + 1, where n = numRings

## Systems Per Player Table

| Rings | Total Systems | 2 Players | 4 Players | 6 Players | 8 Players | 10 Players | 12 Players |
|-------|--------------|-----------|-----------|-----------|-----------|------------|------------|
| 2     | 19           | 9.5       | 4.8       | 3.2       | 2.4       | 1.9        | 1.6        |
| 3     | 37           | 18.5      | 9.3       | 6.2       | 4.6       | 3.7        | 3.1        |
| 4     | 61           | 30.5      | 15.3      | 10.2      | 7.6       | 6.1        | 5.1        |
| 5     | 91           | 45.5      | 22.8      | 15.2      | 11.4      | 9.1        | 7.6        |
| 6     | 127          | 63.5      | 31.8      | 21.2      | 15.9      | 12.7       | 10.6       |
| 7     | 169          | 84.5      | 42.3      | 28.2      | 21.1      | 16.9       | 14.1       |
| 8     | 217          | 108.5     | 54.3      | 36.2      | 27.1      | 21.7       | 18.1       |
| 9     | 271          | 135.5     | 67.8      | 45.2      | 33.9      | 27.1       | 22.6       |
| 10    | 331          | 165.5     | 82.8      | 55.2      | 41.4      | 33.1       | 27.6       |
| 11    | 397          | 198.5     | 99.3      | 66.2      | 49.6      | 39.7       | 33.1       |
| 12    | 469          | 234.5     | 117.3     | 78.2      | 58.6      | 46.9       | 39.1       |

## Design Guidelines

### Quick Games (20-40 turns)
- **2 players:** 3-4 rings (18-30 systems per player)
- **4 players:** 4-5 rings (15-23 systems per player)
- **6+ players:** 5-6 rings (15-21 systems per player)

### Standard Games (40-80 turns)
- **2 players:** 5-6 rings (45-63 systems per player)
- **4 players:** 6-7 rings (32-42 systems per player)
- **6+ players:** 7-8 rings (28-36 systems per player)

### Epic Games (80+ turns)
- **2 players:** 8-10 rings (108-165 systems per player)
- **4 players:** 8-10 rings (54-82 systems per player)
- **6+ players:** 9-11 rings (45-66 systems per player)

## Validation Rules

- **Absolute bounds:** 2-12 rings (enforced by engine)
- **Minimum viable:** 2 rings for any player count (but cramped for 6+ players)
- **Maximum practical:** 12 rings = 469 systems (very large, long games)

## Homeworld Placement

The engine uses distance maximization to spread homeworlds across the map
regardless of ring count. This works well when:
- Systems per player > 5 (adequate strategic space)
- numRings >= playerCount - 1 (enough rings for spacing)

If numRings < playerCount, homeworlds may cluster (intentional for competitive
scenarios).

## Examples

### Competitive 4-player game (quick)

```kdl
gameParameters { playerCount 4 }
mapGeneration { numRings 4 }  // 61 systems = 15 per player
```

### Epic 2-player game

```kdl
gameParameters { playerCount 2 }
mapGeneration { numRings 10 }  // 331 systems = 165 per player
```

### Crowded 12-player game

```kdl
gameParameters { playerCount 12 }
mapGeneration { numRings 6 }  // 127 systems = 10.6 per player (intense!)
```

## Technical Details

### Map Generation Process

1. Load `game_setup/*.kdl` configuration file
2. Extract `numRings` from `mapGeneration` section
3. Validate bounds (2-12 rings)
4. Generate hex grid with center hub and concentric rings
5. Use distance maximization algorithm to assign homeworlds
6. Generate jump lanes between adjacent systems
7. Validate connectivity and homeworld lane requirements

### Systems-Per-Player Ratio Logging

The engine automatically logs the systems-per-player ratio at game
initialization:

```
[INFO] Initialization: Map size: 4 rings = 61 systems (15.3 per player)
```

This helps administrators verify their scenario configuration matches their
intended game length and strategic depth.

## Configuration Reference

### game_setup/*.kdl Structure

```kdl
gameParameters {
    gameId "My Custom Scenario"
    playerCount 4
    theme "dune"
}

mapGeneration {
    numRings 4  // 2-12 valid (absolute bounds)
                // 4 rings = 61 systems, ~15 systems per player for 4 players
                // See this guide for full systems-per-player table
}

// ... rest of setup config
```

### Key Parameters

- **numRings**: Number of hexagonal rings extending from center hub (2-12)
- **playerCount**: Number of AI/human players (independent of ring count)
- **gameSeed**: Random seed for deterministic map generation (optional)

### Relationship to Player Count

**Important:** `numRings` and `playerCount` are independent parameters. This
allows:
- Small maps with many players (competitive, quick games)
- Large maps with few players (epic, exploration-focused games)
- Balanced maps with standard ratios (15-30 systems per player)

The administrator is responsible for choosing an appropriate combination for
their scenario's intended gameplay style.

## Troubleshooting

### Homeworlds Too Close

**Problem:** Homeworlds are clustering despite large map
**Cause:** Distance maximization works best when numRings >= playerCount - 1
**Solution:** Increase numRings or reduce playerCount

### Game Too Short

**Problem:** Players run out of expansion space quickly
**Cause:** Systems-per-player ratio too low (< 10)
**Solution:** Increase numRings in mapGeneration config

### Game Too Long

**Problem:** Games take too many turns to reach victory conditions
**Cause:** Systems-per-player ratio too high (> 50)
**Solution:** Reduce numRings or adjust victory conditions in game setup

### Validation Error: "numRings must be 2-12"

**Problem:** Game fails to initialize
**Cause:** numRings parameter outside valid bounds
**Solution:** Ensure numRings is between 2 and 12 (inclusive)
