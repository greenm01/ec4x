## EC4X Engine Logging System
##
## Lightweight, structured logging with compile-time filtering
## Usage:
##   import common/logger
##   logDebug("Combat", "Resolving space combat in system", systemId)
##   logInfo("Economy", "Income phase complete", income = 1500)
##   logWarn("Fleet", "Fleet has no destination", fleetId)
##   logError("Resolve", "Invalid command", error = errorMsg)
##
## Compile with log level control:
##   nim c -d:logLevel=DEBUG   # Show all logs
##   nim c -d:logLevel=INFO    # Show INFO, WARN, ERROR (default)
##   nim c -d:logLevel=WARN    # Show WARN, ERROR only
##   nim c -d:logLevel=ERROR   # Show ERROR only
##   nim c -d:release          # Disables DEBUG logs automatically

import std/[times, strformat, terminal, strutils]

type
  LogLevel* {.pure.} = enum
    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3

# Compile-time log level configuration
const CompileLogLevel* =
  when defined(logLevel):
    when defined(logLevelDEBUG):
      LogLevel.DEBUG
    elif defined(logLevelINFO):
      LogLevel.INFO
    elif defined(logLevelWARN):
      LogLevel.WARN
    elif defined(logLevelERROR):
      LogLevel.ERROR
    else:
      LogLevel.INFO  # Default to INFO
  elif defined(release):
    LogLevel.INFO  # Production: INFO and above
  else:
    LogLevel.DEBUG  # Debug builds: show everything

# Color coding for log levels
proc getLevelColor(level: LogLevel): ForegroundColor =
  case level
  of LogLevel.DEBUG: fgCyan
  of LogLevel.INFO: fgGreen
  of LogLevel.WARN: fgYellow
  of LogLevel.ERROR: fgRed

proc getLevelStr(level: LogLevel): string =
  case level
  of LogLevel.DEBUG: "DEBUG"
  of LogLevel.INFO: "INFO "
  of LogLevel.WARN: "WARN "
  of LogLevel.ERROR: "ERROR"

# Core logging function (runtime check removed - filtering done in templates)
proc log*(level: LogLevel, module: string, message: string, details: string = "") =
  ## Core logging function - use log* templates instead (they handle compile-time filtering)
  let timestamp = now().format("HH:mm:ss")
  let levelStr = getLevelStr(level)
  let color = getLevelColor(level)

  stdout.styledWrite(fgWhite, &"[{timestamp}] ")
  stdout.styledWrite(color, &"[{levelStr}] ")
  stdout.styledWrite(fgWhite, &"[{module:12}] ", message)

  if details.len > 0:
    stdout.styledWriteLine(fgCyan, &" | {details}")
  else:
    stdout.write("\n")

  flushFile(stdout)

# Convenience templates with compile-time filtering
template logDebug*(module: string, message: string, details: varargs[string, `$`]) =
  ## Debug log - filtered out in release builds
  when CompileLogLevel <= LogLevel.DEBUG:
    log(LogLevel.DEBUG, module, message, details.join(" "))

template logInfo*(module: string, message: string, details: varargs[string, `$`]) =
  ## Info log - normal operational messages
  when CompileLogLevel <= LogLevel.INFO:
    log(LogLevel.INFO, module, message, details.join(" "))

template logWarn*(module: string, message: string, details: varargs[string, `$`]) =
  ## Warning log - potential issues
  when CompileLogLevel <= LogLevel.WARN:
    log(LogLevel.WARN, module, message, details.join(" "))

template logError*(module: string, message: string, details: varargs[string, `$`]) =
  ## Error log - critical issues
  when CompileLogLevel <= LogLevel.ERROR:
    log(LogLevel.ERROR, module, message, details.join(" "))

# Structured logging helpers
template logCombat*(message: string, details: varargs[string, `$`]) =
  logInfo("Combat", message, details)

template logEconomy*(message: string, details: varargs[string, `$`]) =
  logInfo("Economy", message, details)

template logFleet*(message: string, details: varargs[string, `$`]) =
  logInfo("Fleet", message, details)

template logResolve*(message: string, details: varargs[string, `$`]) =
  logInfo("Resolve", message, details)

template logTable*(message: string, details: varargs[string, `$`]) =
  ## Table operation logging (for debugging table issues)
  logDebug("Table", message, details)

# Performance-sensitive debug logging (only in debug builds)
template logPerf*(module: string, message: string, details: varargs[string, `$`]) =
  when not defined(release):
    logDebug(module, &"[PERF] {message}", details)

# RNG logging for determinism verification
template logRNG*(message: string, details: varargs[string, `$`]) =
  logDebug("RNG", message, details)
