## RBA Player Interface
##
## Public API for Rule-Based Advisor AI player
##
## Byzantine Imperial Government Architecture
## ==========================================
##
## The RBA AI is modeled after the Byzantine Imperial Government, with seven specialized
## advisors reporting to the Basileus (emperor). Each advisor has a specific domain of
## responsibility and generates requirements that compete for limited resources.
##
## Advisors and Their Roles
## -------------------------
##
## **Basileus** (Emperor - Chief Mediator)
##   Role: Mediates conflicting requirements from all advisors and allocates budgets
##   Decides: Which advisor requests get funded based on strategic priorities and personality
##   Phase: Phase 2 (Mediation & Allocation)
##
## **Domestikos** (Admiral - Military Commander)
##   Role: Naval/fleet operations, defense, and military construction
##   Manages: Fleet positioning, ship construction, defensive strategies, invasion planning
##   Requests: Warships, starbases, ground armies, planetary shields
##   Phase: Phase 1 (Requirement Generation), Phase 3 (Execution)
##
## **Drungarius** (Spymaster - Intelligence Director)
##   Role: Espionage, counter-intelligence, and covert operations
##   Manages: Spy networks, reconnaissance, sabotage, intelligence gathering
##   Requests: Espionage missions, counter-intel sweeps, intelligence budgets
##   Phase: Phase 0 (Intelligence Distribution), Phase 1 (Requirements), Phase 3 (Execution)
##
## **Eparch** (Governor - Economic Administrator)
##   Role: Colony management, terraforming, and economic development
##   Manages: Infrastructure upgrades, terraforming projects, population growth
##   Requests: Terraforming, infrastructure improvements, economic facilities
##   Phase: Phase 1 (Requirement Generation), Phase 3 (Execution)
##
## **Logothete** (Logothetes tou dromou - Technology Minister)
##   Role: Research and technological advancement
##   Manages: Tech research priorities, research allocation
##   Requests: Research funding for EL, SL, CST advancement
##   Phase: Phase 1 (Requirement Generation), Phase 3 (Execution)
##
## **Protostrator** (Diplomat - Foreign Relations)
##   Role: Diplomatic relations, alliances, and treaty management
##   Manages: War declarations, peace treaties, diplomatic pacts
##   Requests: Diplomatic actions, relationship management
##   Phase: Phase 1 (Requirement Generation), Phase 3 (Execution)
##
## **Treasurer** (Sakellarios - Budget Coordinator)
##   Role: Budget allocation and multi-advisor resource coordination
##   Manages: PP (Production Points) distribution across all advisors
##   Executes: Basileus decisions, ensures advisors stay within allocated budgets
##   Phase: Phase 2 (Budget Allocation), Phase 3 (Execution Coordination)
##
## Turn Execution Flow
## -------------------
## Phase 0: Drungarius distributes intelligence reports to all advisors
## Phase 1: All advisors generate requirements (build, research, espionage, etc.)
## Phase 2: Basileus mediates conflicts, Treasurer allocates budgets
## Phase 3: Advisors execute their allocated requirements (builds, orders, research)
## Phase 4: Feedback loop - unfulfilled requirements are reprioritized

import ../common/types
import ./[controller, controller_types, intelligence, diplomacy, tactical, strategic, budget, espionage, economic, logistics, orders]
export controller, controller_types, types
export intelligence, diplomacy, tactical, strategic, budget, espionage, economic, logistics, orders

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
