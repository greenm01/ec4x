#!/usr/bin/env python3.11
"""
Auto-generate diagnostic_columns.json from CSV writer source code

Parses src/ai/analysis/diagnostics/csv_writer.nim to extract CSVHeaderString
and generates the reference JSON file for analysis scripts.

Usage:
    python3.11 scripts/update_diagnostic_columns.py

Output:
    scripts/analysis/diagnostic_columns.json (updated in place)
"""

import re
import json
from pathlib import Path
from datetime import datetime


def parse_csv_header_from_nim(nim_file_path: str) -> list[str]:
    """Parse CSVHeaderString constant from csv_writer.nim"""

    with open(nim_file_path, 'r') as f:
        content = f.read()

    # Find the CSVHeaderString constant (uses & for concatenation)
    # Pattern: const CSVHeaderString = "..." & \n "..." & ...
    pattern = r'CSVHeaderString\s*=\s*(".*?"(?:\s*&\s*\n?\s*".*?")*)'
    match = re.search(pattern, content, re.DOTALL)

    if not match:
        raise ValueError("Could not find CSVHeaderString in csv_writer.nim")

    # Extract all quoted strings and concatenate
    string_parts = match.group(1)
    quoted_strings = re.findall(r'"([^"]*)"', string_parts)
    header_string = ''.join(quoted_strings)

    # Split by comma and clean up
    columns = [col.strip() for col in header_string.split(',') if col.strip()]

    return columns


def get_ship_role_classifications() -> dict:
    """Ship role classifications from specs/10-reference.md"""
    return {
        "Escort": [
            "corvette_ships",
            "frigate_ships",
            "destroyer_ships",
            "light_cruiser_ships",
            "scout_ships"
        ],
        "Capital": [
            "heavy_cruiser_ships",
            "battlecruiser_ships",
            "battleship_ships",
            "dreadnought_ships",
            "super_dreadnought_ships",
            "carrier_ships",
            "super_carrier_ships",
            "raider_ships"
        ],
        "Auxiliary": [
            "etac_ships",
            "troop_transport_ships"
        ],
        "Fighter": [
            "fighter_ships",
            "total_fighters"
        ],
        "SpecialWeapon": [
            "planet_breaker_ships"
        ]
    }


def get_ship_classes() -> dict:
    """Ship class abbreviations and full names from specs"""
    return {
        "CT": "Corvette (Escort)",
        "FG": "Frigate (Escort)",
        "DD": "Destroyer (Escort)",
        "CL": "Light Cruiser (Escort)",
        "SC": "Scout (Escort)",
        "CA": "Heavy Cruiser (Capital)",
        "BC": "Battle Cruiser (Capital)",
        "BB": "Battleship (Capital)",
        "DN": "Dreadnought (Capital)",
        "SD": "Super Dreadnought (Capital)",
        "CV": "Carrier (Capital)",
        "CX": "Super Carrier (Capital)",
        "RR": "Raider (Capital)",
        "ET": "ETAC (Auxiliary)",
        "TT": "Troop Transport (Auxiliary)",
        "FS": "Fighter Squadron (Fighter)",
        "PB": "Planet-Breaker (SpecialWeapon)"
    }


def generate_diagnostic_columns_json(columns: list[str]) -> dict:
    """Generate the complete JSON structure"""

    return {
        "column_count": len(columns),
        "ship_role_classifications": get_ship_role_classifications(),
        "ship_classes": get_ship_classes(),
        "diagnostic_columns": columns,
        "last_updated": datetime.now().strftime("%Y-%m-%d"),
        "source": "balance_results/diagnostics/game_*.csv"
    }


def main():
    # Paths (relative to project root)
    project_root = Path(__file__).parent.parent
    nim_file = project_root / "src/ai/analysis/diagnostics/csv_writer.nim"
    output_file = project_root / "scripts/analysis/diagnostic_columns.json"

    if not nim_file.exists():
        print(f"❌ Error: Source file not found: {nim_file}")
        return False

    print("📊 Parsing diagnostic columns from csv_writer.nim")

    try:
        columns = parse_csv_header_from_nim(str(nim_file))
        print(f"✅ Found {len(columns)} diagnostic columns")

        json_data = generate_diagnostic_columns_json(columns)

        # Write to file with nice formatting
        with open(output_file, 'w') as f:
            json.dump(json_data, f, indent=2)

        print(f"✅ Updated: {output_file}")
        print(f"   Column count: {json_data['column_count']}")
        print(f"   Last updated: {json_data['last_updated']}")

        return True

    except Exception as e:
        print(f"❌ Error: {e}")
        return False


if __name__ == "__main__":
    import sys
    success = main()
    sys.exit(0 if success else 1)
