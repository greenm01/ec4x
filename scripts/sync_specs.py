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

        # Use maintenance_percent if specified, otherwise calculate from upkeep_cost
        if 'maintenance_percent' in ship:
            mc_percent = ship['maintenance_percent']
        else:
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

        # Format values - treat 0 as NA for CC/CR
        cc_str = str(cc) if cc != 'NA' and cc != 0 else 'NA'
        cr_str = str(cr) if cr != 'NA' and cr != 0 else 'NA'
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

        # Use maintenance_percent if specified, otherwise calculate
        if 'maintenance_percent' in unit:
            mc_percent = unit['maintenance_percent']
        else:
            upkeep = unit.get('upkeep_cost', 0)
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

        # Use maintenance_percent if specified, otherwise calculate
        if 'maintenance_percent' in facility:
            mc_percent = facility['maintenance_percent']
        else:
            upkeep = facility.get('upkeep_cost', 0)
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

        # Use maintenance_percent if specified, otherwise calculate
        if 'maintenance_percent' in ship:
            mc_percent = ship['maintenance_percent']
        else:
            upkeep = ship.get('upkeep_cost', 0)
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


# ============================================================================
# Economy Table Generators
# ============================================================================

def generate_raw_material_table(economy_config: Dict[str, Any]) -> str:
    """Generate RAW material efficiency table from economy.toml."""
    raw = economy_config.get('raw_material_efficiency', {})

    lines = [
        "| RAW       | Eden | Lush | Benign | Harsh | Hostile | Desolate | Extreme |",
        "| --------- |:----:|:----:|:------:|:-----:|:-------:|:--------:|:-------:|",
    ]

    # RAW quality levels
    qualities = [
        ("very_poor", "Very Poor"),
        ("poor", "Poor"),
        ("abundant", "Abundant"),
        ("rich", "Rich"),
        ("very_rich", "Very Rich"),
    ]

    planets = ["eden", "lush", "benign", "harsh", "hostile", "desolate", "extreme"]

    for quality_key, quality_name in qualities:
        values = []
        for planet in planets:
            key = f"{quality_key}_{planet}"
            efficiency = raw.get(key, 0)
            # Convert decimal to percentage string
            percent_str = f"{int(efficiency * 100)}%"
            values.append(percent_str)

        line = f"| {quality_name:<9} | {values[0]:^4} | {values[1]:^4} | {values[2]:^6} | {values[3]:^5} | {values[4]:^7} | {values[5]:^8} | {values[6]:^7} |"
        lines.append(line)

    lines.append("")
    lines.append("*Source: config/economy.toml [raw_material_efficiency] section*")

    return "\n".join(lines)


def generate_tax_penalty_table(prestige_config: Dict[str, Any]) -> str:
    """Generate high-tax prestige penalty table from prestige.toml."""
    tax_penalties = prestige_config.get('tax_penalties', {})

    lines = [
        "| Rolling 6-Turn Average Tax Rate | Prestige Penalty per Turn |",
        "|---------------------------------|---------------------------|",
    ]

    # Process 6 tiers
    for tier_num in range(1, 7):
        min_rate = tax_penalties.get(f'tier_{tier_num}_min', 0)
        max_rate = tax_penalties.get(f'tier_{tier_num}_max', 0)
        penalty = tax_penalties.get(f'tier_{tier_num}_penalty', 0)

        if tier_num == 1:
            range_str = f"≤ {max_rate} %"
        else:
            range_str = f"{min_rate} – {max_rate} %"

        lines.append(f"| {range_str:<31} | {penalty:^25} |")

    lines.append("")
    lines.append("*Source: config/prestige.toml [tax_penalties] section*")

    return "\n".join(lines)


def generate_tax_incentive_table(prestige_config: Dict[str, Any], economy_config: Dict[str, Any]) -> str:
    """Generate low-tax incentive table from prestige.toml and economy.toml."""
    tax_incentives = prestige_config.get('tax_incentives', {})
    tax_pop_growth = economy_config.get('tax_population_growth', {})

    lines = [
        "| Tax Rate This Turn | Population Growth Bonus (multiplier to natural 2% base) | Bonus Prestige per Colony This Turn |",
        "|--------------------|----------------------------------------------------------|-------------------------------------|",
    ]

    # Process 5 tiers (reverse order - highest rates first)
    for tier_num in range(1, 6):
        # Get range from either config (both have same ranges)
        min_rate = tax_incentives.get(f'tier_{tier_num}_min', 0)
        max_rate = tax_incentives.get(f'tier_{tier_num}_max', 0)

        # Get population multiplier from economy config
        multiplier = tax_pop_growth.get(f'tier_{tier_num}_pop_multiplier', 1.0)

        # Get prestige from prestige config
        prestige = tax_incentives.get(f'tier_{tier_num}_prestige', 0)

        range_str = f"{min_rate} – {max_rate} %"

        if tier_num == 1:
            bonus_str = "No bonus"
        else:
            bonus_pct = int((multiplier - 1.0) * 100)
            bonus_str = f"×{multiplier:.2f} (+{bonus_pct} %)"

        prestige_str = "–" if prestige == 0 else f"+{prestige}"

        lines.append(f"| {range_str:<18} | {bonus_str:<56} | {prestige_str:^35} |")

    lines.append("")
    lines.append("*Source: config/prestige.toml [tax_incentives] and config/economy.toml [tax_population_growth] sections*")

    return "\n".join(lines)


