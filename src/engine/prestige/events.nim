## Prestige Event Management
##
## Functions for creating and aggregating prestige events

import ../types/prestige

proc createPrestigeEvent*(
  source: PrestigeSource,
  amount: int,
  description: string
): PrestigeEvent =
  ## Create prestige event
  result = PrestigeEvent(
    source: source,
    amount: amount,
    description: description
  )

proc calculatePrestigeChange*(events: seq[PrestigeEvent]): int =
  ## Calculate net prestige change from events
  result = 0
  for event in events:
    result += event.amount

proc createPrestigeReport*(
  houseId: HouseId,
  startingPrestige: int,
  events: seq[PrestigeEvent]
): PrestigeReport =
  ## Create prestige report for house
  let change = calculatePrestigeChange(events)

  result = PrestigeReport(
    houseId: houseId,
    startingPrestige: startingPrestige,
    events: events,
    endingPrestige: startingPrestige + change
  )
