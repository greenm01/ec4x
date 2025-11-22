#!/usr/bin/env python3
"""
Prepare EC4X training data for LLM fine-tuning.

Converts the generated training dataset into prompt-completion pairs
suitable for instruction-tuning Mistral-7B.
"""

import json
from pathlib import Path
from typing import Dict, List, Any
from dataclasses import dataclass


@dataclass
class TrainingExample:
    """Single training example with prompt and completion."""
    prompt: str
    completion: str
    metadata: Dict[str, Any]


def format_tech_levels(tech: Dict[str, int]) -> str:
    """Format tech levels for display."""
    levels = []
    if "energy" in tech:
        levels.append(f"EL{tech['energy']}")
    if "shields" in tech:
        levels.append(f"SL{tech['shields']}")
    if "weapons" in tech:
        levels.append(f"WL{tech['weapons']}")
    if "engines" in tech:
        levels.append(f"ML{tech['engines']}")
    return ", ".join(levels)


def format_colonies(colonies: List[Dict]) -> str:
    """Format colony list for display."""
    if not colonies:
        return "  (No colonies)"

    lines = []
    for colony in colonies:
        system_id = colony.get("system_id", "Unknown")
        infra = colony.get("infrastructure", 0)
        prod = colony.get("production", 0)
        ptu = colony.get("population", 0)
        lines.append(f"  - {system_id}: {infra} infrastructure, {prod} PP/turn, {ptu} PTU")

    return "\n".join(lines)


def format_fleets(fleets: List[Dict]) -> str:
    """Format fleet list for display."""
    if not fleets:
        return "  (No fleets)"

    lines = []
    for fleet in fleets:
        fleet_id = fleet.get("fleet_id", "Unknown")
        location = fleet.get("location", "Unknown")
        squadrons = fleet.get("squadrons", [])

        # Count ships by type
        ship_counts = {}
        for squadron in squadrons:
            ship_type = squadron.get("ship_type", "Unknown")
            count = squadron.get("ship_count", 0)
            ship_counts[ship_type] = ship_counts.get(ship_type, 0) + count

        ships_str = ", ".join(f"{count} {stype}" for stype, count in ship_counts.items())
        lines.append(f"  - {fleet_id} @ {location}: {ships_str}")

    return "\n".join(lines)


def format_diplomacy(relations: Dict[str, str]) -> str:
    """Format diplomatic relations for display."""
    if not relations:
        return "  (No relations)"

    lines = []
    for house, status in relations.items():
        lines.append(f"  - {house}: {status}")

    return "\n".join(lines)


def format_intel(intel: Dict) -> str:
    """Format intelligence reports for display."""
    lines = []

    enemy_fleets = intel.get("enemy_fleets_spotted", [])
    if enemy_fleets:
        lines.append("  Enemy Forces Detected:")
        for sighting in enemy_fleets:
            location = sighting.get("location", "Unknown")
            owner = sighting.get("owner", "Unknown")
            strength = sighting.get("estimated_strength", "Unknown")
            lines.append(f"    - {owner} fleet @ {location} (strength: {strength})")

    uncolonized = intel.get("uncolonized_systems", [])
    if uncolonized:
        lines.append(f"  Uncolonized Systems: {', '.join(uncolonized[:5])}")
        if len(uncolonized) > 5:
            lines.append(f"    (and {len(uncolonized) - 5} more)")

    if not lines:
        return "  (No significant intelligence)"

    return "\n".join(lines)


def format_orders_as_json(decision: Dict) -> str:
    """Format AI decision as JSON orders."""
    orders = {
        "reasoning": decision.get("reasoning", "Strategic decision"),
    }

    if "fleet_orders" in decision:
        orders["fleet_orders"] = decision["fleet_orders"]

    if "build_orders" in decision:
        orders["build_orders"] = decision["build_orders"]

    if "research_allocation" in decision:
        orders["research_allocation"] = decision["research_allocation"]

    if "diplomatic_actions" in decision:
        orders["diplomatic_actions"] = decision["diplomatic_actions"]

    return json.dumps(orders, indent=2)


