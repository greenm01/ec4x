## Event Factory - Main Module
## Re-exports all event factory sub-modules
##
## DRY Principle: Single import point for all event creation functions
## DoD Principle: Data (GameEvent) separated from creation logic (factories)
##
## Usage:
##   import resolution/event_factory
##   events.add(event_factory.shipCommissioned(houseId, shipClass, systemId))

import commissioning
import military
import economic
import orders
import intelligence
import victory
import prestige
import diplomatic
import alerts
import fleet_ops

export commissioning
export military
export economic
export orders
export intelligence
export victory
export prestige
export diplomatic
export alerts
export fleet_ops