def generate_iu_investment_table(economy_config: Dict[str, Any]) -> str:
    """Generate IU investment cost multiplier table from economy.toml."""
    iu_inv = economy_config.get('industrial_investment', {})

    lines = [
        "| IU Investment (% of PU) | Cost Multiplier | PP  |",
        "| ----------------------- |:---------------:|:---:|",
    ]

    # Tier 1: Up to 50%
    tier_1_mult = iu_inv.get('tier_1_multiplier', 1.0)
    tier_1_pp = iu_inv.get('tier_1_pp', 30)
    lines.append(f"| Up to 50%               | {tier_1_mult}             | {tier_1_pp}  |")

    # Tiers 2-4: ranges
    for tier_num in range(2, 5):
        min_pct = iu_inv.get(f'tier_{tier_num}_min_percent', 0)
        max_pct = iu_inv.get(f'tier_{tier_num}_max_percent', 0)
        mult = iu_inv.get(f'tier_{tier_num}_multiplier', 1.0)
        pp = iu_inv.get(f'tier_{tier_num}_pp', 0)

        range_str = f"{min_pct}% - {max_pct}%"
        lines.append(f"| {range_str:<23} | {mult}             | {pp:<3} |")

    # Tier 5: 151% and above
    tier_5_mult = iu_inv.get('tier_5_multiplier', 2.5)
    tier_5_pp = iu_inv.get('tier_5_pp', 75)
    lines.append(f"| 151% and above          | {tier_5_mult}             | {tier_5_pp}  |")

    lines.append("")
    lines.append("*Source: config/economy.toml [industrial_investment] section*")

    return "\n".join(lines)


def generate_colonization_cost_table(economy_config: Dict[str, Any]) -> str:
    """Generate colonization costs table from economy.toml."""
    colonization = economy_config.get('colonization', {})

    lines = [
        "| Conditions | PP/PTU |",
        "| ---------- |:------:|",
    ]

    planets = [
        ("Eden", "eden"),
        ("Lush", "lush"),
        ("Benign", "benign"),
        ("Harsh", "harsh"),
        ("Hostile", "hostile"),
        ("Desolate", "desolate"),
        ("Extreme", "extreme"),
    ]

    for display_name, key in planets:
        pp_per_ptu = colonization.get(f'{key}_pp_per_ptu', 0)
        lines.append(f"| {display_name:<10} | {pp_per_ptu:<6} |")

    lines.append("")
    lines.append("*Source: config/economy.toml [colonization] section*")

    return "\n".join(lines)


def generate_maintenance_shortfall_table(prestige_config: Dict[str, Any]) -> str:
    """Generate maintenance shortfall prestige penalty table from prestige.toml."""
    penalties = prestige_config.get('penalties', {})

    base = penalties.get('maintenance_shortfall_base', -5)
    increment = penalties.get('maintenance_shortfall_increment', -2)

    lines = [
        "| Consecutive Turns of Missed Full Upkeep | Prestige Loss This Turn | Cumulative Example |",
        "|-----------------------------------------|-------------------------|--------------------|",
    ]

    # Calculate penalties for 4 rows
    cumulative = 0
    for turn in range(1, 5):
        if turn == 1:
            penalty = base
            turn_label = "1st turn"
        elif turn == 2:
            penalty = base + (increment * (turn - 1))
            turn_label = "2nd consecutive turn"
        elif turn == 3:
            penalty = base + (increment * (turn - 1))
            turn_label = "3rd consecutive turn"
        else:
            penalty = base + (increment * (turn - 1))
            turn_label = "4th+ consecutive turn"

        cumulative += penalty

        if turn == 4:
            # For 4th+ show example progression
            next_cumulative = cumulative + penalty
            next_next = next_cumulative + penalty
            lines.append(f"| {turn_label:<39} | {penalty:>23} per turn | –{abs(cumulative)}, –{abs(next_cumulative)}, etc. {' ':<6}|")
        else:
            lines.append(f"| {turn_label:<39} | {penalty:>23} | {cumulative:>18} |")

    lines.append("")
    lines.append("*Source: config/prestige.toml [penalties] section*")

    return "\n".join(lines)


