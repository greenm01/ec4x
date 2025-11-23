# Diplomatic Proposal System (Multiplayer)

**Status:** Design Phase (Not Yet Implemented)
**Related:** diplomacy.md:8.1.2, gameplay.md:1.3.3
**Last Updated:** 2025-11-22

## Overview

The current diplomacy system auto-accepts Non-Aggression Pacts for AI/offline gameplay. For asynchronous multiplayer (human players), we need a proposal/response system where the target player can accept or reject diplomatic offers.

## Current Implementation (AI/Offline)

**Auto-Accept Behavior:**
```nim
# resolve.nim:505-527
of DiplomaticActionType.ProposeNonAggressionPact:
  # For now, auto-accept pacts (AI decision making deferred)
  # Both houses establish pact immediately on same turn
```

This works for:
- AI vs AI games (coevolution, balance testing)
- Local/hotseat multiplayer (all players submit orders simultaneously)
- Single-player vs AI

## Required for Multiplayer

### 1. Pending Proposals System

**New Types:**
```nim
type
  ProposalType* {.pure.} = enum
    NonAggressionPact    # Initial implementation
    TradeAgreement       # Future: resource trading
    MilitaryAlliance     # Future: joint operations
    TechnologySharing    # Future: research cooperation

  ProposalStatus* {.pure.} = enum
    Pending    # Awaiting response
    Accepted   # Target accepted
    Rejected   # Target rejected
    Expired    # Timed out without response
    Withdrawn  # Proposer cancelled

  PendingProposal* = object
    id*: string              # Unique proposal ID
    proposer*: HouseId
    target*: HouseId
    proposalType*: ProposalType
    submittedTurn*: int      # When proposal was made
    expiresIn*: int          # Turns until auto-reject (default: 3)
    status*: ProposalStatus
    message*: string         # Optional diplomatic message

  GameState* = object
    # ... existing fields ...
    pendingProposals*: seq[PendingProposal]
```

### 2. New Diplomatic Actions

**Proposal Actions:**
```nim
type
  DiplomaticActionType* {.pure.} = enum
    ProposeNonAggressionPact  # Existing: creates pending proposal
    AcceptProposal            # New: accept pending proposal
    RejectProposal            # New: reject pending proposal
    WithdrawProposal          # New: cancel own proposal
    BreakPact                 # Existing
    DeclareEnemy              # Existing
    SetNeutral                # Existing

  DiplomaticAction* = object
    targetHouse*: HouseId
    actionType*: DiplomaticActionType
    proposalId*: Option[string]  # For accept/reject/withdraw actions
    message*: Option[string]     # Optional diplomatic message
```

### 3. Resolution Flow

**Turn N: Proposal Submission**
```nim
proc processDiplomaticProposal(state: var GameState,
                               proposer: HouseId,
                               action: DiplomaticAction) =
  # Validate proposal (not isolated, cooldowns, etc.)
  if not canFormPact(state.houses[proposer].violationHistory):
    echo "Proposal blocked: diplomatic isolation"
    return

  # Create pending proposal
  let proposal = PendingProposal(
    id: generateProposalId(),
    proposer: proposer,
    target: action.targetHouse,
    proposalType: ProposalType.NonAggressionPact,
    submittedTurn: state.turn,
    expiresIn: 3,  # From config
    status: ProposalStatus.Pending,
    message: action.message.get("")
  )

  state.pendingProposals.add(proposal)
  echo "    ", proposer, " proposed Non-Aggression Pact to ", action.targetHouse

  # Add to target's notification queue (for UI)
  addNotification(state, action.targetHouse,
                 NotificationType.ProposalReceived, proposal)
```

**Turn N+1: Target Response**
```nim
proc processDiplomaticResponse(state: var GameState,
                               responder: HouseId,
                               action: DiplomaticAction) =
  # Find pending proposal
  let proposalId = action.proposalId.get()
  var proposal = findProposal(state, proposalId)

  if proposal.isNone or proposal.get().target != responder:
    echo "Invalid proposal response"
    return

  case action.actionType
  of DiplomaticActionType.AcceptProposal:
    # Establish pact for both houses
    let proposer = proposal.get().proposer

    discard dip_engine.proposePact(
      state.houses[proposer].diplomaticRelations,
      responder, state.houses[proposer].violationHistory, state.turn)

    discard dip_engine.proposePact(
      state.houses[responder].diplomaticRelations,
      proposer, state.houses[responder].violationHistory, state.turn)

    proposal.get().status = ProposalStatus.Accepted
    echo "    ", responder, " accepted Non-Aggression Pact with ", proposer

    # Notify proposer of acceptance
    addNotification(state, proposer,
                   NotificationType.ProposalAccepted, proposal.get())

  of DiplomaticActionType.RejectProposal:
    proposal.get().status = ProposalStatus.Rejected
    echo "    ", responder, " rejected Non-Aggression Pact from ", proposer

    # Optional: Small prestige penalty for rejection?
    # state.houses[responder].prestige -= 1

    # Notify proposer of rejection
    addNotification(state, proposer,
                   NotificationType.ProposalRejected, proposal.get())
```

