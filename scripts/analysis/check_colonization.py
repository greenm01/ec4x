#!/usr/bin/env python3
"""
Check colonization progress and Act transitions from simulation database
"""

import sqlite3
import sys
import argparse

def analyze_game(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get total systems (fallback if systems table doesn't exist)
    try:
        cursor.execute("SELECT COUNT(*) FROM systems")
        total_systems = cursor.fetchone()[0]
    except:
        total_systems = 61  # Default for 4-player game

    print("=" * 80)
    print(f"COLONIZATION PROGRESS (Total systems: {total_systems})")
    print("=" * 80)

    # Get turn-by-turn colonization summary
    cursor.execute("""
        SELECT turn, act,
               SUM(total_colonies) as total_colonies,
               SUM(etac_ships) as total_etacs
        FROM diagnostics
        GROUP BY turn
        ORDER BY turn
    """)

    act_transitions = {}
    for row in cursor.fetchall():
        turn, act, colonies, etacs = row
        pct = (colonies / total_systems) * 100 if total_systems > 0 else 0

        # Track Act transitions
        if act not in act_transitions:
            act_transitions[act] = turn

        if turn <= 5 or turn % 5 == 0 or turn == 34:
            print(f"Turn {turn:2d} (Act {act}): {colonies:2d}/{total_systems} systems ({pct:5.1f}%) | {etacs:2d} ETACs")

    print("\n" + "=" * 80)
    print("ACT TRANSITIONS")
    print("=" * 80)
    for act in sorted(act_transitions.keys()):
        print(f"Act {act} started at turn {act_transitions[act]}")

    # Find when 90% colonization was reached
    cursor.execute("""
        SELECT turn, SUM(total_colonies) as total
        FROM diagnostics
        GROUP BY turn
        HAVING total >= ?
        ORDER BY turn
        LIMIT 1
    """, (int(total_systems * 0.90),))

    result = cursor.fetchone()
    if result:
        turn_90, colonies_90 = result
        pct_90 = (colonies_90 / total_systems) * 100
        print(f"\n90% threshold reached at turn {turn_90} ({colonies_90}/{total_systems} = {pct_90:.1f}%)")
    else:
        print("\n90% colonization not reached")

    print("\n" + "=" * 80)
    print("PER-HOUSE ETAC COUNTS (Key Turns)")
    print("=" * 80)

    cursor.execute("""
        SELECT turn, house_id, etac_ships
        FROM diagnostics
        WHERE turn IN (1, 5, 10, 15, 20, 25, 30, 34)
        ORDER BY turn, house_id
    """)

    current_turn = None
    for row in cursor.fetchall():
        turn, house_id, etacs = row
        if turn != current_turn:
            if current_turn is not None:
                print()
            print(f"Turn {turn:2d}:", end=" ")
            current_turn = turn
        print(f"{house_id}={etacs:2d}", end=" ")

    print("\n" + "=" * 80)

    conn.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Analyze colonization progress from simulation database"
    )
    parser.add_argument(
        "-s", "--seed",
        type=int,
        default=12345,
        help="Game seed (default: 12345)"
    )
    parser.add_argument(
        "--db",
        type=str,
        help="Direct path to database file (overrides --seed)"
    )

    args = parser.parse_args()

    # Determine database path
    if args.db:
        db_path = args.db
    else:
        db_path = f"balance_results/diagnostics/game_{args.seed}.db"

    try:
        analyze_game(db_path)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
