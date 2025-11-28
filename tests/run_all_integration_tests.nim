## Integration Test Runner
##
## Runs all integration tests in tests/integration/
## Reports pass/fail summary for each test suite

import std/[os, osproc, strutils, strformat]

type
  TestResult = object
    name: string
    passed: bool
    output: string

proc runTest(testFile: string): TestResult =
  ## Run a single test file and capture result
  result.name = testFile.extractFilename().changeFileExt("")

  echo &"Running: {result.name}..."

  # Compile and run test
  let (output, exitCode) = execCmdEx(&"nim c -r --hints:off {testFile}")
  result.passed = (exitCode == 0)
  result.output = output

  if result.passed:
    echo &"  ✅ PASS"
  else:
    echo &"  ❌ FAIL"

proc main() =
  echo "=".repeat(80)
  echo "EC4X Integration Test Suite"
  echo "=".repeat(80)
  echo ""

  var results: seq[TestResult] = @[]

  # Find all integration test files
  let integrationDir = "tests/integration"
  for file in walkFiles(integrationDir / "*.nim"):
    results.add(runTest(file))

  # Print summary
  echo ""
  echo "=".repeat(80)
  echo "Test Summary"
  echo "=".repeat(80)

  var passed = 0
  var failed = 0

  for result in results:
    if result.passed:
      echo &"✅ {result.name}"
      passed.inc
    else:
      echo &"❌ {result.name}"
      failed.inc

  echo ""
  echo &"Total: {results.len} tests"
  echo &"Passed: {passed}"
  echo &"Failed: {failed}"

  if failed > 0:
    echo ""
    echo "Failed Test Details:"
    echo "=".repeat(80)
    for result in results:
      if not result.passed:
        echo &"\n{result.name}:"
        echo result.output

    quit(1)
  else:
    echo ""
    echo "🎉 All integration tests passed!"
    quit(0)

when isMainModule:
  main()