def create_prompt(example: Dict) -> str:
    """Create instruction prompt from training example."""
    game_state = example.get("game_state", {})
    turn = game_state.get("turn", 0)
    house = example.get("house", "Unknown")

    # Extract game state information
    treasury = game_state.get("treasury", 0)
    prestige = game_state.get("prestige", 0)
    tech = game_state.get("tech_levels", {})
    colonies = game_state.get("colonies", [])
    fleets = game_state.get("fleets", [])
    relations = game_state.get("diplomatic_relations", {})
    intel = game_state.get("intelligence", {})

    prompt = f"""<s>[INST] You are a strategic advisor for {house} in EC4X, a turn-based 4X space strategy game.

## Current Situation (Turn {turn})
Treasury: {treasury} PP (Production Points)
Prestige: {prestige}
Tech Levels: {format_tech_levels(tech)}

## Your Colonies
{format_colonies(colonies)}

## Your Fleets
{format_fleets(fleets)}

## Diplomatic Relations
{format_diplomacy(relations)}

## Intelligence Reports
{format_intel(intel)}

Provide your strategic analysis and orders in JSON format. [/INST]

"""
    return prompt


def create_completion(example: Dict) -> str:
    """Create expected completion from expert decision."""
    expert_decision = example.get("expert_decision", {})

    completion = format_orders_as_json(expert_decision)
    completion += "</s>"

    return completion


def process_training_dataset(input_file: Path, output_file: Path):
    """Process combined training dataset into prompt-completion pairs."""
    print(f"Loading training data from: {input_file}")

    with open(input_file) as f:
        data = json.load(f)

    examples_raw = data.get("examples", [])
    print(f"Found {len(examples_raw)} raw examples")

    # Convert to training format
    training_examples = []
    skipped = 0

    for i, example in enumerate(examples_raw):
        try:
            prompt = create_prompt(example)
            completion = create_completion(example)

            training_example = {
                "text": prompt + completion,  # Combined for causal LM training
                "prompt": prompt,
                "completion": completion,
                "metadata": {
                    "game_id": example.get("game_id"),
                    "turn": example.get("game_state", {}).get("turn"),
                    "house": example.get("house"),
                    "strategy": example.get("strategy")
                }
            }

            training_examples.append(training_example)

        except Exception as e:
            print(f"Warning: Skipped example {i}: {e}")
            skipped += 1
            continue

    print(f"✓ Processed {len(training_examples)} training examples")
    if skipped > 0:
        print(f"  Skipped {skipped} examples due to errors")

    # Save processed dataset
    output_data = {
        "metadata": {
            "source": str(input_file),
            "num_examples": len(training_examples),
            "format": "mistral_instruct",
            **data.get("metadata", {})
        },
        "examples": training_examples
    }

    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    file_size_mb = output_file.stat().st_size / (1024 * 1024)
    print(f"✓ Saved processed dataset to: {output_file}")
    print(f"  File size: {file_size_mb:.1f} MB")

    # Calculate statistics
    avg_prompt_len = sum(len(ex["prompt"]) for ex in training_examples) / len(training_examples)
    avg_completion_len = sum(len(ex["completion"]) for ex in training_examples) / len(training_examples)
    avg_total_len = sum(len(ex["text"]) for ex in training_examples) / len(training_examples)

    print(f"\nDataset Statistics:")
    print(f"  Average prompt length: {avg_prompt_len:.0f} chars")
    print(f"  Average completion length: {avg_completion_len:.0f} chars")
    print(f"  Average total length: {avg_total_len:.0f} chars")
    print(f"  Estimated tokens: ~{avg_total_len / 4:.0f} tokens per example")


def main():
    """Main entry point."""
    print("=" * 70)
    print("EC4X Training Data Preparation")
    print("=" * 70)
    print()

    # Paths
    input_file = Path("training_data/training_dataset_combined.json")
    output_file = Path("training_data/training_dataset_processed.json")

    if not input_file.exists():
        print(f"ERROR: Input file not found: {input_file}")
        print("Run generate_parallel.py first to create training data.")
        return 1

    # Process dataset
    process_training_dataset(input_file, output_file)

    print()
    print("=" * 70)
    print("✓ Data preparation complete!")
    print("=" * 70)
    print()
    print("Next step: Run train_model.py to fine-tune Mistral-7B")
    print()

    return 0


if __name__ == "__main__":
    exit(main())