# ============================================================================
# Technology Table Generators
# ============================================================================

def generate_economic_level_table(tech_config: Dict[str, Any]) -> str:
    """Generate Economic Level (EL) table from tech.toml."""
    el = tech_config.get('economic_level', {})

    lines = [
        "| EL  | ERP Cost | EL MOD |",
        "|:---:|:--------:|:------:|",
    ]

    for level in range(1, 12):
        erp = el.get(f'level_{level}_erp', 0)
        mod = el.get(f'level_{level}_mod', 0.0)

        el_str = f"{level:02d}" if level < 11 else "11+"
        erp_str = str(erp) if level < 11 else f"{erp}+"
        mod_str = f"{mod:.2f}"

        lines.append(f"| {el_str} | {erp_str:<8} | {mod_str:<6} |")

    lines.append("")
    lines.append("*Source: config/tech.toml [economic_level] section*")

    return "\n".join(lines)


def generate_science_level_table(tech_config: Dict[str, Any]) -> str:
    """Generate Science Level (SL) table from tech.toml."""
    sl = tech_config.get('science_level', {})

    lines = [
        "| SL  | SRP Cost |",
        "|:---:|:--------:|",
    ]

    for level in range(1, 9):
        srp = sl.get(f'level_{level}_srp', 0)

        sl_str = f"{level:02d}" if level < 8 else "08+"
        srp_str = str(srp) if level < 8 else f"{srp}+"

        lines.append(f"| {sl_str} | {srp_str:<8} |")

    lines.append("")
    lines.append("*Source: config/tech.toml [science_level] section*")

    return "\n".join(lines)


def generate_tech_level_table(tech_config: Dict[str, Any], tech_name: str, max_levels: int = 5) -> str:
    """Generate a generic tech level table (CST, WEP, TER, ELI, CLK, SLD, CIC)."""
    tech_section = tech_config.get(tech_name, {})

    lines = [
        f"| {tech_name.upper()} Level | SL  | TRP Cost |",
        "|:---------:|:---:| -------- |",
    ]

    # Handle special case for terraforming which has 7 levels
    if 'terraforming' in tech_name:
        max_levels = 7

    for level in range(1, max_levels + 1):
        sl = tech_section.get(f'level_{level}_sl', 0)
        trp = tech_section.get(f'level_{level}_trp', 0)

        # Format level string (e.g., CST1, WEP1)
        if tech_name == 'construction_tech':
            prefix = 'CST'
        elif tech_name == 'weapons_tech':
            prefix = 'WEP'
        elif tech_name == 'terraforming_tech':
            prefix = 'TER'
        elif tech_name == 'electronic_intelligence':
            prefix = 'ELI'
        elif tech_name == 'cloaking_tech':
            prefix = 'CLK'
        elif tech_name == 'shield_tech':
            prefix = 'SLD'
        elif tech_name == 'counter_intelligence_tech':
            prefix = 'CIC'
        else:
            prefix = 'XXX'

        level_str = f"{prefix}{level}"
        if level == max_levels and tech_name in ['construction_tech', 'weapons_tech']:
            level_str += "+"

        trp_str = f"\\*{trp}" if level == max_levels and tech_name in ['construction_tech', 'weapons_tech'] else str(trp)

        lines.append(f"| {level_str:<9} | {sl:<3} | {trp_str:<8} |")

    lines.append("")
    lines.append(f"*Source: config/tech.toml [{tech_name}] section*")

    return "\n".join(lines)


def generate_terraforming_upgrade_cost_table(tech_config: Dict[str, Any]) -> str:
    """Generate terraforming planet upgrade cost table from tech.toml."""
    ter_costs = tech_config.get('terraforming_upgrade_costs', {})

    lines = [
        "| Planet Class | Required TER | PU        | PP   |",
        "|:------------ |:------------:|:---------:|:----:|",
    ]

    planets = [
        ("Extreme", "extreme"),
        ("Desolate", "desolate"),
        ("Hostile", "hostile"),
        ("Harsh", "harsh"),
        ("Benign", "benign"),
        ("Lush", "lush"),
        ("Eden", "eden"),
    ]

    for display_name, key in planets:
        ter_level = ter_costs.get(f'{key}_ter', 0)
        pu_min = ter_costs.get(f'{key}_pu_min', 0)
        pu_max = ter_costs.get(f'{key}_pu_max', 0)
        pp = ter_costs.get(f'{key}_pp', 0)

        ter_str = f"TER{ter_level}"

        # Format PU range
        if pu_max >= 999999:
            pu_str = f"{pu_min}+"
        elif pu_max >= 1000:
            if pu_min >= 1000:
                pu_str = f"{pu_min//1000}k - {pu_max//1000}k"
            else:
                pu_str = f"{pu_min}- {pu_max//1000}k"
        else:
            pu_str = f"{pu_min} - {pu_max}"

        pp_str = "NA" if pp == 0 else str(pp)

        lines.append(f"| {display_name:<12} | {ter_str:<12} | {pu_str:<9} | {pp_str:<4} |")

    lines.append("")
    lines.append("*Source: config/tech.toml [terraforming_upgrade_costs] section*")

    return "\n".join(lines)


