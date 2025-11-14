## Turn scheduler - triggers turn resolution at configured times

import std/[times, asyncdispatch]

type
  TurnSchedule* = object
    hour*: int           # Hour to run turn (0-23)
    minute*: int         # Minute to run turn (0-59)
    timezone*: string    # Timezone (e.g., "UTC")

  Scheduler* = ref object
    schedule*: TurnSchedule
    onTurnTrigger*: proc()

proc newScheduler*(schedule: TurnSchedule): Scheduler =
  ## Create new turn scheduler
  result = Scheduler(
    schedule: schedule
  )

proc timeUntilNextTurn*(sched: Scheduler): Duration =
  ## Calculate time until next scheduled turn
  ## TODO: Implement time calculation
  raise newException(CatchableError, "Not yet implemented")

proc start*(sched: Scheduler) {.async.} =
  ## Start scheduler loop
  ## TODO: Implement scheduling loop that calls onTurnTrigger at configured time
  raise newException(CatchableError, "Not yet implemented")

proc triggerManualTurn*(sched: Scheduler) =
  ## Manually trigger a turn resolution
  if sched.onTurnTrigger != nil:
    sched.onTurnTrigger()
