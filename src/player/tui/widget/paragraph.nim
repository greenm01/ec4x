## Paragraph - Text display widget
##
## Displays multi-line text with optional wrapping and scrolling.
## Can be wrapped in a Frame for borders/titles.

import std/options
import ./text/text_pkg
import ./frame
import ../buffer
import ../layout/rect

type
  Wrap* = object
    ## Text wrapping configuration.
    trim*: bool  ## Trim leading whitespace on wrapped lines

  Paragraph* = object
    ## Multi-line text display widget.
    blk: Option[Frame]  # Renamed from 'block' (keyword)
    text: Text
    style: CellStyle
    wrap: Option[Wrap]
    scroll: tuple[x, y: int]
    alignment: Alignment

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc paragraph*(text: Text): Paragraph =
  ## Create a paragraph from Text.
  Paragraph(
    blk: none(Frame),
    text: text,
    style: defaultStyle(),
    wrap: none(Wrap),
    scroll: (0, 0),
    alignment: Alignment.Left
  )

proc paragraph*(content: string): Paragraph =
  ## Create a paragraph from a string.
  paragraph(text(content))

# -----------------------------------------------------------------------------
# Builder methods
# -----------------------------------------------------------------------------

proc `block`*(p: Paragraph, b: Frame): Paragraph =
  ## Wrap paragraph in a block.
  result = p
  result.blk = some(b)

proc style*(p: Paragraph, s: CellStyle): Paragraph =
  ## Set paragraph style.
  result = p
  result.style = s

proc wrap*(p: Paragraph, w: Wrap): Paragraph =
  ## Enable text wrapping.
  result = p
  result.wrap = some(w)

proc scroll*(p: Paragraph, x, y: int): Paragraph =
  ## Set scroll offset.
  result = p
  result.scroll = (x, y)

proc alignment*(p: Paragraph, a: Alignment): Paragraph =
  ## Set text alignment.
  result = p
  result.alignment = a

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

proc render*(p: Paragraph, area: Rect, buf: var CellBuffer) =
  ## Render the paragraph to the buffer.
  ## Implements Widget.render.
  
  if area.isEmpty:
    return
  
  # Apply paragraph style to area
  if not p.style.fg.isNone or not p.style.bg.isNone:
    buf.setStyle(area, p.style)
  
  # Render optional block
  var contentArea = area
  if p.blk.isSome:
    let b = p.blk.get()
    b.render(area, buf)
    contentArea = b.inner(area)
  
  if contentArea.isEmpty:
    return
  
  # Render text lines
  var y = contentArea.y - p.scroll.y
  
  for line in p.text.lines:
    if y >= contentArea.bottom:
      break
    
    if y >= contentArea.y:
      # Calculate x offset based on alignment
      let lineAlign = if line.alignment != Alignment.Left: 
                        line.alignment 
                      else: 
                        p.alignment
      
      var x = contentArea.x
      case lineAlign
      of Alignment.Left:
        x = contentArea.x
      of Alignment.Center:
        let lineWidth = line.width()
        if lineWidth < contentArea.width:
          x = contentArea.x + (contentArea.width - lineWidth) div 2
      of Alignment.Right:
        let lineWidth = line.width()
        if lineWidth < contentArea.width:
          x = contentArea.right - lineWidth
      
      # Apply horizontal scroll
      x -= p.scroll.x
      
      # Render spans
      for span in line.spans:
        if x >= contentArea.right:
          break
        
        # Merge span style with line/text styles
        var spanStyle = span.style
        if spanStyle.fg.isNone and not p.text.style.fg.isNone:
          spanStyle.fg = p.text.style.fg
        if spanStyle.bg.isNone and not p.text.style.bg.isNone:
          spanStyle.bg = p.text.style.bg
        
        let written = buf.setString(x, y, span.content, spanStyle)
        x += written
    
    y += 1