def generate_fighter_doctrine_table(tech_config: Dict[str, Any]) -> str:
    """Generate Fighter Doctrine (FD) table from tech.toml."""
    fd = tech_config.get('fighter_doctrine', {})

    lines = [
        "| Tech Level | Prerequisites | TRP Cost | SL Required | Capacity Multiplier |",
        "|:----------:|--------------|:--------:|:-----------:|:-------------------:|",
    ]

    for level in range(1, 4):
        sl_req = fd.get(f'level_{level}_sl', 0)
        trp = fd.get(f'level_{level}_trp', 0)
        capacity = fd.get(f'level_{level}_capacity_multiplier', 1.0)

        level_str = ["FD I", "FD II", "FD III"][level - 1]
        prereq = "None" if level == 1 else ["", "FD I", "FD II"][level - 1]
        trp_str = "N/A" if trp == 0 else str(trp)
        capacity_str = f"{capacity}x"

        lines.append(f"| {level_str:<10} | {prereq:<12} | {trp_str:<8} | {sl_req:<11} | {capacity_str:<19} |")

    lines.append("")
    lines.append("*Source: config/tech.toml [fighter_doctrine] section*")

    return "\n".join(lines)


def generate_aco_table(tech_config: Dict[str, Any]) -> str:
    """Generate Advanced Carrier Operations (ACO) table from tech.toml."""
    aco = tech_config.get('advanced_carrier_operations', {})

    lines = [
        "| Tech Level | Prerequisites | TRP Cost | SL Required | CV Capacity | CX Capacity |",
        "|:----------:|--------------|:--------:|:-----------:|:-----------:|:-----------:|",
    ]

    for level in range(1, 4):
        sl_req = aco.get(f'level_{level}_sl', 0)
        trp = aco.get(f'level_{level}_trp', 0)
        cv_cap = aco.get(f'level_{level}_cv_capacity', 0)
        cx_cap = aco.get(f'level_{level}_cx_capacity', 0)

        level_str = ["ACO I", "ACO II", "ACO III"][level - 1]
        prereq = "None" if level == 1 else ["", "ACO I", "ACO II"][level - 1]
        trp_str = "N/A" if trp == 0 else str(trp)

        lines.append(f"| {level_str:<10} | {prereq:<12} | {trp_str:<8} | {sl_req:<11} | {cv_cap} FS        | {cx_cap} FS        |")

    lines.append("")
    lines.append("*Source: config/tech.toml [advanced_carrier_operations] section*")

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


def replace_inline_values_diplomacy(content: str, diplomacy_config: Dict[str, Any]) -> str:
    """Replace inline marker values in diplomacy.md with values from config."""
    import re

    # Define inline value replacements for diplomacy.md
    replacements = {
        'DISHONORED_TURNS': lambda: str(diplomacy_config['pact_violations']['dishonored_status_turns']),
        'DIPLOMATIC_ISOLATION_TURNS': lambda: str(diplomacy_config['pact_violations']['diplomatic_isolation_turns']),
        'REPEAT_VIOLATION_WINDOW': lambda: str(diplomacy_config['pact_violations']['repeat_violation_window']),
        'PACT_REINSTATEMENT_TURNS': lambda: str(diplomacy_config['pact_violations']['pact_reinstatement_cooldown']),
        'TECH_THEFT_SRP': lambda: str(diplomacy_config['espionage_effects']['tech_theft_srp_stolen']),
        'LOW_SAB_DICE': lambda: diplomacy_config['espionage_effects']['low_sabotage_dice'],
        'HIGH_SAB_DICE': lambda: diplomacy_config['espionage_effects']['high_sabotage_dice'],
        'ASSASSIN_REDUCTION': lambda: str(int(diplomacy_config['espionage_effects']['assassination_srp_reduction'] * 100)),
        'ASSASSIN_TURNS': lambda: "one" if diplomacy_config['espionage_effects']['assassination_duration_turns'] == 1 else str(diplomacy_config['espionage_effects']['assassination_duration_turns']),
        'ECON_DISRUPT_TURNS': lambda: "one" if diplomacy_config['espionage_effects']['economic_disruption_duration_turns'] == 1 else str(diplomacy_config['espionage_effects']['economic_disruption_duration_turns']),
        'PROPAGANDA_REDUCTION': lambda: str(int(diplomacy_config['espionage_effects']['propaganda_tax_reduction'] * 100)),
        'PROPAGANDA_TURNS': lambda: "one" if diplomacy_config['espionage_effects']['propaganda_duration_turns'] == 1 else str(diplomacy_config['espionage_effects']['propaganda_duration_turns']),
        'FAILED_ESPIONAGE_PRESTIGE': lambda: str(abs(diplomacy_config['detection']['failed_espionage_prestige_loss'])),
    }

    # Replace each inline marker with plain value (removes markers)
    for marker, value_func in replacements.items():
        pattern = f"<!-- {marker} -->.*?<!-- /{marker} -->"
        replacement = value_func()
        content = re.sub(pattern, replacement, content)

    return content


