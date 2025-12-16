#!/usr/bin/env python3
"""
Budget Allocation Analysis - EC4X RBA AI

Analyzes budget allocation patterns across game Acts to identify:
- Treasury hoarding vs spending efficiency
- Budget distribution across objectives (Expansion, Defense, Military, etc.)
- Act-specific allocation patterns
- Underspending root causes

Usage:
    python3 scripts/analysis/analyze_budget_allocation.py
    python3 scripts/analysis/analyze_budget_allocation.py --diagnostics-dir custom/path
"""

import csv
import sys
from pathlib import Path
from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List, Optional

@dataclass
class BudgetSnapshot:
    """Single turn budget allocation snapshot"""
    turn: int
    act: str
    house: str
    strategy: str
    treasury: int
    production: int
    # Build orders by objective
    expansion_spent: int = 0
    defense_spent: int = 0
    military_spent: int = 0
    reconnaissance_spent: int = 0
    special_units_spent: int = 0
    technology_spent: int = 0
    # Ship counts
    total_ships: int = 0
    capitals: int = 0
    escorts: int = 0
    fighters: int = 0
    # Capacity
    squadron_limit: int = 0
    squadron_used: int = 0

    @property
    def total_build_spent(self) -> int:
        """Total PP spent on build orders this turn"""
        return (self.expansion_spent + self.defense_spent + self.military_spent +
                self.reconnaissance_spent + self.special_units_spent)

    @property
    def total_spent(self) -> int:
        """Total PP spent (build + research)"""
        return self.total_build_spent + self.technology_spent

    @property
    def spending_rate(self) -> float:
        """Percentage of production spent"""
        return (self.total_spent / self.production * 100) if self.production > 0 else 0

    @property
    def treasury_to_production_ratio(self) -> float:
        """Turns of production saved in treasury"""
        return (self.treasury / self.production) if self.production > 0 else 0


def load_diagnostics(diagnostics_dir: Path) -> List[BudgetSnapshot]:
    """Load budget snapshots from diagnostic CSV files"""
    snapshots = []

    csv_files = sorted(diagnostics_dir.glob("game_*.csv"))
    if not csv_files:
        print(f"❌ No diagnostic files found in {diagnostics_dir}")
        return []

    print(f"Loading {len(csv_files)} diagnostic files from {diagnostics_dir}...")

    for csv_file in csv_files:
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    # Get strategy and act from CSV (already computed)
                    strategy = row.get('strategy', 'Unknown')
                    act = f"Act{row.get('act', '1')}"  # CSV has act as number (1,2,3,4)
                    turn = int(row['turn'])

                    snapshot = BudgetSnapshot(
                        turn=turn,
                        act=act,
                        house=row['house'],
                        strategy=strategy,
                        treasury=int(row.get('treasury', 0)),
                        production=int(row.get('production', 0)),
                        # TODO: Parse build spending by objective from CSV
                        # For now, use total_ships as proxy
                        total_ships=int(row.get('total_ships', 0)),
                        capitals=int(row.get('battlecruiser_count', 0)) +
                                int(row.get('battleship_count', 0)) +
                                int(row.get('dreadnought_count', 0)),
                        escorts=int(row.get('destroyer_count', 0)) +
                               int(row.get('scout_count', 0)),
                        fighters=int(row.get('fighter_count', 0)),
                        squadron_limit=int(row.get('squadron_limit', 0)),
                        squadron_used=int(row.get('total_ships', 0)),
                    )
                    snapshots.append(snapshot)
                except (KeyError, ValueError) as e:
                    print(f"⚠️  Skipping row in {csv_file}: {e}")
                    continue

    return snapshots


