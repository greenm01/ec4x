#!/usr/bin/env python3
"""
Test script for Scout/Raider detection probability calculations.

This script validates detection mechanics from config/espionage.toml by:
1. Loading detection tables and modifiers from config
2. Calculating detection probabilities for all ELI/CLK combinations
3. Testing mesh network modifiers, starbase bonuses, and tech penalties
4. Generating probability matrices for visual verification

Usage:
    python3 tests/test_detection_probabilities.py
    python3 tests/test_detection_probabilities.py --verbose
"""

import sys
from pathlib import Path
from typing import Dict, Any, List, Tuple
import random

# Add project root to path for config loading
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    import tomllib  # Python 3.11+
except ImportError:
    import tomli as tomllib  # Fallback for older Python


def load_toml(file_path: Path) -> Dict[str, Any]:
    """Load and parse a TOML configuration file."""
    with open(file_path, 'rb') as f:
        return tomllib.load(f)


def calculate_detection_probability(threshold: int, modifier: int = 0) -> float:
    """
    Calculate detection probability for d20 roll.

    Args:
        threshold: Base threshold (roll must exceed this)
        modifier: Detection modifier (added to roll)

    Returns:
        Detection probability as percentage (0-100)
    """
    if threshold >= 21:
        return 0.0  # Impossible

    effective_threshold = threshold - modifier

    # Roll must exceed threshold: success on (threshold+1) through 20
    if effective_threshold >= 20:
        return 0.0
    elif effective_threshold < 1:
        return 100.0
    else:
        successes = 20 - effective_threshold
        return (successes / 20) * 100


def get_random_threshold(thresholds: List[int], eli_advantage: str = 'random') -> int:
    """
    Select threshold based on ELI advantage using 1d3 roll.

    Args:
        thresholds: [min_threshold, max_threshold]
        eli_advantage: 'major' (use min), 'random' (1d3), or 'none' (use max)

    Returns:
        Selected threshold value
    """
    min_threshold, max_threshold = thresholds

    if min_threshold >= 21:
        return 21  # Impossible

    if eli_advantage == 'major':
        return min_threshold
    elif eli_advantage == 'none':
        return max_threshold
    else:  # random
        # 1d3 roll: 1=min, 2=mid, 3=max
        roll = random.randint(1, 3)
        if min_threshold == max_threshold:
            return min_threshold
        elif roll == 1:
            return min_threshold
        elif roll == 3:
            return max_threshold
        else:
            # Mid point
            return (min_threshold + max_threshold) // 2


