## Event Factory - Main Module
## Re-exports all event factory sub-modules
##
## DRY Principle: Single import point for all event creation functions
## DoD Principle: Data (GameEvent) separated from creation logic (factories)
##
## Usage:
##   import resolution/event_factory
##   events.add(shipCommissioned(houseId, shipClass, systemId))

import
  commissioning, military, economic, intel, victory, prestige, diplomatic,
  alerts, fleet_ops, commands

export
  commissioning, military, economic, intel, victory, prestige, diplomatic,
  alerts, fleet_ops, commands
