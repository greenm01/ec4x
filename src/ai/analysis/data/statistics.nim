## Statistical Functions Module
##
## This module provides statistical analysis functions for DataFrames,
## including outlier detection, percentiles, and z-scores.

import datamancer
import arraymancer
import std/[math, algorithm, sequtils]

proc toSeq*(tensor: Tensor[float]): seq[float] =
  ## Convert Tensor to seq for compatibility
  result = newSeq[float](tensor.size)
  for i in 0 ..< tensor.size:
    result[i] = tensor[i]

proc mean*(values: seq[float]): float =
  ## Calculate mean of a sequence of floats
  if values.len == 0:
    return 0.0
  result = values.sum() / float(values.len)

proc stdDev*(values: seq[float]): float =
  ## Calculate standard deviation of a sequence of floats
  if values.len == 0:
    return 0.0

  let m = values.mean()
  var sumSq = 0.0
  for v in values:
    sumSq += (v - m) * (v - m)

  result = sqrt(sumSq / float(values.len))

proc percentile*(values: seq[float], p: float): float =
  ## Calculate percentile of a sequence
  ##
  ## Args:
  ##   values: Input values
  ##   p: Percentile (0.0 to 1.0)
  ##
  ## Returns:
  ##   Value at the given percentile
  if values.len == 0:
    return 0.0

  var sorted = values.sorted()
  let idx = int(p * float(sorted.len - 1))
  result = sorted[idx]

proc zScores*(df: DataFrame, column: string): seq[float] =
  ## Calculate z-scores for a column
  ##
  ## Z-score = (value - mean) / stddev
  ##
  ## Args:
  ##   df: Input DataFrame
  ##   column: Column name to calculate z-scores for
  ##
  ## Returns:
  ##   Sequence of z-scores
  let col = df[column, float].toSeq()
  let m = col.mean()
  let s = col.stdDev()

  if s == 0.0:
    # All values are the same, return zeros
    return newSeqWith(col.len, 0.0)

  result = newSeq[float](col.len)
  for i in 0 ..< col.len:
    result[i] = (col[i] - m) / s

proc detectOutliers*(df: DataFrame, column: string, threshold = 3.0): seq[int] =
  ## Detect outliers in a column using z-score method
  ##
  ## An outlier is defined as |z-score| > threshold
  ##
  ## Args:
  ##   df: Input DataFrame
  ##   column: Column to check for outliers
  ##   threshold: Z-score threshold (default: 3.0)
  ##
  ## Returns:
  ##   Sequence of row indices that are outliers
  let zScores = zScores(df, column)

  result = newSeq[int]()
  for i in 0 ..< zScores.len:
    if abs(zScores[i]) > threshold:
      result.add(i)

proc summary*(df: DataFrame, column: string): tuple[count: int, mean: float, std: float, min: float, p25: float, p50: float, p75: float, max: float] =
  ## Generate summary statistics for a column
  ##
  ## Similar to pandas describe() for a single column
  ##
  ## Returns:
  ##   Tuple with count, mean, std, min, 25th percentile, median, 75th percentile, max
  let col = df[column, float].toSeq()

  result.count = col.len
  result.mean = col.mean()
  result.std = col.stdDev()

  if col.len > 0:
    let sorted = col.sorted()
    result.min = sorted[0]
    result.p25 = percentile(sorted, 0.25)
    result.p50 = percentile(sorted, 0.50)
    result.p75 = percentile(sorted, 0.75)
    result.max = sorted[^1]
  else:
    result.min = 0.0
    result.p25 = 0.0
    result.p50 = 0.0
    result.p75 = 0.0
    result.max = 0.0
