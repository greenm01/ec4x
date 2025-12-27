type
  ValidationResult* = object ## Result of a validation check
    valid*: bool
    errorMessage*: string

  ValidationError* = object of CatchableError ## Exception raised when validation fails

  ValidationSeverity* {.pure.} = enum
    ## Severity level for validation failures
    vWarning ## Log warning but continue execution
    vError ## Raise exception and halt


