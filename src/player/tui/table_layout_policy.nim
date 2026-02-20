## Shared table sizing/scroll policy for Player TUI.

const
  DefaultTableRowCap* = 20
  DefaultMaxHeightPercent* = 75
  MinVisibleRows* = 1

  TableChromeRows* = 4          ## top/bottom + header + separator
  ModalFooterRows* = 2          ## separator + footer text
  PanelFrameRows* = 2           ## rounded frame top + bottom

proc maxRowsByHeight*(
    canvasHeight: int,
    overheadRows: int,
    maxHeightPercent: int = DefaultMaxHeightPercent
): int =
  ## Maximum data rows that can fit given viewport and fixed overhead.
  let maxContentHeight = max(
    1, (canvasHeight * maxHeightPercent) div 100
  )
  max(MinVisibleRows, maxContentHeight - overheadRows)

proc clampedVisibleRows*(
    totalRows: int,
    canvasHeight: int,
    overheadRows: int,
    rowCap: int = DefaultTableRowCap,
    maxHeightPercent: int = DefaultMaxHeightPercent
): int =
  ## Clamp visible table rows by content count, row cap, and viewport fit.
  if totalRows <= 0:
    return MinVisibleRows
  let cap = if rowCap > 0: rowCap else: totalRows
  let maxRows = maxRowsByHeight(
    canvasHeight, overheadRows, maxHeightPercent
  )
  max(MinVisibleRows, min(totalRows, min(cap, maxRows)))

proc contentHeightFromVisibleRows*(
    visibleRows: int,
    overheadRows: int
): int =
  ## Convert visible row count to modal content height.
  max(1, visibleRows) + max(0, overheadRows)

proc clampScrollOffset*(
    offset: int,
    totalRows: int,
    viewportRows: int
): int =
  ## Clamp scroll offset to valid range.
  let maxOffset = max(0, totalRows - max(1, viewportRows))
  clamp(offset, 0, maxOffset)
