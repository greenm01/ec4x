## Screen and cursor operation types.
##
## Defines enums for screen clearing modes, cursor movement directions,
## and mouse tracking modes.

type
  EraseMode* {.pure.} = enum
    ## Screen/line erase modes.
    ToEnd = 0      ## Erase from cursor to end
    ToBeginning = 1  ## Erase from cursor to beginning
    Entire = 2     ## Erase entire screen/line

  MouseMode* {.pure.} = enum
    ## Mouse tracking modes.
    Press         ## Track button presses only (X10)
    Normal        ## Track button press and release (VT200)
    Hilite        ## Highlight tracking (VT200)
    CellMotion    ## Track motion when button pressed (button-event)
    AllMotion     ## Track all motion (any-event)
    ExtendedSgr   ## SGR extended coordinates
    PixelsSgr     ## SGR pixel coordinates

  CursorStyle* {.pure.} = enum
    ## Cursor styles (DECSCUSR).
    Default = 0
    BlinkingBlock = 1
    SteadyBlock = 2
    BlinkingUnderline = 3
    SteadyUnderline = 4
    BlinkingBar = 5
    SteadyBar = 6

  BracketedPasteState* {.pure.} = enum
    ## Bracketed paste mode state.
    Disabled
    Enabled
    InPaste  ## Currently receiving pasted content
