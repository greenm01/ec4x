import unittest
import ../src/daemon/[daemon, sam_core]

suite DaemonTests:
  test initModelTest:
    let model = initModel("data", 30)
    check model.running
    check model.games.len == 0
    check model.pollInterval == 30

  test samProcessTest:
    let loop = newSamLoop(initModel("data", 30))
    let testProposal = Proposal[DaemonModel](
      name: "test",
      payload: proc(model: var DaemonModel) =
        model.running = false
    )
    loop.present(testProposal)
    loop.process()
    check not loop.model.running

runTests()
