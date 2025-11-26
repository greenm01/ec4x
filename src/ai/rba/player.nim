## RBA Player Interface
##
## Public API for Rule-Based Advisor AI player

import ../common/types
import ./[controller, controller_types, intelligence, diplomacy, tactical, strategic, budget, espionage, economic, orders]
export controller, controller_types, types
export intelligence, diplomacy, tactical, strategic, budget, espionage, economic, orders

# Re-export key types and functions for easy access
export AIController, AIStrategy, AIPersonality
export newAIController, newAIControllerWithPersonality
export getStrategyPersonality, getCurrentGameAct
export generateAIOrders

## This module provides the main entry point for using the RBA AI.
##
## Usage:
##   import ai/rba/player
##   let ai = newAIController(houseId, AIStrategy.Aggressive)
##   let orders = generateAIOrders(ai, filteredState, rng)
