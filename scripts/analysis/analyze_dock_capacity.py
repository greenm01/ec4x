#!/usr/bin/env python3
"""
Dock Capacity Analysis

Analyzes whether AI is bottlenecked by dock capacity constraints.

Key Metrics:
- Treasury growth (hoarding vs spending)
- Ship construction rate (ships/turn)
- Implied dock utilization
- Facility scaling patterns

Usage:
    python3 analyze_dock_capacity.py balance_results/diagnostics/*.csv
"""

import csv
import sys
from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List

@dataclass
class TurnSnapshot:
    """Single turn snapshot for one house"""
    turn: int
    act: str
    treasury: int
    production: int
    total_ships: int
    colonies: int
    strategy: str

def load_diagnostics(csv_files: List[str]) -> Dict[str, List[TurnSnapshot]]:
    """Load diagnostic data grouped by house"""
    by_house = defaultdict(list)

    for csv_file in csv_files:
        try:
            with open(csv_file, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    # Skip turn 0 (setup)
                    turn = int(row.get('turn', 0))
                    if turn == 0:
                        continue

                    house = row.get('house', 'unknown')
                    act_num = int(row.get('act', 1))
                    act_name = f"Act{act_num}"

                    snapshot = TurnSnapshot(
                        turn=turn,
                        act=act_name,
                        treasury=int(row.get('treasury', 0)),
                        production=int(row.get('production', 0)),
                        total_ships=int(row.get('total_ships', 0)),
                        colonies=int(row.get('total_colonies', 0)),
                        strategy=row.get('strategy', 'Unknown')
                    )
                    by_house[house].append(snapshot)
        except Exception as e:
            print(f"⚠️  Error loading {csv_file}: {e}", file=sys.stderr)
            continue

    # Sort by turn
    for house in by_house:
        by_house[house].sort(key=lambda x: x.turn)

    return by_house

def analyze_construction_rate(snapshots: List[TurnSnapshot]) -> Dict:
    """Analyze ship construction patterns"""
    if len(snapshots) < 2:
        return {}

    # Group by Act
    by_act = defaultdict(list)
    for s in snapshots:
        by_act[s.act].append(s)

    results = {}
    for act, turns in by_act.items():
        if len(turns) < 2:
            continue

        # Calculate ships/turn
        first = turns[0]
        last = turns[-1]
        turns_elapsed = last.turn - first.turn
        ships_built = last.total_ships - first.total_ships

        if turns_elapsed > 0:
            ships_per_turn = ships_built / turns_elapsed

            # Calculate production utilization
            avg_production = sum(t.production for t in turns) / len(turns)
            avg_treasury = sum(t.treasury for t in turns) / len(turns)

            # Avg ship cost = 80PP (rough estimate)
            potential_ships_per_turn = avg_production / 80 if avg_production > 0 else 0

            # Dock utilization estimate
            # Assumption: Base homeworld has 1 spaceport (5 docks) or 1 shipyard (10 docks)
            # With N colonies, should scale to N*10 docks (if building shipyards)
            avg_colonies = sum(t.colonies for t in turns) / len(turns)

            # Estimate dock capacity (conservative: assume 10 docks per colony)
            estimated_docks = avg_colonies * 10

            # If ship takes 2 turns to build, effective dock throughput = docks/2 ships/turn
            estimated_throughput = estimated_docks / 2

            results[act] = {
                'turns': turns_elapsed,
                'ships_built': ships_built,
                'ships_per_turn': ships_per_turn,
                'avg_production': avg_production,
                'avg_treasury': avg_treasury,
                'avg_colonies': avg_colonies,
                'potential_ships_per_turn': potential_ships_per_turn,
                'estimated_docks': estimated_docks,
                'estimated_throughput': estimated_throughput,
                'utilization_pct': (ships_per_turn / potential_ships_per_turn * 100) if potential_ships_per_turn > 0 else 0,
                'dock_constrained': ships_per_turn < estimated_throughput * 0.8  # Building less than 80% of dock capacity
            }

    return results

def detect_treasury_hoarding(snapshots: List[TurnSnapshot]) -> Dict:
    """Detect if AI is hoarding treasury instead of building"""
    if len(snapshots) < 5:
        return {}

    # Look at Turn 10, 20, 30 if available
    checkpoints = []
    for target_turn in [10, 20, 30]:
        for s in snapshots:
            if s.turn == target_turn:
                checkpoints.append(s)
                break

    if not checkpoints:
        return {}

    results = {}
    for s in checkpoints:
        # Treasury-to-production ratio
        # Healthy economy: Treasury = 0.5-1.0x production (saving 0.5-1.0 turns of production)
        # Hoarding: Treasury > 2x production
        ratio = s.treasury / s.production if s.production > 0 else 0

        # Ships per colony (should be 3-5+ by Turn 20)
        ships_per_colony = s.total_ships / s.colonies if s.colonies > 0 else 0

        results[f"Turn{s.turn}"] = {
            'treasury': s.treasury,
            'production': s.production,
            'ratio': ratio,
            'total_ships': s.total_ships,
            'colonies': s.colonies,
            'ships_per_colony': ships_per_colony,
            'hoarding': ratio > 2.0,
            'underbuilt': ships_per_colony < 3.0
        }

    return results

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_dock_capacity.py balance_results/diagnostics/*.csv")
        sys.exit(1)

    csv_files = sys.argv[1:]
    print(f"📊 Analyzing {len(csv_files)} diagnostic files...\n")

    by_house = load_diagnostics(csv_files)

    if not by_house:
        print("❌ No data loaded")
        sys.exit(1)

    print("=" * 80)
    print("DOCK CAPACITY BOTTLENECK ANALYSIS")
    print("=" * 80)

    for house, snapshots in sorted(by_house.items()):
        if len(snapshots) < 2:
            continue

        strategy = snapshots[0].strategy if snapshots else "Unknown"
        print(f"\n{house} ({strategy})")
        print("-" * 80)

        # Construction rate analysis
        construction = analyze_construction_rate(snapshots)
        if construction:
            print("\n  Construction Rate by Act:")
            for act in ['Act1', 'Act2', 'Act3', 'Act4']:
                if act not in construction:
                    continue
                data = construction[act]
                print(f"    {act}:")
                print(f"      Ships Built: {data['ships_built']:.0f} ({data['ships_per_turn']:.1f} ships/turn)")
                print(f"      Avg Production: {data['avg_production']:.0f} PP/turn")
                print(f"      Avg Treasury: {data['avg_treasury']:.0f} PP")
                print(f"      Avg Colonies: {data['avg_colonies']:.1f}")
                print(f"      Potential: {data['potential_ships_per_turn']:.1f} ships/turn (if 100% production → ships)")
                print(f"      Est. Dock Capacity: {data['estimated_docks']:.0f} docks ({data['estimated_throughput']:.1f} ships/turn)")
                print(f"      Utilization: {data['utilization_pct']:.1f}%")

                if data['dock_constrained']:
                    print(f"      ⚠️  DOCK BOTTLENECK: Building {data['ships_per_turn']:.1f} ships/turn with {data['estimated_throughput']:.1f} estimated capacity")
                    print(f"         → Likely needs more Shipyards/Spaceports!")
                else:
                    print(f"      ✅ Not dock-constrained (building well below estimated capacity)")

        # Treasury hoarding analysis
        hoarding = detect_treasury_hoarding(snapshots)
        if hoarding:
            print("\n  Treasury vs Production:")
            for checkpoint, data in sorted(hoarding.items()):
                print(f"    {checkpoint}:")
                print(f"      Treasury: {data['treasury']:.0f} PP ({data['ratio']:.1f}x production)")
                print(f"      Ships: {data['total_ships']:.0f} ({data['ships_per_colony']:.1f} per colony)")

                if data['hoarding']:
                    print(f"      ⚠️  HOARDING: Treasury > 2x production")
                if data['underbuilt']:
                    print(f"      ⚠️  UNDERBUILT: < 3 ships per colony")

    print("\n" + "=" * 80)
    print("ANALYSIS SUMMARY")
    print("=" * 80)
    print("""
Common Patterns:

1. **Dock Bottleneck**: AI building < 1 ship/turn with 2000+ PP treasury
   → Cause: Limited Spaceport/Shipyard capacity (5-10 docks)
   → Fix: AI needs to build more Shipyards at each colony

2. **Treasury Hoarding**: Treasury > 2x production
   → Cause: Budget-aware logic too conservative OR dock bottleneck
   → Fix: Either increase spending thresholds or build more docks

3. **Underbuilt Fleets**: < 3 ships per colony by Turn 20
   → Cause: Combination of budget constraints + dock limits
   → Fix: Scale facility construction with colony count

Expected Healthy Patterns:
- Act1: 0.5-1 ships/turn (expansion focus, limited budget)
- Act2: 1-3 ships/turn (buildup phase)
- Act3: 3-6 ships/turn (war economy, should have 3-5 colonies with 2-3 shipyards each)
- Act4: 5-10 ships/turn (endgame, full production)

Dock Capacity Scaling:
- 1 Colony (homeworld): 10 docks (1 shipyard) = 5 ships/turn
- 3 Colonies: 30 docks (10 per colony) = 15 ships/turn
- 5 Colonies: 50 docks (10 per colony) = 25 ships/turn
""")

if __name__ == "__main__":
    main()
