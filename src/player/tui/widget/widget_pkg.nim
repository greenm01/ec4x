## Widget package - TUI widget system
##
## Provides a widget system for building terminal UIs.
## Widgets are ephemeral, recreated each frame, with render consuming self.
##
## Core components:
## - Text system: Span, Line, Text for styled text
## - Borders: Border types and character sets
## - Block: Container widget with borders/titles
## - Paragraph: Text display widget
## - List: Scrollable list with selection
##
## Inspired by ratatui's widget system.

import ./text/text_pkg
import ./borders
import ./widget
import ./frame
import ./paragraph
import ./list

# Re-export everything
export text_pkg
export borders
export widget
export frame
export paragraph
export list