def test_spy_detection(config: Dict[str, Any], verbose: bool = False) -> bool:
    """Test spy scout detection probabilities."""
    print("\n" + "="*80)
    print("SPY SCOUT DETECTION TESTS")
    print("="*80)

    spy_table = config['spy_detection_table']
    scout_config = config['scout_detection']

    # Test basic detection without modifiers
    print("\n1. Base Detection Probabilities (no modifiers)")
    print("-" * 80)
    print("Detector → | ELI1  | ELI2  | ELI3  | ELI4  | ELI5  |")
    print("-----------+-------+-------+-------+-------+-------|")

    for spy_level in range(1, 6):
        row = [f"Spy ELI{spy_level}   |"]
        for detector_level in range(1, 6):
            key = f"eli{detector_level}_vs_spy_eli{spy_level}"
            thresholds = spy_table[key]

            # Use average of min/max for base probability
            avg_threshold = (thresholds[0] + thresholds[1]) / 2
            prob = calculate_detection_probability(int(avg_threshold))

            if thresholds[0] >= 21:
                row.append(" NA    |")
            else:
                row.append(f" {prob:4.1f}% |")

        print("".join(row))

    # Test mesh network modifiers
    print("\n2. Mesh Network Modifier Effects")
    print("-" * 80)

    test_case = (3, 3)  # ELI3 detector vs ELI3 spy
    key = f"eli{test_case[0]}_vs_spy_eli{test_case[1]}"
    base_thresholds = spy_table[key]
    base_threshold = (base_thresholds[0] + base_thresholds[1]) // 2
    base_prob = calculate_detection_probability(base_threshold)

    print(f"\nBase case: ELI{test_case[0]} detector vs Spy ELI{test_case[1]}")
    print(f"Threshold: {base_threshold} (base probability: {base_prob:.1f}%)")
    print()

    mesh_configs = [
        (1, 0, "1 scout"),
        (2, scout_config['mesh_2_3_scouts'], "2-3 scouts"),
        (4, scout_config['mesh_4_5_scouts'], "4-5 scouts"),
        (6, scout_config['mesh_6_plus_scouts'], "6+ scouts"),
    ]

    for scouts, modifier, label in mesh_configs:
        prob = calculate_detection_probability(base_threshold, modifier)
        delta = prob - base_prob
        print(f"{label:12} | Modifier: +{modifier} | Probability: {prob:5.1f}% | Delta: {delta:+5.1f}%")

    # Test starbase bonus
    print("\n3. Starbase ELI Bonus")
    print("-" * 80)

    starbase_bonus = scout_config['starbase_eli_bonus']
    prob_with_starbase = calculate_detection_probability(base_threshold, starbase_bonus)
    delta = prob_with_starbase - base_prob

    print(f"\nStarbase bonus: +{starbase_bonus} ELI modifier")
    print(f"Base probability: {base_prob:.1f}%")
    print(f"With starbase: {prob_with_starbase:.1f}%")
    print(f"Improvement: {delta:+.1f}%")

    # Test tech level penalty
    print("\n4. Tech Level Penalty")
    print("-" * 80)

    tech_threshold = scout_config['dominant_tech_threshold']
    print(f"\nTech penalty applies when >{tech_threshold*100:.0f}% of scouts are lower tech")
    print(f"Penalty: -1 ELI (effectively +1 to threshold)")

    prob_with_penalty = calculate_detection_probability(base_threshold, -1)
    delta = prob_with_penalty - base_prob

    print(f"Base probability: {base_prob:.1f}%")
    print(f"With tech penalty: {prob_with_penalty:.1f}%")
    print(f"Reduction: {delta:.1f}%")

    # Validation checks
    print("\n5. Validation Checks")
    print("-" * 80)

    all_pass = True

    # Check 1: Higher detector ELI should have higher probability
    for spy_level in range(1, 6):
        for detector_level in range(1, 5):
            key1 = f"eli{detector_level}_vs_spy_eli{spy_level}"
            key2 = f"eli{detector_level+1}_vs_spy_eli{spy_level}"

            thresh1 = spy_table[key1]
            thresh2 = spy_table[key2]

            if thresh1[0] < 21 and thresh2[0] < 21:
                avg1 = (thresh1[0] + thresh1[1]) / 2
                avg2 = (thresh2[0] + thresh2[1]) / 2

                if avg1 <= avg2:
                    print(f"✗ FAIL: ELI{detector_level+1} ({avg2}) should have lower threshold than ELI{detector_level} ({avg1}) vs Spy ELI{spy_level}")
                    all_pass = False

    # Check 2: Higher spy ELI should be harder to detect
    for detector_level in range(1, 6):
        for spy_level in range(1, 5):
            key1 = f"eli{detector_level}_vs_spy_eli{spy_level}"
            key2 = f"eli{detector_level}_vs_spy_eli{spy_level+1}"

            thresh1 = spy_table[key1]
            thresh2 = spy_table[key2]

            if thresh1[0] < 21 and thresh2[0] < 21:
                avg1 = (thresh1[0] + thresh1[1]) / 2
                avg2 = (thresh2[0] + thresh2[1]) / 2

                if avg1 >= avg2:
                    print(f"✗ FAIL: Spy ELI{spy_level+1} ({avg2}) should have higher threshold than Spy ELI{spy_level} ({avg1}) vs ELI{detector_level}")
                    all_pass = False

    if all_pass:
        print("✓ All validation checks passed")

    return all_pass


