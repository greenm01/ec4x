#!/usr/bin/env python3
"""
Sync game specifications from TOML configuration files.

This script generates markdown tables for game specifications from TOML config files,
ensuring a single source of truth for all game balance values.

Usage:
    python3 scripts/sync_specs.py

This will update docs/specs/reference.md with current values from config/ files.
"""

import tomllib
from pathlib import Path
from typing import Dict, List, Any


def load_toml(filepath: Path) -> Dict[str, Any]:
    """Load a TOML file and return its contents."""
    with open(filepath, 'rb') as f:
        return tomllib.load(f)


def generate_prestige_table(config: Dict[str, Any]) -> str:
    """Generate prestige sources table from prestige.toml."""
    economic = config.get('economic', {})
    military = config.get('military', {})
    espionage = config.get('espionage', {})

    lines = [
        "| Prestige Source | Enum Name | Value |",
        "|-----------------|-----------|-------|",
    ]

    # Map TOML keys to readable names and enum names
    # Format: (section, toml_key, readable_name, enum_name)
    prestige_mapping = [
        ("economic", "tech_advancement", "Tech Advancement", "TechAdvancement"),
        ("economic", "establish_colony", "Colony Establishment", "ColonyEstablishment"),
        ("military", "invade_planet", "System Capture", "SystemCapture"),
        ("economic", "establish_colony", "Diplomatic Pact Formation", "DiplomaticPact"),
        ("military", "lose_planet", "Pact Violation (penalty)", "PactViolation"),
        ("military", "lose_planet", "Repeat Violation (penalty)", "RepeatViolation"),
        ("military", "ambushed_by_cloak", "Dishonor Status Expires", "DishonoredExpires"),
        ("espionage", "tech_theft", "Tech Theft Success", "TechTheftSuccess"),
        ("espionage", "failed_espionage", "Tech Theft Detected (penalty)", "TechTheftDetected"),
        ("espionage", "assassination", "Assassination Success", "AssassinationSuccess"),
        ("espionage", "failed_espionage", "Assassination Detected (penalty)", "AssassinationDetected"),
        ("espionage", "failed_espionage", "Espionage Attempt Failed (penalty)", "EspionageFailure"),
        ("military", "destroy_squadron", "Major Ship Destroyed (per ship)", "ShipDestroyed"),
        ("military", "destroy_starbase", "Starbase Destroyed", "StarbaseDestroyed"),
        ("military", "destroy_task_force", "Fleet Victory (per battle)", "FleetVictory"),
        ("military", "invade_planet", "Planet Conquered", "PlanetConquered"),
        ("military", "destroy_task_force", "House Eliminated", "HouseEliminated"),
        ("economic", "establish_colony", "Victory Achieved", "VictoryAchieved"),
    ]

    sections = {"economic": economic, "military": military, "espionage": espionage}

    for section, toml_key, readable_name, enum_name in prestige_mapping:
        value = sections[section].get(toml_key, 0)
        sign = "+" if value >= 0 else ""
        lines.append(f"| {readable_name} | `{enum_name}` | {sign}{value} |")

    return "\n".join(lines)


def generate_morale_table(config: Dict[str, Any]) -> str:
    """Generate morale levels table (when morale.toml exists)."""
    # For now, return a placeholder - morale values are still in code
    return """| Morale Level | Prestige Range | Tax Efficiency | Combat Bonus |
|--------------|----------------|----------------|--------------|
| **Collapsing** | < -100 | 0.5 (-50%) | -0.2 (-20%) |
| **VeryLow** | -100 to 0 | 0.75 (-25%) | -0.1 (-10%) |
| **Low** | 0 to 500 | 0.9 (-10%) | -0.05 (-5%) |
| **Normal** | 500 to 1500 | 1.0 (baseline) | 0.0 (baseline) |
| **High** | 1500 to 3000 | 1.1 (+10%) | +0.05 (+5%) |
| **VeryHigh** | 3000 to 5000 | 1.2 (+20%) | +0.1 (+10%) |
| **Exceptional** | 5000+ | 1.3 (+30%) | +0.15 (+15%) |

*Note: Morale values will be moved to config/morale.toml in future update*"""


