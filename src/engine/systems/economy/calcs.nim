proc calculatePTU*(pu: int): int =
  ## Convert PU to PTU per economy.md:3.1
  ## Formula: PTU = pu - 1 + exp(0.00657 * pu)
  ##
  ## This exponential relationship models dis-inflationary economics:
  ## High-PU colonies contribute many PTUs with minimal PU loss,
  ## incentivizing population concentration and growth.

  if pu <= 0:
    return 0

  if pu == 1:
    # PTU = 1 - 1 + exp(0.00657) = 0 + 1.0066 ≈ 1
    return 1

  const conversionFactor = 0.00657
  let exponent = conversionFactor * float(pu)
  let expValue = exp(exponent)

  result = pu - 1 + int(round(expValue))

proc calculatePU*(ptu: int): int =
  ## Convert PTU to PU per economy.md:3.1
  ## Inverse of calculatePTU using binary search approximation
  ## (Lambert W function is complex to implement in Nim)
  ##
  ## Accurate within ±1 PU which is acceptable for game mechanics

  if ptu <= 0:
    return 0

  if ptu == 1:
    return 1

  # Binary search for PU that gives target PTU
  var low = 1
  var high = ptu + 100  # Upper bound estimate

  while low < high:
    let mid = (low + high) div 2
    let calculatedPTU = calculatePTU(mid)

    if calculatedPTU < ptu:
      low = mid + 1
    elif calculatedPTU > ptu:
      high = mid
    else:
      return mid  # Exact match

  # Return closest PU value
  let ptuLow = calculatePTU(low)
  let ptuHigh = if high <= ptu + 100: calculatePTU(high) else: int.high

  if abs(ptuLow - ptu) < abs(ptuHigh - ptu):
    result = low
  else:
    result = high

