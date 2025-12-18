# EC4X Strategic AI Guide: Intelligence and Campaign Operations

## Act 1: Expansion Phase
*Objective: Secure territory and map the strategic landscape*

### Eparch (Colonization)
- **Primary mission:** Colonize all nearby habitable worlds within immediate reach of homeworld
- **Decision model:** Speed over caution - send etacs immediately to grab territory before rivals
- **Colony priorities:** 
  1. Eden and Rich worlds closest to homeworld
  2. Habitable worlds in defensible clusters
  3. Forward positions that block rival expansion routes
- **Espionage:** Minimal to none unless rival colonies appear in your planned expansion zone

### Drungarius (Exploration)
- **Primary mission:** Scout outward in expanding rings from homeworld
- **Survey priorities:**
  1. Systems adjacent to your colonies (immediate threat detection)
  2. Unexplored systems between your space and likely rival positions
  3. Deep space exploration to find long-term expansion targets
- **Intelligence output:** Build comprehensive database of system ownership, planet types, and rival positions
- **Scout preservation:** Scouts are valuable - avoid hostile systems until you have military escorts

### Domestikos (Military Operations)
- **Primary mission:** Execute immediate tactical operations as directed by GOAP
- **Fleet positioning:** Station defensive fleets at key colonies, especially border worlds
- **Reconnaissance:** Use cheap destroyers/corvettes to "View a World" on adjacent systems
  - Reveals ownership and planet class
  - Minimal cost, provides situational awareness
  - Creates early warning network around your territory
- **Combat doctrine:** ROE 4 (defensive only) - engage only when attacked
- **Encounter intelligence:** Every fleet contact builds your database on rival naval strength
- **Tactical horizon:** Operates on immediate opportunities within a few turns, no long-term campaign planning

### Act 1 Success Metrics
By end of Act 1, you should have:
- Initial colonial cluster established around homeworld
- Complete map of local strategic neighborhood
- Basic intelligence on all nearby rival empires (location, rough colony count)
- No major military commitments or losses

---

## Act 2: Competition Phase
*Objective: Gather actionable intelligence and begin strategic campaigns*

### Eparch (Strategic Intelligence)
- **Primary mission:** Target espionage against rival colonies in contested zones
- **Spy priorities:**
  1. Border colonies that threaten your expansion
  2. Rival homeworlds (assess overall threat level)
  3. Wealthy colonies worth conquering
  4. Systems where Domestikos is planning operations
- **Espionage timing:** Begin spying well before planned military action to allow intelligence gathering
- **Secondary mission:** Continue colonization in safe rear areas

### Drungarius (Targeted Reconnaissance)
- **Primary mission:** Detailed surveys of high-value rival systems
- **Scout priorities:**
  1. Systems flagged by Domestikos for campaign planning
  2. Rival clusters to assess colony density and defenses
  3. Unexplored strategic corridors and chokepoints
  4. Periodic re-surveys of previously scouted rival systems (situations change)
- **Coordination:** Work from Domestikos target list - scout what the military needs to know
- **Risk management:** Use military escorts when scouting deep in rival territory

### Domestikos (Tactical Execution)
- **Primary mission:** Execute tactical military orders as directed by GOAP strategic planner

- **Intelligence Collection Operations:**
  - Basic reconnaissance: "View a World" on adjacent systems (ongoing)
  - Probe operations: Send expendable fleets to test defenses when ordered
  - Patrol operations: Challenge rival fleets in contested systems when ordered
  - ROE 1-2 for probes: Engage inferior forces, retreat from equal/superior
  - Accept losses during intelligence gathering - trading ships for information
  
- **Combat Operations:**
  - Execute fleet movements and positioning as ordered
  - Engage enemy fleets according to assigned ROE
  - ROE 2-3 for patrols: Engage equal forces, retreat only from clearly superior fleets
  - ROE 4 for defensive fleets: Engage only when attacked
  
- **Tactical Assessment:**
  - Evaluate immediate combat opportunities (enemy fleet in range, local superiority)
  - Execute opportunistic strikes within a few turns if advantage is clear
  - Report combat results and fleet status back to strategic layer
  
- **No Strategic Planning:** Domestikos does not plan multi-turn campaigns, coordinate with other advisors, or make strategic decisions about which systems to target

### Minimum Intelligence Requirements for Campaigns

**For Opportunistic Raids:**
- System basic intel (ownership + planet class) from Domestikos recon
- Local fleet superiority confirmed by scout or patrol
- *Use case:* Quick strikes against weak border colonies

