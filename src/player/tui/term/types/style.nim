## Style type definition for text styling.
##
## Style represents a styled piece of text with foreground/background colors
## and text attributes (bold, italic, underline, etc.).

import core

type
  StyleAttr* {.pure.} = enum
    ## Text style attributes.
    Bold
    Faint
    Italic
    Underline
    Blink
    Reverse
    CrossOut
    Overline

  Style* = object
    ## Styled text representation.
    ## Immutable builder pattern: each method returns a new Style.
    profile*: Profile
    text*: string
    fg*: Color
    bg*: Color
    attrs*: set[StyleAttr]


# Style constructors
proc initStyle*(profile: Profile = Profile.TrueColor): Style =
  ## Create an empty style with the given profile.
  Style(
    profile: profile,
    text: "",
    fg: noColor(),
    bg: noColor(),
    attrs: {}
  )

proc initStyle*(text: string, profile: Profile = Profile.TrueColor): Style =
  ## Create a style with text content.
  Style(
    profile: profile,
    text: text,
    fg: noColor(),
    bg: noColor(),
    attrs: {}
  )


# Style attribute queries
proc hasForeground*(s: Style): bool {.inline.} =
  not s.fg.isNone

proc hasBackground*(s: Style): bool {.inline.} =
  not s.bg.isNone

proc hasAttrs*(s: Style): bool {.inline.} =
  s.attrs.len > 0

proc isEmpty*(s: Style): bool {.inline.} =
  ## Returns true if style has no colors or attributes.
  s.fg.isNone and s.bg.isNone and s.attrs.len == 0