def analyze_by_act(snapshots: List[BudgetSnapshot]) -> Dict[str, Dict]:
    """Analyze budget patterns grouped by Act"""

    by_act = defaultdict(lambda: {
        'count': 0,
        'total_treasury': 0,
        'total_production': 0,
        'total_ships': 0,
        'total_capitals': 0,
        'avg_treasury': 0,
        'avg_production': 0,
        'avg_treasury_ratio': 0,
        'strategies': defaultdict(lambda: {
            'count': 0,
            'treasury': 0,
            'production': 0,
            'ships': 0,
            'capitals': 0
        })
    })

    for snap in snapshots:
        act_data = by_act[snap.act]
        act_data['count'] += 1
        act_data['total_treasury'] += snap.treasury
        act_data['total_production'] += snap.production
        act_data['total_ships'] += snap.total_ships
        act_data['total_capitals'] += snap.capitals

        strat_data = act_data['strategies'][snap.strategy]
        strat_data['count'] += 1
        strat_data['treasury'] += snap.treasury
        strat_data['production'] += snap.production
        strat_data['ships'] += snap.total_ships
        strat_data['capitals'] += snap.capitals

    # Calculate averages
    for act, data in by_act.items():
        if data['count'] > 0:
            data['avg_treasury'] = data['total_treasury'] / data['count']
            data['avg_production'] = data['total_production'] / data['count']
            data['avg_treasury_ratio'] = (data['avg_treasury'] / data['avg_production']) if data['avg_production'] > 0 else 0

            for strat, sdata in data['strategies'].items():
                if sdata['count'] > 0:
                    sdata['avg_treasury'] = sdata['treasury'] / sdata['count']
                    sdata['avg_production'] = sdata['production'] / sdata['count']
                    sdata['avg_ships'] = sdata['ships'] / sdata['count']
                    sdata['avg_capitals'] = sdata['capitals'] / sdata['count']

    return dict(by_act)


def analyze_treasury_hoarding(snapshots: List[BudgetSnapshot]) -> Dict:
    """Identify treasury hoarding patterns"""

    hoarding = {
        'high_treasury_low_ships': [],  # High treasury but few ships
        'excessive_savings': [],        # Treasury > 3x production
        'underspending_acts': defaultdict(int),
    }

    for snap in snapshots:
        # High treasury but low ship count (capacity underutilization)
        if snap.squadron_limit > 0:
            capacity_usage = snap.squadron_used / snap.squadron_limit
            if snap.treasury > 1000 and capacity_usage < 0.5:
                hoarding['high_treasury_low_ships'].append({
                    'turn': snap.turn,
                    'house': snap.house,
                    'treasury': snap.treasury,
                    'ships': snap.total_ships,
                    'capacity': f"{snap.squadron_used}/{snap.squadron_limit}",
                    'usage': f"{capacity_usage*100:.0f}%"
                })

        # Excessive savings (treasury > 3x production = 3 turns of income saved)
        if snap.treasury_to_production_ratio > 3.0:
            hoarding['excessive_savings'].append({
                'turn': snap.turn,
                'house': snap.house,
                'treasury': snap.treasury,
                'production': snap.production,
                'ratio': f"{snap.treasury_to_production_ratio:.1f}x"
            })
            hoarding['underspending_acts'][snap.act] += 1

    return hoarding


def print_act_analysis(by_act: Dict):
    """Print Act-by-Act budget analysis"""

    print("\n" + "=" * 80)
    print("BUDGET ALLOCATION BY ACT")
    print("=" * 80)

    for act in ['Act1', 'Act2', 'Act3', 'Act4']:
        if act not in by_act:
            continue

        data = by_act[act]
        print(f"\n{act} ({data['count']} snapshots)")
        print("-" * 80)
        print(f"  Average Treasury:     {data['avg_treasury']:.0f} PP")
        print(f"  Average Production:   {data['avg_production']:.0f} PP/turn")
        print(f"  Treasury/Production:  {data['avg_treasury_ratio']:.1f}x (turns of income saved)")
        print(f"  Total Ships:          {data['total_ships']}")
        print(f"  Total Capitals:       {data['total_capitals']}")

        print(f"\n  By Strategy:")
        for strat in ['Aggressive', 'Balanced', 'Economic', 'Turtle']:
            if strat not in data['strategies']:
                continue
            sdata = data['strategies'][strat]
            if sdata['count'] == 0:
                continue

            print(f"    {strat:12} Treasury: {sdata['avg_treasury']:6.0f}PP  "
                  f"Ships: {sdata['avg_ships']:4.1f}  "
                  f"Capitals: {sdata['avg_capitals']:4.1f}")


