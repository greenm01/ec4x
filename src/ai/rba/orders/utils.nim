## Orders Utility Functions
##
## Shared utility functions used across order generation phases

import std/[strformat, options]
import ../../../engine/[gamestate, fog_of_war, logger, orders]
import ../../../engine/economy/construction

proc calculateProjectedTreasury*(filtered: FilteredGameState): int =
  ## Calculate projected treasury for AI planning
  ## Treasury projection = current + expected income - expected maintenance
  ##
  ## CRITICAL: AI generates orders BEFORE income/maintenance phase in turn resolution
  ## But build orders are processed AFTER income is added. Without projection,
  ## AI sees treasury=2 PP, makes no builds, then economy has 52 PP available.
  let currentTreasury = filtered.ownHouse.treasury

  # Calculate expected income from all owned colonies
  var expectedIncome = 0
  for colony in filtered.ownColonies:
    # Income = GCO × tax rate
    # GCO (Gross Colonial Output) is the total economic output
    expectedIncome += (colony.grossOutput * filtered.ownHouse.taxPolicy.currentRate) div 100

  # Calculate expected maintenance from fleets
  var expectedMaintenance = 0
  for fleet in filtered.ownFleets:
    # Each fleet costs ~2 PP maintenance (simplified)
    expectedMaintenance += 2

  result = currentTreasury + expectedIncome - expectedMaintenance
  result = max(result, 0)  # Can't go negative

  logDebug(LogCategory.lcAI,
           &"{filtered.viewingHouse} Projected treasury: current={currentTreasury}PP, " &
           &"income≈{expectedIncome}PP, maintenance≈{expectedMaintenance}PP, " &
           &"projected={result}PP")

proc calculateTotalCost*(buildOrders: seq[BuildOrder]): int =
  ## Calculate total PP cost of all build orders
  result = 0
  for order in buildOrders:
    case order.buildType
    of BuildType.Ship:
      if order.shipClass.isSome:
        result += getShipConstructionCost(order.shipClass.get()) * order.quantity
    of BuildType.Building:
      # Building costs vary by type, skip for now as we don't have cost lookup
      discard
    of BuildType.Infrastructure:
      # Infrastructure costs are handled separately, skip for now
      discard