**For Calculated Assaults:**
- System basic intel from Domestikos recon
- Colony defense estimate from Eparch espionage OR combat probe results
- Rival fleet strength estimated from patrol encounters
- *Use case:* Standard conquest operations against established colonies

**For Deliberate Campaigns:**
- Detailed system intel from Drungarius scouts
- Complete colony intelligence from Eparch espionage (multiple spy reports)
- Fleet composition and strength confirmed through multiple combat probes
- Neighboring rival systems surveyed (reinforcement routes)
- *Use case:* Assaults on fortified strongpoints or rival homeworlds

---

## GOAP Campaign Planning

GOAP is the strategic planner - it coordinates all advisors and plans multi-turn campaigns. Once minimum intelligence exists for a target, GOAP evaluates conquest campaigns against other strategic goals.

**Example: GOAP plans "Conquer Colony in System X"**

*Given intelligence in world state:*
- System X basic intel = true (from Domestikos recon)
- Colony X defenses known = true (from Eparch espionage)
- Fleet strength estimated = true (from probe combat results)

*GOAP uses A* to generate optimal action sequence:*
1. Order Domestikos: Mass Fleet Alpha at staging system
2. Order Domestikos: Move Fleet Alpha to System X
3. Order Domestikos: Patrol System X (executes until space control achieved)
4. Order Domestikos: Blockade Colony X (executes for sustained period)
5. Order Domestikos: Bombard Colony X (weakens defenses)
6. Order Domestikos: Invade Colony X (conquest)

*GOAP evaluation:*
- Calculates total cost (fleet commitment, time, probable losses)
- Compares against alternative goals (colonize safer systems, build economy, research)
- Factors in intelligence quality (stale intel = higher risk cost)
- Chooses highest-value goal given current world state

**All multi-turn coordination is GOAP's responsibility:**
- Timing intelligence gathering before military operations
- Coordinating Drungarius scouts with Domestikos probe fleets
- Sequencing Eparch espionage to support upcoming campaigns
- Deciding when to commit to conquest vs continuing expansion

**Advisors are tactical executors:**
- Receive individual orders from GOAP
- Execute within their domain (Eparch: colonies/spies, Drungarius: scouts, Domestikos: fleets)
- Report results back to GOAP (updates world state)
- May exploit immediate tactical opportunities (few turns), but don't plan campaigns

---

## Intelligence Degradation

Intelligence has a shelf life:
- **System ownership:** Decays slowly, re-check periodically
- **Colony defenses:** Decays at medium speed as colonies develop
- **Fleet positions:** Decays rapidly, patrol intel becomes stale quickly
- **Combat strength:** Decays as fleets are reinforced/damaged, re-probe if data is old

GOAP should factor intelligence age into campaign planning. Stale intelligence increases risk costs.

---

## Act Transition Triggers

**Act 1 → Act 2 Transition:**
- Initial colonial cluster established
- Multiple rival empires discovered
- Basic reconnaissance complete around your borders
- First rival colony border contact established

**Act 2 → Act 3 Transition:**
- Substantial colonial presence established
- Intelligence networks operational against all major rivals
- First successful conquest campaign completed
- Multiple simultaneous military operations feasible

---

## Advisor Coordination Principles

**GOAP coordinates all advisors:**
- Advisors do not coordinate directly with each other
- All strategic coordination flows through GOAP's A* planning
- GOAP orders advisors as part of multi-action campaign plans

**Intelligence flows into shared world state:**
- Domestikos recon updates system ownership and planet class data
- Drungarius surveys update detailed system intelligence
- Eparch espionage updates colony defense and garrison data
- Combat encounters update fleet strength estimates
- All advisors read from this unified world state when executing orders

**GOAP uses intelligence to plan:**
- When planning "Conquer System X", GOAP checks world state for required intelligence
- If intelligence missing, GOAP generates prerequisite actions:
  - Order Drungarius: Scout System X
  - Order Eparch: Spy Colony X
  - Order Domestikos: Probe System X defenses
- Once intelligence threshold met, GOAP proceeds with conquest action sequence

**Advisors execute, don't plan:**
- Eparch receives order: "Spy on Colony X" - executes spy mission, reports results
- Drungarius receives order: "Scout System X" - executes survey, reports results
- Domestikos receives order: "Patrol System X" - executes patrol, engages per ROE, reports combat results
- None of them decide *why* they're doing this or what comes next - that's GOAP's job