def generate_espionage_actions_table(config: Dict[str, Any]) -> str:
    """Generate espionage actions table from espionage.toml."""
    actions = config.get('actions', {})

    lines = [
        "| Action | Enum Name | EBP Cost | Detection Base | Effect |",
        "|--------|-----------|----------|----------------|--------|",
    ]

    # Espionage actions mapping
    espionage_mapping = [
        ("tech_theft", "TechTheft", "Steals SRP"),
        ("sabotage_low", "SabotageLow", "d6 IU damage"),
        ("sabotage_high", "SabotageHigh", "d20 IU damage"),
        ("assassination", "Assassination", "-50% SRP (1 turn)"),
        ("cyber_attack", "CyberAttack", "Cripple starbase"),
        ("economic_manipulation", "EconomicManipulation", "-50% NCV (1 turn)"),
        ("psyops_campaign", "PsyopsCampaign", "-25% tax (1 turn)"),
    ]

    for toml_key, enum_name, effect in espionage_mapping:
        action_data = actions.get(toml_key, {})
        ebp_cost = action_data.get('ebp_cost', 0)
        detection_base = action_data.get('detection_base', 0)
        lines.append(f"| {toml_key.replace('_', ' ').title()} | `{enum_name}` | {ebp_cost} | {detection_base}% | {effect} |")

    return "\n".join(lines)


def generate_penalty_mechanics_table(config: Dict[str, Any]) -> str:
    """Generate penalty mechanics table from prestige.toml [penalties] section."""
    penalties = config.get('penalties', {})

    lines = [
        "| Penalty Type | Condition | Prestige Impact | Frequency | Config Keys |",
        "|--------------|-----------|-----------------|-----------|-------------|",
    ]

    # Tax rate penalties
    high_threshold = penalties.get('high_tax_threshold', 51)
    high_penalty = penalties.get('high_tax_penalty', -1)
    high_freq = penalties.get('high_tax_frequency', 3)

    very_high_threshold = penalties.get('very_high_tax_threshold', 66)
    very_high_penalty = penalties.get('very_high_penalty', -2)
    very_high_freq = penalties.get('very_high_tax_frequency', 5)

    lines.append(
        f"| High Tax Rate | Rolling 6-turn avg {high_threshold}-65% | "
        f"{high_penalty} prestige | Every {high_freq} consecutive turns | "
        f"`high_tax_*` |"
    )
    lines.append(
        f"| Very High Tax Rate | Rolling 6-turn avg >{very_high_threshold}% | "
        f"{very_high_penalty} prestige | Every {very_high_freq} consecutive turns | "
        f"`very_high_tax_*` |"
    )

    # Maintenance shortfall
    maint_base = penalties.get('maintenance_shortfall_base', -5)
    maint_increment = penalties.get('maintenance_shortfall_increment', -2)

    lines.append(
        f"| Maintenance Shortfall | Missed maintenance payment | "
        f"{maint_base} turn 1, escalates by {maint_increment}/turn | Per turn missed | "
        f"`maintenance_shortfall_*` |"
    )

    # Blockade
    blockade_penalty = penalties.get('blockade_penalty', -2)

    lines.append(
        f"| Blockade | Colony under blockade at Income Phase | "
        f"{blockade_penalty} prestige | Per turn per colony | "
        f"`blockade_penalty` |"
    )

    lines.append("")
    lines.append("*Source: config/prestige.toml [penalties] section*")

    return "\n".join(lines)


