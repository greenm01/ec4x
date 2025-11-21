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


def generate_space_force_table(ships_config: Dict[str, Any]) -> str:
    """Generate Space Force (WEP1) table from ships.toml."""
    lines = [
        "CST = Minimum CST Level",
        "PC = Production Cost",
        "MC = Maintenance Cost (% of PC)",
        "AS = Attack Strength",
        "DS = Defensive Strength",
        "CC= Command Cost",
        "CR = Command Rating",
        "CL = Carry Limit",
        "",
        "| Class | Name              | CST | PC  | MC  | AS  | DS  | CC  | CR  | CL  |",
        "|:-----:| ----------------- |:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|",
    ]

    # Map ship sections to display order and details
    ship_order = [
        ("corvette", "CT", "Corvette"),
        ("frigate", "FG", "Frigate"),
        ("destroyer", "DD", "Destroyer"),
        ("light_cruiser", "CL", "Light Cruiser"),
        ("heavy_cruiser", "CA", "Heavy Cruiser"),
        ("battlecruiser", "BC", "Battle Cruiser"),
        ("battleship", "BB", "Battleship"),
        ("dreadnought", "DN", "Dreadnought"),
        ("super_dreadnought", "SD", "Super Dreadnought"),
        ("planetbreaker", "PB", "Planet-Breaker"),
        ("carrier", "CV", "Carrier"),
        ("supercarrier", "CX", "Super Carrier"),
        ("fighter", "FS", "Fighter Squadron"),
        ("raider", "RR", "Raider"),
        ("scout", "SC", "Scout"),
        ("starbase", "SB", "Starbase"),
    ]

    for section_name, ship_class, display_name in ship_order:
        ship = ships_config.get(section_name, {})
        if not ship:
            continue

        cst = ship.get('tech_level', ship.get('cst_min', 1))
        pc = ship.get('build_cost', 0)

        # Calculate MC percentage from upkeep_cost
        upkeep = ship.get('upkeep_cost', 0)
        if pc > 0:
            mc_percent = round((upkeep / pc) * 100)
        else:
            mc_percent = 0
        mc = f"{mc_percent}%"

        as_val = ship.get('attack_strength', 0)
        ds = ship.get('defense_strength', 0)
        cc = ship.get('command_cost', 'NA')
        cr = ship.get('command_rating', 'NA')
        cl = ship.get('carry_limit', 'NA')

        # Format values
        cc_str = str(cc) if cc != 'NA' else 'NA'
        cr_str = str(cr) if cr != 'NA' else 'NA'
        cl_str = str(cl) if cl != 'NA' and cl > 0 else 'NA'

        lines.append(
            f"| {ship_class:<5} | {display_name:<17} | {cst:<3} | {pc:<3} | {mc:<3} | {as_val:<3} | {ds:<3} | {cc_str:<3} | {cr_str:<3} | {cl_str:<3} |"
        )

    lines.append("")
    lines.append("*Source: config/ships.toml*")

    return "\n".join(lines)


def generate_ground_units_table(ground_config: Dict[str, Any]) -> str:
    """Generate Ground Units (WEP1) table from ground_units.toml."""
    lines = [
        "| **Class** | **Name**         | CST | PC  | MC  | AS  | DS  |",
        "| --------- | ---------------- |:---:| --- | --- |:---:|:---:|",
    ]

    # Map ground unit sections to display order
    units_order = [
        ("planetary_shield", "PS", "Planetary Shield"),
        ("ground_battery", "GB", "Ground Batteries"),
        ("army", "AA", "Armies"),
        ("marine_division", "MD", "Space Marines"),
    ]

    for section_name, unit_class, display_name in units_order:
        unit = ground_config.get(section_name, {})
        if not unit:
            continue

        cst = unit.get('cst_min', 1)
        pc = unit.get('build_cost', 0)
        upkeep = unit.get('upkeep_cost', 0)

        # Calculate MC percentage
        if pc > 0:
            mc_percent = round((upkeep / pc) * 100)
        else:
            mc_percent = 0
        mc = f"{mc_percent}%"

        as_val = unit.get('attack_strength', 0)
        ds = unit.get('defense_strength', 0)

        lines.append(
            f"| {unit_class:<9} | {display_name:<16} | {cst:<3} | {pc:<3} | {mc:<3} | {as_val:<3} | {ds:<3} |"
        )

    lines.append("")
    lines.append("*Source: config/ground_units.toml*")

    return "\n".join(lines)