**Maintenance Phase: Expire Old Proposals**
```nim
proc expirePendingProposals(state: var GameState) =
  for proposal in state.pendingProposals.mitems:
    if proposal.status == ProposalStatus.Pending:
      proposal.expiresIn -= 1

      if proposal.expiresIn <= 0:
        proposal.status = ProposalStatus.Expired
        echo "    Proposal ", proposal.id, " expired (",
             proposal.proposer, " -> ", proposal.target, ")"

        # Notify proposer of expiration
        addNotification(state, proposal.proposer,
                       NotificationType.ProposalExpired, proposal)

  # Clean up old proposals (keep for history, or remove after X turns)
  state.pendingProposals.keepIf(proc(p: PendingProposal): bool =
    p.status == ProposalStatus.Pending or
    (state.turn - p.submittedTurn) < 10  # Keep 10 turn history
  )
```

### 4. AI Decision Making for Responses

**AI Controller Enhancement:**
```nim
proc generateDiplomaticResponse(controller: AIController,
                                state: GameState,
                                rng: var Rand): seq[DiplomaticAction] =
  ## AI decides whether to accept/reject pending proposals
  result = @[]

  # Find proposals targeting this AI
  let myProposals = state.pendingProposals.filter(proc(p: PendingProposal): bool =
    p.target == controller.houseId and p.status == ProposalStatus.Pending
  )

  for proposal in myProposals:
    # Strategic assessment of proposer
    let assessment = assessHouse(controller, state, proposal.proposer)

    # Accept if strategically beneficial
    if assessment.recommendPact and not assessment.recommendEnemy:
      result.add(DiplomaticAction(
        targetHouse: proposal.proposer,
        actionType: DiplomaticActionType.AcceptProposal,
        proposalId: some(proposal.id)
      ))
      return result  # One response per turn

    # Reject if enemy or unfavorable
    elif assessment.recommendEnemy or proposal.expiresIn <= 1:
      result.add(DiplomaticAction(
        targetHouse: proposal.proposer,
        actionType: DiplomaticActionType.RejectProposal,
        proposalId: some(proposal.id)
      ))
      return result

    # Otherwise, wait and think about it (let it pend)
```

### 5. Notification System

**For UI/Client Display:**
```nim
type
  NotificationType* {.pure.} = enum
    ProposalReceived   # You received a diplomatic proposal
    ProposalAccepted   # Your proposal was accepted
    ProposalRejected   # Your proposal was rejected
    ProposalExpired    # Your proposal expired without response
    ProposalWithdrawn  # Proposer withdrew their proposal
    PactViolation      # Someone violated a pact
    EspionageDetected  # Your espionage was detected
    # ... other notification types

  Notification* = object
    turn*: int
    notificationType*: NotificationType
    source*: HouseId            # Who caused this notification
    data*: JsonNode             # Serialized event data (proposal, etc.)
    read*: bool                 # Has player seen this?

  House* = object
    # ... existing fields ...
    notifications*: seq[Notification]
```

### 6. Configuration

**config/diplomacy.toml:**
```toml
[proposals]
# Proposal expiration (turns)
proposal_expiration_turns = 3

# Whether to allow diplomatic messages
allow_messages = true
max_message_length = 500

# Prestige impact (optional)
rejection_penalty = 0  # Prestige lost for rejecting (currently 0)
acceptance_bonus = 0   # Prestige gained for accepting (currently 0)

# Withdrawal rules
allow_withdrawal = true
withdrawal_cooldown_turns = 1  # Can't re-propose for X turns after withdrawal
```

## Implementation Priority

1. **Phase 1: Basic Proposal System** (Multiplayer MVP)
   - Add PendingProposal types
   - Implement proposal creation and expiration
   - Add AcceptProposal/RejectProposal actions
   - Update resolve.nim to handle pending proposals

2. **Phase 2: AI Response Logic**
   - AI decides whether to accept/reject proposals
   - Strategic assessment of proposal value
   - Time-based decision making (accept if about to expire)

3. **Phase 3: Notification System**
   - Store notifications in game state
   - Client/UI displays pending proposals
   - Show proposal history

4. **Phase 4: Diplomatic Messages** (Optional)
   - Allow text messages with proposals
   - Display in UI
   - Store message history

5. **Phase 5: Advanced Proposals** (Future)
   - Trade agreements
   - Technology sharing
   - Military alliances
   - Joint victory conditions

## Backward Compatibility

**For AI/offline games, keep auto-accept behavior:**
```nim
# In config or game setup
type
  GameMode* {.pure.} = enum
    Offline      # Auto-accept pacts (current behavior)
    Multiplayer  # Require proposal/acceptance flow

  GameState* = object
    # ... existing fields ...
    gameMode*: GameMode

# In resolve.nim
if state.gameMode == GameMode.Offline:
  # Auto-accept (current behavior)
  establishPactImmediately(state, proposer, target)
else:
  # Create pending proposal (new behavior)
  createPendingProposal(state, proposer, target)
```

## Testing Considerations

- Test proposal expiration timing
- Test AI acceptance/rejection logic
- Test multiple simultaneous proposals
- Test proposal during diplomatic isolation
- Test proposal cooldown after violation
- Test withdrawal and re-proposal scenarios

## Related Issues

- Need messaging/notification system for multiplayer
- Need UI to display pending proposals
- Need client-side logic to accept/reject proposals
- May need chat/diplomatic messaging system

## References

- docs/specs/diplomacy.md:8.1.2 - Non-Aggression Pacts
- src/engine/resolve.nim:505-527 - Current auto-accept implementation
- tests/balance/ai_controller.nim:984-1043 - AI diplomatic decision making