def test_raider_detection(config: Dict[str, Any], verbose: bool = False) -> bool:
    """Test raider detection probabilities."""
    print("\n" + "="*80)
    print("RAIDER DETECTION TESTS")
    print("="*80)

    raider_table = config['raider_detection_table']
    raider_config = config['raider_detection']

    # Test basic detection without modifiers
    print("\n1. Base Detection Probabilities (no modifiers)")
    print("-" * 80)
    print("Detector | CLK1  | CLK2  | CLK3  | CLK4  | CLK5  |")
    print("---------+-------+-------+-------+-------+-------|")

    for eli_level in range(1, 6):
        row = [f"ELI{eli_level}     |"]
        for clk_level in range(1, 6):
            key = f"eli{eli_level}_vs_clk{clk_level}"
            thresholds = raider_table[key]

            # Use average of min/max for base probability
            avg_threshold = (thresholds[0] + thresholds[1]) / 2
            prob = calculate_detection_probability(int(avg_threshold))

            if thresholds[0] >= 21:
                row.append(" NA    |")
            else:
                row.append(f" {prob:4.1f}% |")

        print("".join(row))

    # Test threshold variance (1d3 roll)
    print("\n2. Threshold Variance (1d3 roll)")
    print("-" * 80)

    test_case = (3, 2)  # ELI3 vs CLK2
    key = f"eli{test_case[0]}_vs_clk{test_case[1]}"
    thresholds = raider_table[key]

    print(f"\nTest case: ELI{test_case[0]} vs CLK{test_case[1]}")
    print(f"Threshold range: {thresholds[0]}-{thresholds[1]}")
    print()

    # Calculate probability for each possible threshold
    print(f"Roll | Threshold | Probability")
    print(f"-----+-----------+------------")

    for roll in range(1, 4):
        if roll == 1:
            threshold = thresholds[0]
            label = f"1    | {threshold:3} (min) |"
        elif roll == 3:
            threshold = thresholds[1]
            label = f"3    | {threshold:3} (max) |"
        else:
            threshold = (thresholds[0] + thresholds[1]) // 2
            label = f"2    | {threshold:3} (mid) |"

        prob = calculate_detection_probability(threshold)
        print(f"{label} {prob:6.1f}%")

    # Test ELI advantage
    print("\n3. ELI Advantage Effects")
    print("-" * 80)

    eli_major = raider_config['eli_advantage_major']
    eli_minor = raider_config['eli_advantage_minor']

    print(f"\nELI advantage thresholds:")
    print(f"  Major (ELI {eli_major}+ levels higher): use minimum threshold")
    print(f"  Minor (ELI {eli_minor} level higher): random threshold (1d3)")
    print(f"  None (ELI lower): use maximum threshold")
    print()

    test_case = (4, 2)  # ELI4 vs CLK2 = 2 level advantage (major)
    key = f"eli{test_case[0]}_vs_clk{test_case[1]}"
    thresholds = raider_table[key]

    print(f"Example: ELI{test_case[0]} vs CLK{test_case[1]} (ELI advantage: {test_case[0]-test_case[1]} levels)")
    print(f"Threshold range: {thresholds[0]}-{thresholds[1]}")

    prob_min = calculate_detection_probability(thresholds[0])
    prob_max = calculate_detection_probability(thresholds[1])

    print(f"  Major advantage (use min): {prob_min:.1f}% detection")
    print(f"  No advantage (use max): {prob_max:.1f}% detection")
    print(f"  Advantage benefit: {prob_min - prob_max:+.1f}%")

    # Validation checks
    print("\n4. Validation Checks")
    print("-" * 80)

    all_pass = True

    # Check 1: Higher detector ELI should have higher probability
    for clk_level in range(1, 6):
        for eli_level in range(1, 5):
            key1 = f"eli{eli_level}_vs_clk{clk_level}"
            key2 = f"eli{eli_level+1}_vs_clk{clk_level}"

            thresh1 = raider_table[key1]
            thresh2 = raider_table[key2]

            if thresh1[0] < 21 and thresh2[0] < 21:
                avg1 = (thresh1[0] + thresh1[1]) / 2
                avg2 = (thresh2[0] + thresh2[1]) / 2

                if avg1 <= avg2:
                    print(f"✗ FAIL: ELI{eli_level+1} ({avg2}) should have lower threshold than ELI{eli_level} ({avg1}) vs CLK{clk_level}")
                    all_pass = False

    # Check 2: Higher raider CLK should be harder to detect
    for eli_level in range(1, 6):
        for clk_level in range(1, 5):
            key1 = f"eli{eli_level}_vs_clk{clk_level}"
            key2 = f"eli{eli_level}_vs_clk{clk_level+1}"

            thresh1 = raider_table[key1]
            thresh2 = raider_table[key2]

            if thresh1[0] < 21 and thresh2[0] < 21:
                avg1 = (thresh1[0] + thresh1[1]) / 2
                avg2 = (thresh2[0] + thresh2[1]) / 2

                if avg1 >= avg2:
                    print(f"✗ FAIL: CLK{clk_level+1} ({avg2}) should have higher threshold than CLK{clk_level} ({avg1}) vs ELI{eli_level}")
                    all_pass = False

    if all_pass:
        print("✓ All validation checks passed")

    return all_pass


def main():
    """Run all detection probability tests."""
    verbose = '--verbose' in sys.argv

    print("="*80)
    print("EC4X DETECTION PROBABILITY TEST SUITE")
    print("="*80)
    print(f"\nLoading config from: config/espionage.toml")

    # Load config
    config_path = Path(__file__).parent.parent / "config" / "espionage.toml"
    if not config_path.exists():
        print(f"✗ ERROR: Config file not found at {config_path}")
        sys.exit(1)

    config = load_toml(config_path)
    print(f"✓ Config loaded successfully")

    # Run tests
    spy_pass = test_spy_detection(config, verbose)
    raider_pass = test_raider_detection(config, verbose)

    # Summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)

    if spy_pass and raider_pass:
        print("✓ All tests passed")
        sys.exit(0)
    else:
        if not spy_pass:
            print("✗ Spy scout detection tests failed")
        if not raider_pass:
            print("✗ Raider detection tests failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
