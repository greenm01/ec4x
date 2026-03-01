import std/[unittest, os, times]
import ../../src/daemon/config

proc writeTempKdl(content: string): string =
  let path = getTempDir() / ("ec4x_daemon_config_" &
    $epochTime().int64 & ".kdl")
  writeFile(path, content)
  path

suite "Daemon Config":
  test "auto_resolve_on_all_submitted defaults to true":
    let path = writeTempKdl("""
daemon {
  data_dir "data"
  poll_interval 30
  turn_deadline_minutes 60
  relay_urls {
    url "ws://localhost:8080"
  }
}
""")
    defer:
      if fileExists(path):
        removeFile(path)

    let cfg = parseDaemonKdl(path)
    check cfg.auto_resolve_on_all_submitted

  test "deadline zero disables deadline auto-resolve":
    let path = writeTempKdl("""
daemon {
  data_dir "data"
  poll_interval 30
  turn_deadline_minutes 0
  auto_resolve_on_all_submitted #false
  relay_urls {
    url "ws://localhost:8080"
  }
}
""")
    defer:
      if fileExists(path):
        removeFile(path)

    let cfg = parseDaemonKdl(path)
    check cfg.turn_deadline_minutes == 0
    check not cfg.auto_resolve_on_all_submitted
