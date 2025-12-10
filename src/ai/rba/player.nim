## RBA Player Interface
##
## Public API for Rule-Based Advisor AI player

import ../common/types
import ./[controller, controller_types, intelligence, tactical, strategic, budget, logistics, orders]
import ./[basileus, domestikos, drungarius, eparch, logothete, protostrator, treasurer]
import ./goap/core/types as goap_types # For GOAPlan
import ./goap/integration/[plan_tracking, replanning] # For PlanTracker, newPlanTracker, ReplanReason
import ./config # For GOAPConfig (now globalRBAConfig.goap)

export controller, controller_types, types
export intelligence, tactical, strategic, budget, logistics, orders
export basileus, domestikos, drungarius, eparch, logothete, protostrator, treasurer

# Re-export key types and functions for easy access
export AIController, AIStrategy, AIPersonality, AIOrderSubmission
export goap_types.GOAPlan # Export GOAPlan type
export plan_tracking.PlanTracker, plan_tracking.newPlanTracker # Export PlanTracker and its constructor
export replanning.ReplanReason # Export ReplanReason enum for feedback loops
export newAIController, newAIControllerWithPersonality
export getStrategyPersonality, getCurrentGameAct
export generateAIOrders

## This module provides the main entry point for using the RBA AI.
##
## Usage:
##   import ai/rba/player
##   let ai = newAIController(houseId, AIStrategy.Aggressive)
##   let orders = generateAIOrders(ai, filteredState, rng)

# Basileus = Emperor
# Protostrator = Diplomacy
# Logothete = Science & Technology
# Eparch = Economics
# Domestikos = War
# Drungarius = Intelligence & Clandestine Operations

# Basileus (Βασιλεύς) - The Emperor coordinating all advisors
# - Personality-driven advisor weighting
# - Multi-advisor coordination frameworks
# - Full feedback loop
# - Intelligence distribution

# Protostrator (πρωτοστράτωρ) - Master of ceremonies managing foreign relations
# - Diplomatic relationship assessment
# - Alliance/pact recommendations
# - War/peace evaluations
# - Foreign policy strategy

# Logothete (λογοθέτης) - Controller of technological secrets
# - Research budget allocation (ERP/SRP/TRP)
# - Tech cap detection and reallocation
# - Personality-driven research priorities

# Eparch (ἔπαρχος) - Prefect controlling markets and infrastructure
# - Terraforming strategy (planetary development)
# - Facility construction (shipyards, spaceports)
# - Economic policy (taxation, trade)

# Domestikos (δομέστικος) - Commander of Imperial Forces
# - Fleet utilization analysis
# - Act-specific fleet reorganization (split in Act 1, merge in Act 2+)
# - Smart defensive consolidation (no suicide attacks)
# - Opportunistic counter-attacks against vulnerable enemies
# - Probing attacks for intelligence gathering

# Drungarius (δρουγγάριος) - Commander of intelligence networks
# - Strategic espionage target selection
# - Operation type selection (based on EBP budget)
# - Counter-intelligence decisions (CIP usage)
