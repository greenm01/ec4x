## Prestige System - Main Module
##
## Re-exports all prestige subsystem modules for convenient importing.
##
## Victory point tracking and prestige modifiers per gameplay.md:1.1 and reference.md:9.4
##
## Prestige represents House dominance and is the victory condition
## Victory: First to 5000 prestige OR last house standing
##
## Prestige sources:
## - Military victories (combat, eliminations)
## - Economic prosperity (low taxes, colonies)
## - Technological advancement
## - Diplomatic actions
##
## Prestige penalties:
## - High taxes (rolling average > 50%)
## - Blockaded colonies
## - Maintenance shortfalls
## - Military defeats

import
  prestige/[types, sources, events, combat, economic, advancement, effects, application]

export types, sources, events, combat, economic, advancement, effects, application
