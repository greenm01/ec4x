## Basileus Module - Supreme Imperial Coordinator
##
## Byzantine Basileus (Βασιλεύς) - The Emperor coordinating all advisors
##
## **Phase 6 Implementation Status:**
## - Personality-driven advisor weighting: ✅ Implemented
## - Multi-advisor coordination framework: ✅ Implemented
## - Full feedback loop: ✅ Implemented
## - Intelligence distribution: ✅ Integrated (Drungarius hub)
##
## **Current Architecture:**
## 1. Drungarius generates IntelligenceSnapshot for all advisors
## 2. All 6 advisors generate requirements independently
## 3. Basileus mediates competing priorities using personality weights
## 4. Treasurer allocates budget based on mediated priorities
## 5. Multi-advisor feedback loop iterates until convergence (max 3 iterations)

import std/tables
import ../../common/types/core
import ../common/types as ai_types
import ./controller_types
import ./basileus/personality
import ./basileus/mediation

# Re-export personality and mediation modules
export personality
export mediation