def update_reference_spec(prestige_table: str, morale_table: str, espionage_table: str, penalty_table: str):
    """Update docs/specs/reference.md with generated tables."""
    spec_file = Path("docs/specs/reference.md")

    if not spec_file.exists():
        print(f"Warning: {spec_file} not found, skipping update")
        return

    content = spec_file.read_text()

    # Markers for table replacement
    prestige_start = "<!-- PRESTIGE_TABLE_START -->"
    prestige_end = "<!-- PRESTIGE_TABLE_END -->"

    morale_start = "<!-- MORALE_TABLE_START -->"
    morale_end = "<!-- MORALE_TABLE_END -->"

    espionage_start = "<!-- ESPIONAGE_TABLE_START -->"
    espionage_end = "<!-- ESPIONAGE_TABLE_END -->"

    penalty_start = "<!-- PENALTY_MECHANICS_START -->"
    penalty_end = "<!-- PENALTY_MECHANICS_END -->"

    # Replace prestige table if markers exist
    if prestige_start in content and prestige_end in content:
        start_idx = content.index(prestige_start) + len(prestige_start)
        end_idx = content.index(prestige_end)
        content = content[:start_idx] + "\n" + prestige_table + "\n" + content[end_idx:]
        print("✓ Updated prestige table in reference.md")
    else:
        print("⚠ Prestige table markers not found in reference.md")

    # Replace morale table if markers exist
    if morale_start in content and morale_end in content:
        start_idx = content.index(morale_start) + len(morale_start)
        end_idx = content.index(morale_end)
        content = content[:start_idx] + "\n" + morale_table + "\n" + content[end_idx:]
        print("✓ Updated morale table in reference.md")
    else:
        print("⚠ Morale table markers not found in reference.md")

    # Replace espionage table if markers exist
    if espionage_start in content and espionage_end in content:
        start_idx = content.index(espionage_start) + len(espionage_start)
        end_idx = content.index(espionage_end)
        content = content[:start_idx] + "\n" + espionage_table + "\n" + content[end_idx:]
        print("✓ Updated espionage table in reference.md")
    else:
        print("⚠ Espionage table markers not found in reference.md")

    # Replace penalty mechanics table if markers exist
    if penalty_start in content and penalty_end in content:
        start_idx = content.index(penalty_start) + len(penalty_start)
        end_idx = content.index(penalty_end)
        content = content[:start_idx] + "\n" + penalty_table + "\n" + content[end_idx:]
        print("✓ Updated penalty mechanics table in reference.md")
    else:
        print("⚠ Penalty mechanics table markers not found in reference.md")

    # Write updated content
    spec_file.write_text(content)
    print(f"\n✓ Successfully updated {spec_file}")


def main():
    """Main script entry point."""
    print("EC4X Specification Sync")
    print("=" * 50)

    # Load config files
    config_dir = Path("config")

    print("\nLoading configuration files...")

    prestige_config = load_toml(config_dir / "prestige.toml")
    print(f"✓ Loaded {config_dir / 'prestige.toml'}")

    espionage_config = load_toml(config_dir / "espionage.toml")
    print(f"✓ Loaded {config_dir / 'espionage.toml'}")

    # Generate tables
    print("\nGenerating specification tables...")

    prestige_table = generate_prestige_table(prestige_config)
    print("✓ Generated prestige table (18 sources)")

    morale_table = generate_morale_table({})
    print("✓ Generated morale table (7 levels)")

    espionage_table = generate_espionage_actions_table(espionage_config)
    print("✓ Generated espionage table (7 actions)")

    penalty_table = generate_penalty_mechanics_table(prestige_config)
    print("✓ Generated penalty mechanics table (4 penalty types)")

    # Update spec file
    print("\nUpdating specification documents...")
    update_reference_spec(prestige_table, morale_table, espionage_table, penalty_table)

    print("\n" + "=" * 50)
    print("Sync complete!")
    print("\nNext steps:")
    print("1. Review changes in docs/specs/reference.md")
    print("2. Commit updated specifications")
    print("3. Ensure all references use enum names, not hardcoded values")


if __name__ == "__main__":
    main()