def generate_spacelift_table(facilities_config: Dict[str, Any], ships_config: Dict[str, Any]) -> str:
    """Generate Spacelift Command (WEP1) table from facilities.toml and ships.toml."""
    lines = [
        "| **Class** | **Name**         | CST | PC  | MC  | CL  | DS  |",
        "|:---------:| ---------------- |:---:|:---:|:---:|:---:|:---:|",
    ]

    # Spaceport and Shipyard are in facilities.toml
    facilities_order = [
        ("spaceport", "SP", "Spaceport"),
        ("shipyard", "SY", "Shipyard"),
    ]

    for section_name, facility_class, display_name in facilities_order:
        facility = facilities_config.get(section_name, {})
        if not facility:
            continue

        cst = facility.get('cst_min', 1)
        pc = facility.get('build_cost', 0)
        upkeep = facility.get('upkeep_cost', 0)

        # Calculate MC percentage
        if pc > 0:
            mc_percent = round((upkeep / pc) * 100)
        else:
            mc_percent = 0
        mc = f"{mc_percent}%"

        cl = facility.get('carry_limit', 0)
        ds = facility.get('defense_strength', 0)

        lines.append(
            f"| {facility_class:<9} | {display_name:<16} | {cst:<3} | {pc:<3} | {mc:<3} | {cl:<3} | {ds:<3} |"
        )

    # ETAC and Troop Transports are in ships.toml
    ship_order = [
        ("etac", "ET", "ETAC"),
        ("troop_transport", "TT", "Troop Transports"),
    ]

    for section_name, ship_class, display_name in ship_order:
        ship = ships_config.get(section_name, {})
        if not ship:
            continue

        cst = ship.get('tech_level', ship.get('cst_min', 1))
        pc = ship.get('build_cost', 0)
        upkeep = ship.get('upkeep_cost', 0)

        # Calculate MC percentage
        if pc > 0:
            mc_percent = round((upkeep / pc) * 100)
        else:
            mc_percent = 0
        mc = f"{mc_percent}%"

        cl = ship.get('carry_limit', 0)
        ds = ship.get('defense_strength', 0)

        lines.append(
            f"| {ship_class:<9} | {display_name:<16} | {cst:<3} | {pc:<3} | {mc:<3} | {cl:<3} | {ds:<3} |"
        )

    lines.append("")
    lines.append("*Source: config/facilities.toml and config/ships.toml*")

    return "\n".join(lines)


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

    lines.append("")
    lines.append("*Source: config/prestige.toml [economic], [military], and [espionage] sections*")

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


