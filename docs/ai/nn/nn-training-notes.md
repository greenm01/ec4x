# Neural Network Training Notes: Hybrid GOAP-RBA AI as a Teacher

## 1. Capability of the Current Hybrid GOAP-RBA AI

The current Hybrid GOAP-RBA AI is a **capable and challenging player** with a strong foundation:

*   **Strategic Foresight (GOAP)**: Enables multi-turn planning for complex objectives (invasions, tech rushes, repair capacity). Adaptive replanning based on specific failures (`TechNeeded`, `BudgetFailure`, `CapacityFull`) allows for targeted corrections rather than generic restarts.
*   **Detailed Resource Management (RBA)**: Granular budget allocation by the Treasurer, with a comprehensive feedback loop for advisor reprioritization.
*   **Robust Event-Driven Feedback**: Integration of `GameEvent`s into `checkActualOutcome` allows for accurate learning from real-world consequences in combat, espionage, and diplomacy, while respecting Fog of War.
*   **Opportunistic Play**: `detectNewOpportunities` enables the AI to seize sudden advantages.
*   **Domain Expertise**: Modular advisors provide specialized, rule-based intelligence for various game areas (military, research, espionage, economy, diplomacy, logistics).

Overall, the AI exhibits consistent, logical strategies and adapts to mid-game challenges, making it a decent opponent.

## 2. Suitability for Neural Network Training Data

The Hybrid GOAP-RBA AI is **excellently suited to generate high-quality training data** for a neural network:

*   **Structured Decisions**: Provides clear input-output pairs for NN learning at every level (GOAP goal selection/plan generation, RBA requirement generation/budget allocation/order execution).
    *   **Inputs**: `WorldStateSnapshot`, `IntelligenceSnapshot`, `AIPersonality`, `GameAct`, `TreasurerFeedback`.
    *   **Outputs**: `GOAPlan`, `AdvisorRequirements`, `MultiAdvisorAllocation`, `AIOrderSubmission`.
*   **Explanatory "Labels"**: `RequirementFeedback` (e.g., `unfulfillmentReason`, `suggestion`) and `ReplanReason` provide explicit reasons for action outcomes and replanning triggers. This context is invaluable for an NN to learn *why* certain decisions were made or *why* they failed.
*   **Diverse Scenarios**: Running the RBA/GOAP with various `AIStrategy` profiles and game settings will produce a rich dataset covering many game states and strategic approaches.
*   **Good Baseline "Teacher"**: The RBA/GOAP provides a logical and consistent set of "expert" decisions, offering a strong teacher signal that avoids purely random or highly suboptimal initial NN behaviors.

## 3. Comparison to a Future Neural Network Player

A well-trained neural network player, especially one leveraging deep reinforcement learning, has the potential to be **significantly more capable** than the current RBA/GOAP AI:

### NN Advantages:

*   **Emergent Strategies**: NNs can discover subtle patterns and non-linear relationships, potentially finding novel and superior strategies that are difficult to hardcode.
*   **Adaptability to Complexity**: Better handles high branching factors and complex interactions, which can be challenging for brittle rule-based systems.
*   **Learning from Scale**: Capable of achieving superhuman levels of play with sufficient training data and computational power.
*   **Discovery of Unimplemented Features**: NNs can implicitly figure out how to utilize game features or mechanics that are not explicitly coded or fully optimized by the RBA/GOAP (e.g., optimal repair timings, dynamic drydock usage, implicit cost-benefit analysis of repair actions). It learns effective sequences of actions through observation, action, and reward signals.
*   **Real-time Responsiveness**: Once trained, decision-making can be very fast.

### NN Disadvantages (relative to RBA/GOAP):

*   **Explainability (Black Box)**: Decisions are often opaque, hindering debugging, balancing, and iterative design.
*   **Goal Setting**: Pure NNs often struggle with explicit, long-term goal setting and planning in dynamic, non-deterministic environments.
*   **Data Hunger**: Requires massive amounts of high-quality training data.
*   **Initial Performance**: Raw NNs perform poorly without extensive training.

### Future Outlook: Hybrid NN-GOAP-RBA

The most capable AI would likely integrate an NN within the existing hybrid GOAP-RBA framework:

*   **NN as Tactical Advisor**: Replace complex RBA heuristics with learned policies for specific tactical decisions (e.g., optimal fleet composition, economic investment choices, espionage target selection).
*   **NN Enhancing GOAP**: Improve GOAP's heuristic evaluation function for better plan quality or faster search.
*   **GOAP/RBA as Strategic Scaffolding**: Continue to provide explicit goal setting, multi-turn planning, and explainable high-level strategy, while the NN fills in the tactical "intuition" and complex pattern recognition.

The current RBA/GOAP is an excellent foundation for both playing the game effectively and serving as a robust teacher for future neural network development.