def print_hoarding_analysis(hoarding: Dict):
    """Print treasury hoarding analysis"""

    print("\n" + "=" * 80)
    print("TREASURY HOARDING ANALYSIS")
    print("=" * 80)

    # Excessive savings (>3x production)
    excessive = hoarding['excessive_savings']
    if excessive:
        print(f"\n⚠️  EXCESSIVE TREASURY: {len(excessive)} instances of treasury > 3x production")
        print("-" * 80)

        # Group by Act
        by_act = defaultdict(list)
        for item in excessive[:20]:  # Show first 20
            by_act[item['turn'] // 10].append(item)

        for act_range, items in sorted(by_act.items()):
            act_name = ['Act1', 'Act2', 'Act3', 'Act4'][min(act_range, 3)]
            print(f"\n  {act_name}:")
            for item in items[:5]:  # Show first 5 per act
                print(f"    Turn {item['turn']:2d} | {item['house']:15} | "
                      f"Treasury: {item['treasury']:5d}PP ({item['ratio']}) | "
                      f"Production: {item['production']:4d}PP/turn")
    else:
        print("\n✅ No excessive treasury hoarding detected")

    # High treasury but low capacity usage
    low_usage = hoarding['high_treasury_low_ships']
    if low_usage:
        print(f"\n⚠️  CAPACITY UNDERUTILIZATION: {len(low_usage)} instances")
        print("-" * 80)
        print("    (High treasury but using <50% of squadron capacity)")

        for item in low_usage[:10]:  # Show first 10
            print(f"    Turn {item['turn']:2d} | {item['house']:15} | "
                  f"Treasury: {item['treasury']:5d}PP | "
                  f"Ships: {item['ships']:2d} | "
                  f"Capacity: {item['capacity']:5} ({item['usage']})")
    else:
        print("\n✅ No capacity underutilization detected")

    # Underspending by Act
    print(f"\n  Underspending Summary by Act:")
    for act in ['Act1', 'Act2', 'Act3', 'Act4']:
        count = hoarding['underspending_acts'].get(act, 0)
        if count > 0:
            print(f"    {act}: {count} instances of excessive savings")


def analyze_spending_efficiency(by_act: Dict) -> Dict:
    """Analyze spending efficiency vs potential"""

    efficiency = {}

    for act, data in by_act.items():
        if data['count'] == 0 or data['avg_production'] == 0:
            continue

        # Calculate potential ships/turn vs actual
        # Avg ship cost ~80PP (mix of destroyers, capitals, etc.)
        avg_ship_cost = 80
        potential_ships_per_turn = data['avg_production'] / avg_ship_cost

        # Actual ships built over the Act period
        # Estimate turns per act: Act1=7, Act2=8, Act3=15, Act4=rest
        turns_in_act = {'Act1': 7, 'Act2': 8, 'Act3': 15, 'Act4': 10}.get(act, 10)
        actual_ships_per_turn = data['total_ships'] / data['count'] / turns_in_act

        # Spending efficiency = actual / potential
        spending_efficiency = (actual_ships_per_turn / potential_ships_per_turn * 100) if potential_ships_per_turn > 0 else 0

        efficiency[act] = {
            'potential_per_turn': potential_ships_per_turn,
            'actual_per_turn': actual_ships_per_turn,
            'efficiency_pct': spending_efficiency,
            'avg_treasury': data['avg_treasury'],
            'avg_production': data['avg_production']
        }

    return efficiency


def print_spending_efficiency(efficiency: Dict):
    """Print spending efficiency analysis"""

    print("\n" + "=" * 80)
    print("SPENDING EFFICIENCY ANALYSIS")
    print("=" * 80)
    print("  (Potential ships/turn vs actual ship building rate)\n")

    for act in ['Act1', 'Act2', 'Act3', 'Act4']:
        if act not in efficiency:
            continue

        eff = efficiency[act]
        print(f"  {act}:")
        print(f"    Potential: {eff['potential_per_turn']:.1f} ships/turn "
              f"(based on {eff['avg_production']:.0f}PP production)")
        print(f"    Actual:    {eff['actual_per_turn']:.1f} ships/turn")
        print(f"    Efficiency: {eff['efficiency_pct']:.0f}% of production spent on ships")

        if eff['efficiency_pct'] < 20:
            print(f"    ⚠️  SEVERE UNDERSPENDING: Only {eff['efficiency_pct']:.0f}% utilization!")
        elif eff['efficiency_pct'] < 40:
            print(f"    ⚠️  Low spending: Only {eff['efficiency_pct']:.0f}% utilization")
        elif eff['efficiency_pct'] < 60:
            print(f"    ✓  Moderate spending: {eff['efficiency_pct']:.0f}% utilization")
        else:
            print(f"    ✅ Good spending: {eff['efficiency_pct']:.0f}% utilization")
        print()


def print_recommendations(by_act: Dict, hoarding: Dict, efficiency: Dict):
    """Print actionable recommendations"""

    print("\n" + "=" * 80)
    print("RECOMMENDATIONS")
    print("=" * 80)

    recommendations = []

    # Check spending efficiency
    for act, eff in efficiency.items():
        if eff['efficiency_pct'] < 30:
            recommendations.append(
                f"⚠️  {act}: Severe underspending ({eff['efficiency_pct']:.0f}% efficiency). "
                f"Potential: {eff['potential_per_turn']:.1f} ships/turn, "
                f"Actual: {eff['actual_per_turn']:.1f} ships/turn. "
                f"Budget-aware logic may be TOO conservative."
            )

    # Check for excessive treasury in any Act
    for act in ['Act1', 'Act2', 'Act3', 'Act4']:
        if act in by_act:
            data = by_act[act]
            if data['avg_treasury_ratio'] > 2.5:
                recommendations.append(
                    f"⚠️  {act}: Treasury ratio {data['avg_treasury_ratio']:.1f}x too high. "
                    f"AI saving {data['avg_treasury']:.0f}PP but should spend more on ships."
                )

    # Check hoarding patterns
    if len(hoarding['excessive_savings']) > 10:
        recommendations.append(
            f"⚠️  Excessive treasury hoarding: {len(hoarding['excessive_savings'])} instances. "
            f"Budget allocation may be too conservative."
        )

    if len(hoarding['high_treasury_low_ships']) > 10:
        recommendations.append(
            f"⚠️  Capacity underutilization: {len(hoarding['high_treasury_low_ships'])} instances. "
            f"AI has PP but not building ships to fill squadron capacity."
        )

    # Print recommendations
    if recommendations:
        print("\n  Issues Found:")
        for i, rec in enumerate(recommendations, 1):
            print(f"\n  {i}. {rec}")

        print("\n  Potential Root Causes:")
        print("    - Budget-aware affordability logic too conservative")
        print("    - Act-specific spending thresholds need adjustment")
        print("    - Strategic Triage not allocating enough to Military/Defense")
        print("    - Unit requests getting Deferred instead of fulfilled")

        print("\n  Suggested Fixes:")
        print("    1. Increase Act-specific spending thresholds (15%/25%/40%/50% → higher)")
        print("    2. Lower affordability factor requirements (e.g., allow 30% treasury spend)")
        print("    3. Reduce 2x cost health check to 1.5x cost")
        print("    4. Adjust baseline budget allocations to favor Military in Act2+")
    else:
        print("\n✅ Budget allocation looks healthy!")
        print("   - Treasury ratios reasonable across all Acts")
        print("   - No significant hoarding patterns detected")
        print("   - Capacity utilization good")


def main():
    """Main analysis entry point"""

    # Parse command line args
    diagnostics_dir = Path("balance_results/diagnostics")
    if len(sys.argv) > 1:
        diagnostics_dir = Path(sys.argv[1])

    if not diagnostics_dir.exists():
        print(f"❌ Diagnostics directory not found: {diagnostics_dir}")
        print(f"   Run a simulation first: ./bin/run_simulation --fixed-turns --turns 30")
        return 1

    # Load data
    snapshots = load_diagnostics(diagnostics_dir)
    if not snapshots:
        return 1

    print(f"Loaded {len(snapshots)} budget snapshots\n")

    # Analyze
    by_act = analyze_by_act(snapshots)
    hoarding = analyze_treasury_hoarding(snapshots)
    efficiency = analyze_spending_efficiency(by_act)

    # Print results
    print_act_analysis(by_act)
    print_spending_efficiency(efficiency)
    print_hoarding_analysis(hoarding)
    print_recommendations(by_act, hoarding, efficiency)

    print("\n" + "=" * 80)
    print("Analysis complete!")
    print("=" * 80)

    return 0


if __name__ == "__main__":
    sys.exit(main())