def generate_espionage_prestige_table(prestige_config: Dict[str, Any], espionage_config: Dict[str, Any]) -> str:
    """Generate espionage prestige rewards/penalties table from prestige.toml and espionage.toml."""
    espionage_rewards = prestige_config.get('espionage', {})
    espionage_victims = prestige_config.get('espionage_victim', {})
    costs = espionage_config.get('costs', {})

    lines = [
        "| Espionage Action | Cost in EBPs | Description | Prestige Change for Player | Prestige Change for Target |",
        "|------------------|:------------:|-------------|----------------------------|----------------------------|",
    ]

    # Mapping of actions
    actions = [
        ("tech_theft", "tech_theft_victim", "Tech Theft", "tech_theft_ebp", "Attempt to steal critical R&D tech."),
        ("low_impact_sabotage", "low_impact_sabotage_victim", "Sabotage (Low Impact)", "sabotage_low_ebp", "Small-scale sabotage to a colony's industry."),
        ("high_impact_sabotage", "high_impact_sabotage_victim", "Sabotage (High Impact)", "sabotage_high_ebp", "Major sabotage to a colony's industry."),
        ("assassination", "assassination_victim", "Assassination", "assassination_ebp", "Attempt to eliminate a key figures within the target House."),
        ("cyber_attack", "cyber_attack_victim", "Cyber Attack", "cyber_attack_ebp", "Attempt to hack into a Starbase's systems to cause damage and chaos."),
        ("economic_manipulation", "economic_manipulation_victim", "Economic Manipulation", "economic_manipulation_ebp", "Influence markets to harm the target's economy"),
        ("psyops_campaign", "psyops_campaign_victim", "Psyops Campaign", "psyops_campaign_ebp", "Launch a misinformation campaign or demoralization effort."),
    ]

    for player_key, victim_key, name, cost_key, description in actions:
        player_prestige = espionage_rewards.get(player_key, 0)
        victim_prestige = espionage_victims.get(victim_key, 0)
        ebp_cost = costs.get(cost_key, 0)

        player_sign = "+" if player_prestige >= 0 else ""
        victim_sign = "+" if victim_prestige >= 0 else ""

        lines.append(
            f"| {name} | {ebp_cost} | {description} | {player_sign}{player_prestige} | {victim_sign}{victim_prestige} |"
        )

    lines.append("")
    lines.append("*Source: config/prestige.toml [espionage] and [espionage_victim] sections; config/espionage.toml [costs]*")

    return "\n".join(lines)


def generate_cic_detection_modifier_table(espionage_config: Dict[str, Any]) -> str:
    """Generate CIC detection modifier table from espionage.toml."""
    detection = espionage_config.get('detection', {})

    lines = [
        "| Total CIP Points | Automatic Detection Modifier |",
        "|:----------------:|:----------------------------:|",
    ]

    # Map CIP ranges to modifiers
    cip_ranges = [
        ("0", detection.get('cip_0_modifier', 0), "espionage automatically succeeds"),
        ("1-5", detection.get('cip_1_5_modifier', 1), None),
        ("6-10", detection.get('cip_6_10_modifier', 2), None),
        ("11-15", detection.get('cip_11_15_modifier', 3), None),
        ("16-20", detection.get('cip_16_20_modifier', 4), None),
        ("21+", detection.get('cip_21_plus_modifier', 5), "maximum"),
    ]

    for cip_range, modifier, note in cip_ranges:
        modifier_text = f"+{modifier}" if modifier > 0 else str(modifier)
        if note:
            modifier_text += f" ({note})"
        lines.append(f"| {cip_range} | {modifier_text} |")

    lines.append("")
    lines.append("*Source: config/espionage.toml [detection] section*")

    return "\n".join(lines)


def generate_cic_detection_thresholds_table(espionage_config: Dict[str, Any]) -> str:
    """Generate CIC detection thresholds table from espionage.toml."""
    detection = espionage_config.get('detection', {})

    lines = [
        "| CIC Level | Base 1D20 Roll | Detection Probability (with Automatic Modifier) |",
        "|:---------:|:--------------:|:-----------------------------------------------:|",
    ]

    # Map CIC levels to thresholds
    cic_levels = [
        ("CIC1", detection.get('cic1_threshold', 15), "25% → 30-50%"),
        ("CIC2", detection.get('cic2_threshold', 12), "40% → 45-65%"),
        ("CIC3", detection.get('cic3_threshold', 10), "55% → 60-80%"),
        ("CIC4", detection.get('cic4_threshold', 7), "65% → 70-90%"),
        ("CIC5", detection.get('cic5_threshold', 4), "80% → 85-95%"),
    ]

    for level, threshold, probability in cic_levels:
        lines.append(f"| {level} | > {threshold} | {probability} |")

    lines.append("")
    lines.append("*Source: config/espionage.toml [detection] section*")

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