def update_diplomacy_spec(espionage_prestige_table: str, cic_modifier_table: str, cic_threshold_table: str, diplomacy_config: Dict[str, Any]):
    """Update docs/specs/diplomacy.md with generated tables and inline values."""
    spec_file = Path("docs/specs/diplomacy.md")

    if not spec_file.exists():
        print(f"Warning: {spec_file} not found, skipping update")
        return

    content = spec_file.read_text()

    # Replace inline values first
    content = replace_inline_values_diplomacy(content, diplomacy_config)

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


def update_economy_spec(raw_table: str, tax_penalty_table: str, tax_incentive_table: str,
                        iu_table: str, colonization_table: str, maintenance_shortfall_table: str,
                        el_table: str, sl_table: str, cst_table: str, wep_table: str,
                        ter_table: str, ter_upgrade_table: str, eli_table: str, clk_table: str,
                        sld_table: str, cic_table: str, fd_table: str, aco_table: str,
                        economy_config: Dict[str, Any], construction_config: Dict[str, Any], military_config: Dict[str, Any], tech_config: Dict[str, Any]):
    """Update docs/specs/economy.md with generated tables and inline values."""
    spec_file = Path("docs/specs/economy.md")

    if not spec_file.exists():
        print(f"⚠ {spec_file} not found, skipping economy.md update")
        return

    content = spec_file.read_text()

    # Replace inline values first
    content = replace_inline_values(content, economy_config, construction_config, military_config, tech_config)

    # Define all markers for economy tables
    markers = {
        "RAW_MATERIAL_TABLE": (raw_table, "RAW material efficiency table"),
        "TAX_PENALTY_TABLE": (tax_penalty_table, "tax penalty table"),
        "TAX_INCENTIVE_TABLE": (tax_incentive_table, "tax incentive table"),
        "IU_INVESTMENT_TABLE": (iu_table, "IU investment table"),
        "COLONIZATION_COST_TABLE": (colonization_table, "colonization cost table"),
        "MAINTENANCE_SHORTFALL_TABLE": (maintenance_shortfall_table, "maintenance shortfall penalty table"),
        "ECONOMIC_LEVEL_TABLE": (el_table, "Economic Level (EL) table"),
        "SCIENCE_LEVEL_TABLE": (sl_table, "Science Level (SL) table"),
        "CST_TABLE": (cst_table, "Construction (CST) table"),
        "WEP_TABLE": (wep_table, "Weapons (WEP) table"),
        "TER_TABLE": (ter_table, "Terraforming (TER) table"),
        "TER_UPGRADE_COST_TABLE": (ter_upgrade_table, "Terraforming upgrade cost table"),
        "ELI_TABLE": (eli_table, "Electronic Intelligence (ELI) table"),
        "CLK_TABLE": (clk_table, "Cloaking (CLK) table"),
        "SLD_TABLE": (sld_table, "Shield (SLD) table"),
        "CIC_TABLE": (cic_table, "Counter Intelligence (CIC) table"),
        "FD_TABLE": (fd_table, "Fighter Doctrine (FD) table"),
        "ACO_TABLE": (aco_table, "Advanced Carrier Operations (ACO) table"),
    }

    # Replace each table if markers exist
    for marker_name, (table_content, display_name) in markers.items():
        start_marker = f"<!-- {marker_name}_START -->"
        end_marker = f"<!-- {marker_name}_END -->"

        if start_marker in content and end_marker in content:
            start_idx = content.index(start_marker) + len(start_marker)
            end_idx = content.index(end_marker)
            content = content[:start_idx] + "\n" + table_content + "\n" + content[end_idx:]
            print(f"✓ Updated {display_name} in economy.md")
        else:
            print(f"⚠ {display_name} markers not found in economy.md")

    # Write updated content
    spec_file.write_text(content)
    print(f"✓ Successfully updated {spec_file}")


