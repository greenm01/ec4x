#!/usr/bin/env python3.11
"""
Diagnostic script to investigate marine production issues.
Checks build requirements, marine production over time, and transport/marine ratios.
"""

import sqlite3
import sys
from pathlib import Path

def analyze_game(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    print(f"\n{'='*80}")
    print(f"MARINE PRODUCTION ANALYSIS: {Path(db_path).name}")
    print(f"{'='*80}\n")

    # Get house names
    cursor.execute("SELECT DISTINCT house_id FROM diagnostics ORDER BY house_id")
    houses = [row[0] for row in cursor.fetchall()]

    # Marine production over time (every 5 turns)
    print("MARINE PRODUCTION TIMELINE")
    print("-" * 80)
    for house in houses:
        cursor.execute("""
            SELECT turn, marine_division_units
            FROM diagnostics
            WHERE house_id = ? AND turn % 5 = 0
            ORDER BY turn
        """, (house,))

        marines_timeline = cursor.fetchall()
        print(f"\n{house}:")
        print("  Turn:    ", " ".join(f"{t:3d}" for t, _ in marines_timeline))
        print("  Marines: ", " ".join(f"{m:3d}" for _, m in marines_timeline))

    # Transport vs Marine capacity analysis
    print("\n\nTRANSPORT vs MARINE CAPACITY (Final Turn)")
    print("-" * 80)
    cursor.execute("SELECT MAX(turn) FROM diagnostics")
    final_turn = cursor.fetchone()[0]

    print(f"{'House':<15} {'Transports':>10} {'Capacity':>10} {'Marines':>10} {'Fill %':>10}")
    print("-" * 80)

    for house in houses:
        cursor.execute("""
            SELECT troop_transport_ships, marine_division_units
            FROM diagnostics
            WHERE house_id = ? AND turn = ?
        """, (house, final_turn))

        row = cursor.fetchone()
        transports = row[0] if row else 0
        marines = row[1] if row else 0
        capacity = transports * 3  # Each transport holds 3 marines
        fill_pct = (marines / capacity * 100) if capacity > 0 else 0

        print(f"{house:<15} {transports:>10} {capacity:>10} {marines:>10} {fill_pct:>9.1f}%")

    # Check if marines are being built at all
    print("\n\nMARINE CONSTRUCTION ACTIVITY")
    print("-" * 80)
    print(f"{'House':<15} {'Marines Built':>15} {'Transports Built':>18}")
    print("-" * 80)

    for house in houses:
        # Get initial and final marines
        cursor.execute("""
            SELECT marine_division_units FROM diagnostics
            WHERE house_id = ? AND turn = 1
        """, (house,))
        row = cursor.fetchone()
        initial_marines = row[0] if row else 0

        cursor.execute("""
            SELECT marine_division_units FROM diagnostics
            WHERE house_id = ? AND turn = ?
        """, (house, final_turn))
        row = cursor.fetchone()
        final_marines = row[0] if row else 0

        marines_built = max(0, final_marines - initial_marines)

        # Transports built (final - initial)
        cursor.execute("""
            SELECT troop_transport_ships FROM diagnostics
            WHERE house_id = ? AND turn = 1
        """, (house,))
        row = cursor.fetchone()
        initial_transports = row[0] if row else 0

        cursor.execute("""
            SELECT troop_transport_ships FROM diagnostics
            WHERE house_id = ? AND turn = ?
        """, (house, final_turn))
        row = cursor.fetchone()
        final_transports = row[0] if row else 0

        transports_built = max(0, final_transports - initial_transports)

        print(f"{house:<15} {marines_built:>15} {transports_built:>18}")

    # Colony count over time
    print("\n\nCOLONY COUNT (Every 5 turns)")
    print("-" * 80)
    for house in houses:
        cursor.execute("""
            SELECT turn, total_colonies
            FROM diagnostics
            WHERE house_id = ? AND turn % 5 = 0
            ORDER BY turn
        """, (house,))

        colonies_timeline = cursor.fetchall()
        print(f"\n{house}:")
        print("  Turn:     ", " ".join(f"{t:3d}" for t, _ in colonies_timeline))
        print("  Colonies: ", " ".join(f"{c:3d}" for _, c in colonies_timeline))

    # Expected vs actual marines
    print("\n\nEXPECTED vs ACTUAL MARINES (Final Turn)")
    print("-" * 80)
    print(f"{'House':<15} {'Colonies':>10} {'Expected':>10} {'Actual':>10} {'Ratio':>10}")
    print("-" * 80)

    for house in houses:
        cursor.execute("""
            SELECT total_colonies, marine_division_units
            FROM diagnostics
            WHERE house_id = ? AND turn = ?
        """, (house, final_turn))

        row = cursor.fetchone()
        colonies = row[0] if row else 0
        actual_marines = row[1] if row else 0
        expected_marines = colonies * 10  # base_marines_per_colony = 10
        ratio = actual_marines / expected_marines if expected_marines > 0 else 0

        print(f"{house:<15} {colonies:>10} {expected_marines:>10} {actual_marines:>10} {ratio:>9.1%}")

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3.11 check_marine_production.py <db_path>")
        print("Example: python3.11 check_marine_production.py balance_results/diagnostics/game_12345.db")
        sys.exit(1)

    db_path = sys.argv[1]
    if not Path(db_path).exists():
        print(f"Error: Database not found: {db_path}")
        sys.exit(1)

    analyze_game(db_path)
