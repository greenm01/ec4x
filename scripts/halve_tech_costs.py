#!/usr/bin/env python3
"""
Halve all tech research costs for 30-turn acceleration
Processes level_X_erp, level_X_srp, level_X_cost, level_X_trp values
"""

import re

with open('config/tech.toml', 'r') as f:
    content = f.read()

# Add acceleration comment at top
if 'ACCELERATION' not in content:
    content = content.replace(
        '# Edit this file to change tech costs',
        '# Edit this file to change tech costs\n# ACCELERATION: All research costs halved for 30-turn multi-generational timeline'
    )

# Pattern to match: level_X_erp = 50 or level_X_srp = 25, etc.
def halve_cost(match):
    prefix = match.group(1)
    value = int(match.group(2))
    new_value = value // 2
    return f"{prefix} = {new_value}"

# Halve all _erp, _srp, _trp, and _cost values
content = re.sub(r'(level_\d+_[est]rp)\s*=\s*(\d+)', halve_cost, content)
content = re.sub(r'(level_\d+_cost)\s*=\s*(\d+)', halve_cost, content)

# Also handle non-level costs
content = re.sub(r'(_cost\s*=\s*)(\d+)', lambda m: f"{m.group(1)}{int(m.group(2)) // 2}", content)

with open('config/tech.toml', 'w') as f:
    f.write(content)

print("✓ Tech costs halved in config/tech.toml")