def generate_shield_effectiveness_table(combat_config: Dict[str, Any]) -> str:
    """Generate planetary shield effectiveness table from combat.toml."""
    shields = combat_config.get('planetary_shields', {})

    lines = [
        "| SLD Level | % Chance | 1D20 Roll | % of Hits Blocked |",
        "|:---------:|:--------:|:---------:|:-----------------:|",
    ]

    for level in range(1, 7):  # SLD1-SLD6
        chance = shields.get(f'sld{level}_chance', 0)
        roll = shields.get(f'sld{level}_roll', 0)
        block = shields.get(f'sld{level}_block', 0)

        lines.append(f"| SLD{level}      | {chance}       | > {roll}      | {block}%               |")

    lines.append("")
    lines.append("*Source: config/combat.toml [planetary_shields] section*")

    return "\n".join(lines)


def replace_inline_values(content: str, economy_config: Dict[str, Any], construction_config: Dict[str, Any], military_config: Dict[str, Any], tech_config: Dict[str, Any]) -> str:
    """Replace inline marker values in prose with values from config."""
    import re

    # Define all inline value replacements
    replacements = {
        'PTU_TO_SOULS': lambda: f"{economy_config['population']['ptu_to_souls'] // 1000}k",
        'PU_TO_PTU_CONVERSION': lambda: str(economy_config['population']['pu_to_ptu_conversion']),
        'TAX_WINDOW': lambda: str(economy_config['tax_mechanics']['tax_averaging_window_turns']),
        'NATURAL_GROWTH_RATE': lambda: f"{int(economy_config['population']['natural_growth_rate'] * 100)}%",
        'PTU_GROWTH_RATE': lambda: f"{economy_config['population']['ptu_growth_rate'] * 100:.1f}%",
        'FIGHTER_PU_DIVISOR': lambda: str(military_config['fighter_mechanics']['fighter_capacity_pu_divisor']),
        'STARBASE_PER_FS': lambda: str(military_config['fighter_mechanics']['starbase_per_fighter_squadrons']),
        'CAPACITY_GRACE_PERIOD': lambda: str(military_config['fighter_mechanics']['capacity_violation_grace_period']),
        'STARBASE_REPAIR_COST': lambda: f"{int(construction_config['repair']['starbase_repair_cost_multiplier'] * 100)}%",
        'EMERGENCY_SALVAGE': lambda: f"{int(military_config['salvage']['emergency_salvage_multiplier'] * 100)} %",
        'NORMAL_SALVAGE': lambda: f"{int(military_config['salvage']['salvage_value_multiplier'] * 100)} %",
        'SQUADRON_PU_DIVISOR': lambda: str(military_config['squadron_limits']['squadron_limit_pu_divisor']),
        'SQUADRON_MINIMUM': lambda: str(military_config['squadron_limits']['squadron_limit_minimum']),
        'BREAKTHROUGH_BASE': lambda: f"{int(economy_config['research']['research_breakthrough_base_chance'] * 100)}%",
        'BREAKTHROUGH_RP_PER_PERCENT': lambda: str(economy_config['research']['research_breakthrough_rp_per_percent']),
        'MINOR_BREAKTHROUGH_BONUS': lambda: str(economy_config['research']['minor_breakthrough_bonus']),
        'MODERATE_BREAKTHROUGH_DISCOUNT': lambda: f"{int(economy_config['research']['moderate_breakthrough_discount'] * 100)}%",
        'REV_QUANTUM_BONUS': lambda: f"{int(economy_config['research']['revolutionary_quantum_computing_el_mod_bonus'] * 100)}%",
        'REV_STEALTH_BONUS': lambda: str(economy_config['research']['revolutionary_stealth_detection_bonus']),
        'REV_TERRAFORMING_BONUS': lambda: f"{int(economy_config['research']['revolutionary_terraforming_growth_bonus'] * 100)}%",
        'ERP_BASE_COST': lambda: str(economy_config['research']['erp_base_cost']),
        'EL_EARLY_BASE': lambda: str(economy_config['research']['el_early_base']),
        'EL_EARLY_INCREMENT': lambda: str(economy_config['research']['el_early_increment']),
        'EL_LATE_INCREMENT': lambda: str(economy_config['research']['el_late_increment']),
        'SRP_BASE_COST': lambda: str(economy_config['research']['srp_base_cost']),
        'SRP_SL_MULTIPLIER': lambda: str(economy_config['research']['srp_sl_multiplier']),
        'SL_EARLY_BASE': lambda: str(economy_config['research']['sl_early_base']),
        'SL_EARLY_INCREMENT': lambda: str(economy_config['research']['sl_early_increment']),
        'SL_LATE_INCREMENT': lambda: str(economy_config['research']['sl_late_increment']),
        'TRP_FIRST_LEVEL_COST': lambda: str(economy_config['research']['trp_first_level_cost']),
        'TRP_LEVEL_INCREMENT': lambda: str(economy_config['research']['trp_level_increment']),
        'CST_CAPACITY_INCREASE': lambda: f"{int(construction_config['modifiers']['construction_capacity_increase_per_level'] * 100)}%",
        'WEP_STAT_INCREASE': lambda: f"{int(tech_config['weapons_tech']['weapons_stat_increase_per_level'] * 100)}%",
        'WEP_COST_INCREASE': lambda: f"{int(tech_config['weapons_tech']['weapons_cost_increase_per_level'] * 100)}%",
        'MILITARY_SHIP_TURNS': lambda: "two" if construction_config['construction']['shipyard_turns'] == 2 else str(construction_config['construction']['shipyard_turns']),
        'SPACELIFT_SHIP_TURNS': lambda: "one" if construction_config['construction']['spaceport_turns'] == 1 else str(construction_config['construction']['spaceport_turns']),
        'SHIP_REPAIR_TURNS': lambda: "one" if construction_config['repair']['ship_repair_turns'] == 1 else str(construction_config['repair']['ship_repair_turns']),
        'PLANETSIDE_CONSTRUCTION_PENALTY': lambda: f"{int((construction_config['modifiers']['planetside_construction_cost_multiplier'] - 1) * 100)}%",
        'SHIP_REPAIR_COST': lambda: f"{int(construction_config['repair']['ship_repair_cost_multiplier'] * 100)}%",
        'SHIP_REPAIR_COST_DECIMAL': lambda: str(construction_config['repair']['ship_repair_cost_multiplier']),
    }

    # Replace each inline marker with plain value (removes markers)
    for marker, value_func in replacements.items():
        pattern = f"<!-- {marker} -->.*?<!-- /{marker} -->"
        replacement = value_func()
        content = re.sub(pattern, replacement, content)

    return content