def update_reference_spec(ships_table: str, ground_table: str, spacelift_table: str, prestige_table: str, morale_table: str, espionage_table: str, penalty_table: str):
    """Update docs/specs/reference.md with generated tables."""
    spec_file = Path("docs/specs/reference.md")

    if not spec_file.exists():
        print(f"Warning: {spec_file} not found, skipping update")
        return

    content = spec_file.read_text()

    # Markers for table replacement
    ships_start = "<!-- SPACE_FORCE_TABLE_START -->"
    ships_end = "<!-- SPACE_FORCE_TABLE_END -->"

    ground_start = "<!-- GROUND_UNITS_TABLE_START -->"
    ground_end = "<!-- GROUND_UNITS_TABLE_END -->"

    spacelift_start = "<!-- SPACELIFT_TABLE_START -->"
    spacelift_end = "<!-- SPACELIFT_TABLE_END -->"

    prestige_start = "<!-- PRESTIGE_TABLE_START -->"
    prestige_end = "<!-- PRESTIGE_TABLE_END -->"

    morale_start = "<!-- MORALE_TABLE_START -->"
    morale_end = "<!-- MORALE_TABLE_END -->"

    espionage_start = "<!-- ESPIONAGE_ACTIONS_TABLE_START -->"
    espionage_end = "<!-- ESPIONAGE_ACTIONS_TABLE_END -->"

    penalty_start = "<!-- PENALTY_MECHANICS_START -->"
    penalty_end = "<!-- PENALTY_MECHANICS_END -->"

    # Replace space force table if markers exist
    if ships_start in content and ships_end in content:
        start_idx = content.index(ships_start) + len(ships_start)
        end_idx = content.index(ships_end)
        content = content[:start_idx] + "\n" + ships_table + "\n" + content[end_idx:]
        print("✓ Updated space force table in reference.md")
    else:
        print("⚠ Space force table markers not found in reference.md")

    # Replace ground units table if markers exist
    if ground_start in content and ground_end in content:
        start_idx = content.index(ground_start) + len(ground_start)
        end_idx = content.index(ground_end)
        content = content[:start_idx] + "\n" + ground_table + "\n" + content[end_idx:]
        print("✓ Updated ground units table in reference.md")
    else:
        print("⚠ Ground units table markers not found in reference.md")

    # Replace spacelift table if markers exist
    if spacelift_start in content and spacelift_end in content:
        start_idx = content.index(spacelift_start) + len(spacelift_start)
        end_idx = content.index(spacelift_end)
        content = content[:start_idx] + "\n" + spacelift_table + "\n" + content[end_idx:]
        print("✓ Updated spacelift table in reference.md")
    else:
        print("⚠ Spacelift table markers not found in reference.md")

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


def update_diplomacy_spec(espionage_prestige_table: str, cic_modifier_table: str, cic_threshold_table: str):
    """Update docs/specs/diplomacy.md with generated tables."""
    spec_file = Path("docs/specs/diplomacy.md")

    if not spec_file.exists():
        print(f"Warning: {spec_file} not found, skipping update")
        return

    content = spec_file.read_text()

    # Markers for table replacement
    esp_prestige_start = "<!-- ESPIONAGE_PRESTIGE_TABLE_START -->"
    esp_prestige_end = "<!-- ESPIONAGE_PRESTIGE_TABLE_END -->"

    cic_modifier_start = "<!-- CIC_MODIFIER_TABLE_START -->"
    cic_modifier_end = "<!-- CIC_MODIFIER_TABLE_END -->"

    cic_threshold_start = "<!-- CIC_THRESHOLD_TABLE_START -->"
    cic_threshold_end = "<!-- CIC_THRESHOLD_TABLE_END -->"

    # Replace espionage prestige table if markers exist
    if esp_prestige_start in content and esp_prestige_end in content:
        start_idx = content.index(esp_prestige_start) + len(esp_prestige_start)
        end_idx = content.index(esp_prestige_end)
        content = content[:start_idx] + "\n" + espionage_prestige_table + "\n" + content[end_idx:]
        print("✓ Updated espionage prestige table in diplomacy.md")
    else:
        print("⚠ Espionage prestige table markers not found in diplomacy.md")

    # Replace CIC modifier table if markers exist
    if cic_modifier_start in content and cic_modifier_end in content:
        start_idx = content.index(cic_modifier_start) + len(cic_modifier_start)
        end_idx = content.index(cic_modifier_end)
        content = content[:start_idx] + "\n" + cic_modifier_table + "\n" + content[end_idx:]
        print("✓ Updated CIC modifier table in diplomacy.md")
    else:
        print("⚠ CIC modifier table markers not found in diplomacy.md")

    # Replace CIC threshold table if markers exist
    if cic_threshold_start in content and cic_threshold_end in content:
        start_idx = content.index(cic_threshold_start) + len(cic_threshold_start)
        end_idx = content.index(cic_threshold_end)
        content = content[:start_idx] + "\n" + cic_threshold_table + "\n" + content[end_idx:]
        print("✓ Updated CIC threshold table in diplomacy.md")
    else:
        print("⚠ CIC threshold table markers not found in diplomacy.md")

    # Write updated content
    spec_file.write_text(content)
    print(f"✓ Successfully updated {spec_file}")


