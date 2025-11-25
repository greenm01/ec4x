#!/usr/bin/env python3
"""
Refactor ai_controller.nim to use FilteredGameState everywhere.
This enforces fog-of-war at the type level.
"""

import re
import sys

def refactor_ai_controller(input_file, output_file):
    with open(input_file, 'r') as f:
        content = f.read()

    # Phase 1: Update imports
    content = re.sub(
        r'import std/\[tables, options, random, sequtils, strformat, algorithm\]\n'
        r'import \.\./\.\./src/engine/\[gamestate, orders, fleet, squadron, starmap, fog_of_war\]\n'
        r'import \.\./\.\./src/common/types/\[core, units, tech, planets\]\n'
        r'import \.\./\.\./src/engine/espionage/types as esp_types\n'
        r'import \.\./\.\./src/engine/research/types as res_types\n'
        r'import \.\./\.\./src/engine/diplomacy/types as dip_types\n'
        r'import \.\./\.\./src/engine/diplomacy/proposals as dip_proposals\n'
        r'import \.\./\.\./src/engine/economy/construction\n',
        'import std/[tables, options, random, sequtils, strformat, algorithm]\n'
        'import ../../src/engine/[orders, fleet, squadron, starmap, fog_of_war]\n'
        'import ../../src/common/types/[core, units, tech, planets]\n'
        'import ../../src/engine/espionage/types as esp_types\n'
        'import ../../src/engine/research/types as res_types\n'
        'import ../../src/engine/diplomacy/types as dip_types\n'
        'import ../../src/engine/diplomacy/proposals as dip_proposals\n'
        'import ../../src/engine/economy/construction\n'
        'import ai_modules/types\n\n'
        'export types\n',
        content
    )

    # Phase 2: Remove type definitions (already in ai_modules/types.nim)
    # Find the type section and remove it
    type_section_start = content.find('# Export FallbackRoute')
    type_section_end = content.find('# =============================================================================\n# Strategy Profiles')
    if type_section_start != -1 and type_section_end != -1:
        content = content[:type_section_start] + content[type_section_end:]

    # Also remove strategy profile functions (moved to types.nim)
    strategy_start = content.find('# =============================================================================\n# Strategy Profiles')
    strategy_end = content.find('# =============================================================================\n# Helper Functions')
    if strategy_start != -1 and strategy_end != -1:
        content = content[:strategy_start] + content[strategy_end:]

    # Phase 3: Change all function signatures from GameState to FilteredGameState
    content = re.sub(
        r'\bstate: GameState\b',
        'filtered: FilteredGameState',
        content
    )
    content = re.sub(
        r'\bstate: var GameState\b',
        'filtered: var FilteredGameState',
        content
    )

    # Phase 4: Update data access patterns
    # state.houses[controller.houseId] → filtered.ownHouse
    content = re.sub(
        r'\bstate\.houses\[controller\.houseId\]',
        'filtered.ownHouse',
        content
    )
    content = re.sub(
        r'\bstate\.houses\[houseId\]',
        'filtered.ownHouse',
        content
    )

    # state.turn → filtered.turn
    content = re.sub(r'\bstate\.turn\b', 'filtered.turn', content)
    content = re.sub(r'\bstate\.year\b', 'filtered.year', content)
    content = re.sub(r'\bstate\.month\b', 'filtered.month', content)

    # state.starMap → filtered.starMap
    content = re.sub(r'\bstate\.starMap\b', 'filtered.starMap', content)

    # Phase 5: Remove TEMPORARY BRIDGE section
    bridge_start = content.find('  # TEMPORARY BRIDGE: Create compatibility GameState structure')
    bridge_end = content.find('  # Strategic planning before generating orders')
    if bridge_start != -1 and bridge_end != -1:
        # Keep the strategic planning comment
        content = content[:bridge_start] + '  ' + content[bridge_end:]

    # Phase 6: Fix variable names in remaining code
    # Change 'state' variable name to 'filtered' in function bodies
    # This is tricky - only in function bodies, not in comments

    with open(output_file, 'w') as f:
        f.write(content)

    print(f"Refactored {input_file} → {output_file}")
    print("Manual fixes still needed:")
    print("1. Update colony/fleet iteration patterns")
    print("2. Fix helper function calls")
    print("3. Review all uses of state.colonies/state.fleets")
    print("4. Test compilation")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: refactor_ai.py input.nim output.nim")
        sys.exit(1)

    refactor_ai_controller(sys.argv[1], sys.argv[2])