def replace_inline_values_operations(content: str, combat_config: Dict[str, Any], construction_config: Dict[str, Any], military_config: Dict[str, Any]) -> str:
    """Replace inline marker values in operations.md with values from config."""
    import re

    # Define inline value replacements for operations.md
    replacements = {
        'BLOCKADE_PENALTY': lambda: f"{int(combat_config['blockade']['blockade_production_penalty'] * 100)}%",
        'BLOCKADE_PRESTIGE': lambda: str(combat_config['blockade']['blockade_prestige_penalty']),
        'SALVAGE_VALUE': lambda: f"{int(military_config['salvage']['salvage_value_multiplier'] * 100)}%",
        'SHIP_REPAIR_COST': lambda: f"{int(construction_config['repair']['ship_repair_cost_multiplier'] * 100)}%",
        'INVASION_IU_LOSS': lambda: f"{int(combat_config['invasion']['invasion_iu_loss'] * 100)}%",
    }

    # Replace each inline marker with plain value (removes markers)
    for marker, value_func in replacements.items():
        pattern = f"<!-- {marker} -->.*?<!-- /{marker} -->"
        replacement = value_func()
        content = re.sub(pattern, replacement, content)

    return content


def update_operations_spec(shield_table: str, combat_config: Dict[str, Any], construction_config: Dict[str, Any], military_config: Dict[str, Any]):
    """Update docs/specs/operations.md with generated tables and inline values."""
    spec_file = Path("docs/specs/operations.md")

    if not spec_file.exists():
        print(f"⚠ {spec_file} not found, skipping operations.md update")
        return

    content = spec_file.read_text()

    # Replace inline values first
    content = replace_inline_values_operations(content, combat_config, construction_config, military_config)

    # Replace shield effectiveness table
    shield_start = "<!-- SHIELD_EFFECTIVENESS_TABLE_START -->"
    shield_end = "<!-- SHIELD_EFFECTIVENESS_TABLE_END -->"

    if shield_start in content and shield_end in content:
        start_idx = content.index(shield_start) + len(shield_start)
        end_idx = content.index(shield_end)
        content = content[:start_idx] + "\n" + shield_table + "\n" + content[end_idx:]
        print("✓ Updated shield effectiveness table in operations.md")
    else:
        print("⚠ Shield effectiveness table markers not found in operations.md")

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

    economy_config = load_toml(config_dir / "economy.toml")
    print(f"✓ Loaded {config_dir / 'economy.toml'}")

    tech_config = load_toml(config_dir / "tech.toml")
    print(f"✓ Loaded {config_dir / 'tech.toml'}")

    combat_config = load_toml(config_dir / "combat.toml")
    print(f"✓ Loaded {config_dir / 'combat.toml'}")

    construction_config = load_toml(config_dir / "construction.toml")
    print(f"✓ Loaded {config_dir / 'construction.toml'}")

    military_config = load_toml(config_dir / "military.toml")
    print(f"✓ Loaded {config_dir / 'military.toml'}")

    diplomacy_config = load_toml(config_dir / "diplomacy.toml")
    print(f"✓ Loaded {config_dir / 'diplomacy.toml'}")

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

    # Generate economy tables
    raw_table = generate_raw_material_table(economy_config)
    print("✓ Generated RAW material efficiency table (5 qualities × 7 planet classes)")

    tax_penalty_table = generate_tax_penalty_table(prestige_config)
    print("✓ Generated tax penalty table (6 tiers)")

    tax_incentive_table = generate_tax_incentive_table(prestige_config, economy_config)
    print("✓ Generated tax incentive table (5 tiers)")

    iu_table = generate_iu_investment_table(economy_config)
    print("✓ Generated IU investment table (5 tiers)")

    colonization_table = generate_colonization_cost_table(economy_config)
    print("✓ Generated colonization cost table (7 planet classes)")

    maintenance_shortfall_table = generate_maintenance_shortfall_table(prestige_config)
    print("✓ Generated maintenance shortfall penalty table (4 tiers)")

    # Generate tech tables
    el_table = generate_economic_level_table(tech_config)
    print("✓ Generated Economic Level (EL) table (11 levels)")

    sl_table = generate_science_level_table(tech_config)
    print("✓ Generated Science Level (SL) table (8+ levels)")

    cst_table = generate_tech_level_table(tech_config, 'construction_tech')
    print("✓ Generated Construction (CST) table (5+ levels)")

    wep_table = generate_tech_level_table(tech_config, 'weapons_tech')
    print("✓ Generated Weapons (WEP) table (5+ levels)")

    ter_table = generate_tech_level_table(tech_config, 'terraforming_tech', 7)
    print("✓ Generated Terraforming (TER) table (7 levels)")

    ter_upgrade_table = generate_terraforming_upgrade_cost_table(tech_config)
    print("✓ Generated Terraforming upgrade cost table (7 planet classes)")

    eli_table = generate_tech_level_table(tech_config, 'electronic_intelligence')
    print("✓ Generated Electronic Intelligence (ELI) table (5 levels)")

    clk_table = generate_tech_level_table(tech_config, 'cloaking_tech')
    print("✓ Generated Cloaking (CLK) table (5 levels)")

    sld_table = generate_tech_level_table(tech_config, 'shield_tech')
    print("✓ Generated Shield (SLD) table (5 levels)")

    cic_tech_table = generate_tech_level_table(tech_config, 'counter_intelligence_tech')
    print("✓ Generated Counter Intelligence (CIC) table (5 levels)")

    fd_table = generate_fighter_doctrine_table(tech_config)
    print("✓ Generated Fighter Doctrine (FD) table (3 levels)")

    aco_table = generate_aco_table(tech_config)
    print("✓ Generated Advanced Carrier Operations (ACO) table (3 levels)")

    # Generate operations tables
    shield_table = generate_shield_effectiveness_table(combat_config)
    print("✓ Generated shield effectiveness table (6 levels)")

    # Update spec files
    print("\nUpdating specification documents...")
    update_reference_spec(ships_table, ground_table, spacelift_table, prestige_table, morale_table, espionage_table, penalty_table)
    update_diplomacy_spec(espionage_prestige_table, cic_modifier_table, cic_threshold_table, diplomacy_config)
    update_economy_spec(raw_table, tax_penalty_table, tax_incentive_table, iu_table, colonization_table,
                        maintenance_shortfall_table, el_table, sl_table, cst_table, wep_table,
                        ter_table, ter_upgrade_table, eli_table, clk_table, sld_table,
                        cic_tech_table, fd_table, aco_table, economy_config, construction_config, military_config, tech_config)
    update_operations_spec(shield_table, combat_config, construction_config, military_config)

    print("\n" + "=" * 50)
    print("Sync complete!")
    print("\nNext steps:")
    print("1. Review changes in docs/specs/reference.md and docs/specs/economy.md")
    print("2. Commit updated specifications")
    print("3. Ensure all references use enum names, not hardcoded values")


if __name__ == "__main__":
    main()
