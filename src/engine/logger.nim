## Centralized logging system for EC4X engine
##
## Provides structured logging with levels, categories, and file output
## Replaces scattered echo statements throughout the engine

import std/[logging, strformat, times, os]

type
  LogCategory* = enum
    ## Log categories for filtering and organization
    lcGeneral = "GENERAL"
    lcEconomy = "ECONOMY"
    lcFleet = "FLEET"
    lcColonization = "COLONIZATION"
    lcCombat = "COMBAT"
    lcDiplomacy = "DIPLOMACY"
    lcResearch = "RESEARCH"
    lcOrders = "ORDERS"
    lcAI = "AI"
    lcValidation = "VALIDATION"

var
  engineLogger: ConsoleLogger
  fileLogger: FileLogger
  currentLogFile: string = ""
  loggingEnabled* = true
  logToFile* = false

proc initEngineLogger*(logDir: string = "", enableFileLogging: bool = false) =
  ## Initialize engine logging system
  ## If logDir is provided and enableFileLogging is true, logs will be written to file

  # Console logger with custom format
  engineLogger = newConsoleLogger(
    levelThreshold = lvlDebug,
    fmtStr = "[$time] [$levelname] "
  )

  if enableFileLogging and logDir != "":
    # Ensure log directory exists
    if not dirExists(logDir):
      createDir(logDir)

    # Create timestamped log file
    let timestamp = now().format("yyyyMMdd_HHmmss")
    currentLogFile = logDir / &"ec4x_engine_{timestamp}.log"

    fileLogger = newFileLogger(
      currentLogFile,
      levelThreshold = lvlDebug,
      fmtStr = "$datetime [$levelname] "
    )
    logToFile = true

proc logDebug*(category: LogCategory, msg: string) =
  ## Log debug message with category
  if not loggingEnabled:
    return

  let fullMsg = &"[{category}] {msg}"
  engineLogger.log(lvlDebug, fullMsg)

  if logToFile and fileLogger != nil:
    fileLogger.log(lvlDebug, fullMsg)

proc logInfo*(category: LogCategory, msg: string) =
  ## Log info message with category
  if not loggingEnabled:
    return

  let fullMsg = &"[{category}] {msg}"
  engineLogger.log(lvlInfo, fullMsg)

  if logToFile and fileLogger != nil:
    fileLogger.log(lvlInfo, fullMsg)

proc logWarn*(category: LogCategory, msg: string) =
  ## Log warning message with category
  if not loggingEnabled:
    return

  let fullMsg = &"[{category}] {msg}"
  engineLogger.log(lvlWarn, fullMsg)

  if logToFile and fileLogger != nil:
    fileLogger.log(lvlWarn, fullMsg)

proc logError*(category: LogCategory, msg: string) =
  ## Log error message with category
  if not loggingEnabled:
    return

  let fullMsg = &"[{category}] {msg}"
  engineLogger.log(lvlError, fullMsg)

  if logToFile and fileLogger != nil:
    fileLogger.log(lvlError, fullMsg)

proc logFatal*(category: LogCategory, msg: string) =
  ## Log fatal error message with category
  let fullMsg = &"[{category}] {msg}"
  engineLogger.log(lvlFatal, fullMsg)

  if logToFile and fileLogger != nil:
    fileLogger.log(lvlFatal, fullMsg)

proc getLogFile*(): string =
  ## Get current log file path
  return currentLogFile

proc setLoggingEnabled*(enabled: bool) =
  ## Enable or disable logging globally
  loggingEnabled = enabled

proc closeEngineLogger*() =
  ## Close file logger if open
  if fileLogger != nil:
    fileLogger.file.close()
    fileLogger = nil

# Initialize with console logging only by default
initEngineLogger()