def main():
    """Main script entry point."""
    print("EC4X Specification Sync")
    print("=" * 50)

    # Load config files
    config_dir = Path("config")

    print("\nLoading configuration files...")

    ships_config = load_toml(config_dir / "ships.toml")
    print(f"✓ Loaded {config_dir / 'ships.toml'}")

    ground_config = load_toml(config_dir / "ground_units.toml")
    print(f"✓ Loaded {config_dir / 'ground_units.toml'}")

    facilities_config = load_toml(config_dir / "facilities.toml")
    print(f"✓ Loaded {config_dir / 'facilities.toml'}")

    prestige_config = load_toml(config_dir / "prestige.toml")
    print(f"✓ Loaded {config_dir / 'prestige.toml'}")

    espionage_config = load_toml(config_dir / "espionage.toml")
    print(f"✓ Loaded {config_dir / 'espionage.toml'}")

    # Generate tables
    print("\nGenerating specification tables...")

    ships_table = generate_space_force_table(ships_config)
    print("✓ Generated space force table (16 ship types)")

    ground_table = generate_ground_units_table(ground_config)
    print("✓ Generated ground units table (4 unit types)")

    spacelift_table = generate_spacelift_table(facilities_config, ships_config)
    print("✓ Generated spacelift table (4 entries)")

    prestige_table = generate_prestige_table(prestige_config)
    print("✓ Generated prestige table (18 sources)")

    morale_table = generate_morale_table({})
    print("✓ Generated morale table (7 levels)")

    espionage_table = generate_espionage_actions_table(espionage_config)
    print("✓ Generated espionage table (7 actions)")

    penalty_table = generate_penalty_mechanics_table(prestige_config)
    print("✓ Generated penalty mechanics table (4 penalty types)")

    espionage_prestige_table = generate_espionage_prestige_table(prestige_config, espionage_config)
    print("✓ Generated espionage prestige table (7 actions)")

    cic_modifier_table = generate_cic_detection_modifier_table(espionage_config)
    print("✓ Generated CIC detection modifier table (6 ranges)")

    cic_threshold_table = generate_cic_detection_thresholds_table(espionage_config)
    print("✓ Generated CIC detection thresholds table (5 levels)")

    # Update spec files
    print("\nUpdating specification documents...")
    update_reference_spec(ships_table, ground_table, spacelift_table, prestige_table, morale_table, espionage_table, penalty_table)
    update_diplomacy_spec(espionage_prestige_table, cic_modifier_table, cic_threshold_table)

    print("\n" + "=" * 50)
    print("Sync complete!")
    print("\nNext steps:")
    print("1. Review changes in docs/specs/reference.md")
    print("2. Commit updated specifications")
    print("3. Ensure all references use enum names, not hardcoded values")


if __name__ == "__main__":
    main()
