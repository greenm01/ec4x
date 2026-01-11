## KDL Configuration Helpers
##
## Generic utilities for loading and validating KDL configuration files
##
## Design principles:
## - Type-safe value extraction with clear error messages
## - Automatic validation with configurable severity
## - Support for optional fields with defaults
## - Path-based error reporting for nested structures

import std/[options, os, strformat, strutils, tables]
import ../types/config
import kdl

# ============================================================================
# Exception Helpers
# ============================================================================

proc newConfigError*(message: string): ConfigError =
  ## Create a new ConfigError exception
  result = ConfigError(msg: message)

# ============================================================================
# Node Navigation Helpers
# ============================================================================

proc findNode*(doc: KdlDoc, name: string): Option[KdlNode] =
  ## Find top-level node by name
  for node in doc:
    if node.name == name:
      return some(node)
  none(KdlNode)

proc findChildNode*(parent: KdlNode, name: string): Option[KdlNode] =
  ## Find child node by name
  for child in parent.children:
    if child.name == name:
      return some(child)
  none(KdlNode)

proc child*(node: KdlNode, childName: string): Option[KdlVal] =
  ## Get first argument value from child node
  ## Example: ship { attackStrength 10 } → child("attackStrength") = 10
  for child in node.children:
    if child.name == childName and child.args.len > 0:
      return some(child.args[0])
  none(KdlVal)

proc hasChild*(node: KdlNode, childName: string): bool =
  ## Check if node has a child with given name
  for child in node.children:
    if child.name == childName:
      return true
  false

# ============================================================================
# Property/Attribute Helpers
# ============================================================================

proc property*(node: KdlNode, propName: string): Option[KdlVal] =
  ## Get property value from node (properties are key-value pairs on node line)
  ## Example: ship name="Destroyer" → property("name") = "Destroyer"
  if propName in node.props:
    return some(node.props[propName])
  none(KdlVal)

proc stringAttribute*(
    node: KdlNode, attrName: string, ctx: KdlConfigContext
): Option[string] =
  ## Get string property/attribute from node
  let propOpt = node.property(attrName)
  if propOpt.isNone:
    return none(string)

  let val = propOpt.get
  if val.kind == KValKind.KString:
    return some(val.getString())
  else:
    return none(string)

# ============================================================================
# Required Field Extraction (raises ConfigError if missing)
# ============================================================================

proc requireNode*(doc: KdlDoc, name: string, ctx: KdlConfigContext): KdlNode =
  ## Get required top-level node, raise ConfigError if missing
  let nodeOpt = doc.findNode(name)
  if nodeOpt.isNone:
    raise newConfigError(
      &"Missing required node '{name}' in {ctx.filepath}")
  nodeOpt.get

proc requireChildNode*(parent: KdlNode, name: string, ctx: KdlConfigContext): KdlNode =
  ## Get required child node, raise ConfigError if missing
  let nodeOpt = parent.findChildNode(name)
  if nodeOpt.isNone:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Missing required child '{name}' in {path} ({ctx.filepath})")
  nodeOpt.get

proc requireInt32*(node: KdlNode, childName: string, ctx: KdlConfigContext): int32 =
  ## Get required integer value from child node
  let valOpt = node.child(childName)
  if valOpt.isNone:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Missing required field '{childName}' in {path} ({ctx.filepath})")

  let val = valOpt.get
  case val.kind
  of KValKind.KInt, KValKind.KInt8, KValKind.KInt16, KValKind.KInt32, KValKind.KInt64:
    val.getInt().int32
  of KValKind.KUInt8, KValKind.KUInt16, KValKind.KUInt32, KValKind.KUInt64:
    val.getInt().int32
  else:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be integer, got {val.kind} ({ctx.filepath})")

proc requireFloat32*(node: KdlNode, childName: string, ctx: KdlConfigContext): float32 =
  ## Get required float value from child node
  let valOpt = node.child(childName)
  if valOpt.isNone:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Missing required field '{childName}' in {path} ({ctx.filepath})")
  
  let val = valOpt.get
  case val.kind
  of KValKind.KFloat, KValKind.KFloat32, KValKind.KFloat64:
    val.getFloat().float32
  of KValKind.KInt, KValKind.KInt32, KValKind.KInt64:
    val.getInt().float32
  else:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be numeric, got {val.kind} ({ctx.filepath})")

proc requireString*(node: KdlNode, childName: string, ctx: KdlConfigContext): string =
  ## Get required string value from child node
  let valOpt = node.child(childName)
  if valOpt.isNone:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Missing required field '{childName}' in {path} ({ctx.filepath})")
  
  let val = valOpt.get
  if val.kind != KValKind.KString:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be string, got {val.kind} ({ctx.filepath})")
  val.getString()

proc requireBool*(node: KdlNode, childName: string, ctx: KdlConfigContext): bool =
  ## Get required boolean value from child node
  let valOpt = node.child(childName)
  if valOpt.isNone:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Missing required field '{childName}' in {path} ({ctx.filepath})")
  
  let val = valOpt.get
  if val.kind != KValKind.KBool:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be boolean, got {val.kind} ({ctx.filepath})")
  val.getBool()

# ============================================================================
# Optional Field Extraction (returns Option or default value)
# ============================================================================

proc int32Val*(node: KdlNode, childName: string, default: int32): int32 =
  ## Get optional int32 value with default
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return default

  let val = valOpt.get
  case val.kind
  of KValKind.KInt, KValKind.KInt8, KValKind.KInt16, KValKind.KInt32, KValKind.KInt64,
     KValKind.KUInt8, KValKind.KUInt16, KValKind.KUInt32, KValKind.KUInt64:
    val.getInt().int32
  else:
    default

proc float32Val*(node: KdlNode, childName: string, default: float32): float32 =
  ## Get optional float32 value with default
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return default

  let val = valOpt.get
  case val.kind
  of KValKind.KFloat, KValKind.KFloat32, KValKind.KFloat64:
    val.getFloat().float32
  of KValKind.KInt, KValKind.KInt32, KValKind.KInt64:
    val.getInt().float32
  else:
    default

proc stringVal*(node: KdlNode, childName: string, default: string): string =
  ## Get optional string value with default
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return default
  
  let val = valOpt.get
  if val.kind == KValKind.KString:
    val.getString()
  else:
    default

proc boolVal*(node: KdlNode, childName: string, default: bool): bool =
  ## Get optional boolean value with default
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return default
  
  let val = valOpt.get
  if val.kind == KValKind.KBool:
    val.getBool()
  else:
    default

proc int32Opt*(node: KdlNode, childName: string): Option[int32] =
  ## Get optional integer as Option[int32]
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return none(int32)

  let val = valOpt.get
  case val.kind
  of KValKind.KInt, KValKind.KInt8, KValKind.KInt16, KValKind.KInt32, KValKind.KInt64,
     KValKind.KUInt8, KValKind.KUInt16, KValKind.KUInt32, KValKind.KUInt64:
    some(val.getInt().int32)
  else:
    none(int32)

proc int64Opt*(node: KdlNode, childName: string): Option[int64] =
  ## Get optional integer as Option[int64]
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return none(int64)

  let val = valOpt.get
  case val.kind
  of KValKind.KInt, KValKind.KInt8, KValKind.KInt16, KValKind.KInt32, KValKind.KInt64,
     KValKind.KUInt8, KValKind.KUInt16, KValKind.KUInt32, KValKind.KUInt64:
    some(val.getInt().int64)
  else:
    none(int64)
    
proc float32Opt*(node: KdlNode, childName: string): Option[float32] =
  ## Get optional float as Option[float32]
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return none(float32)

  let val = valOpt.get
  case val.kind
  of KValKind.KFloat, KValKind.KFloat32, KValKind.KFloat64:
    some(val.getFloat().float32)
  of KValKind.KInt, KValKind.KInt32, KValKind.KInt64:
    some(val.getInt().float32)
  else:
    none(float32)

proc stringOpt*(node: KdlNode, childName: string): Option[string] =
  ## Get optional string as Option[string]
  let valOpt = node.child(childName)
  if valOpt.isNone:
    return none(string)
  
  let val = valOpt.get
  if val.kind == KValKind.KString:
    some(val.getString())
  else:
    none(string)

# ============================================================================
# Validated Field Extraction (combines extraction + validation)
# ============================================================================

proc requirePositiveInt32*(node: KdlNode, childName: string, ctx: KdlConfigContext): int32 =
  ## Get required integer that must be > 0
  result = node.requireInt32(childName, ctx)
  if result <= 0:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be positive, got {result} ({ctx.filepath})")

proc requireNonNegativeInt32*(node: KdlNode, childName: string, ctx: KdlConfigContext): int32 =
  ## Get required integer that must be >= 0
  result = node.requireInt32(childName, ctx)
  if result < 0:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be non-negative, got {result} ({ctx.filepath})")

proc requireRangeInt32*(
    node: KdlNode, 
    childName: string, 
    min, max: int, 
    ctx: KdlConfigContext
): int32 =
  ## Get required integer within [min, max] range
  result = node.requireInt32(childName, ctx)
  if result < min or result > max:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be between {min} and {max}, got {result} ({ctx.filepath})")

proc requireRatio*(node: KdlNode, childName: string, ctx: KdlConfigContext): float32 =
  ## Get required float32 that must be in [0.0, 1.0]
  result = node.requireFloat32(childName, ctx)
  if result < 0.0 or result > 1.0:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be ratio [0.0-1.0], got {result} ({ctx.filepath})")

proc requirePercentage*(node: KdlNode, childName: string, ctx: KdlConfigContext): float32 =
  ## Get required float that must be in [0.0, 100.0]
  result = node.requireFloat32(childName, ctx)
  if result < 0.0 or result > 100.0:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Field '{childName}' in {path} must be percentage [0.0-100.0], got {result} ({ctx.filepath})")

# ============================================================================
# Context Management
# ============================================================================

proc newContext*(filepath: string): KdlConfigContext =
  ## Create new config context for error reporting
  KdlConfigContext(filepath: filepath, nodePath: @[])

proc pushNode*(ctx: var KdlConfigContext, nodeName: string) =
  ## Add node to path for nested error reporting
  ctx.nodePath.add(nodeName)

proc popNode*(ctx: var KdlConfigContext) =
  ## Remove last node from path
  if ctx.nodePath.len > 0:
    discard ctx.nodePath.pop()

template withNode*(ctx: var KdlConfigContext, nodeName: string, body: untyped) =
  ## Execute body with node added to context path
  ctx.pushNode(nodeName)
  try:
    body
  finally:
    ctx.popNode()

# ============================================================================
# Collection Helpers
# ============================================================================

proc allChildren*(node: KdlNode): seq[KdlNode] =
  ## Get all child nodes
  result = @[]
  for child in node.children:
    result.add(child)

proc childrenByName*(parent: KdlNode, name: string): seq[KdlNode] =
  ## Get all children with given name
  result = @[]
  for child in parent.children:
    if child.name == name:
      result.add(child)

proc childNames*(node: KdlNode): seq[string] =
  ## Get names of all child nodes
  result = @[]
  for child in node.children:
    if child.name notin result:
      result.add(child.name)

# ============================================================================
# Enum Parsing Helpers
# ============================================================================

proc parseEnum*[T: enum](
    node: KdlNode, 
    childName: string, 
    ctx: KdlConfigContext
): T =
  ## Parse enum value from string field
  ## Automatically tries case-insensitive matching
  let strVal = node.requireString(childName, ctx)
  
  try:
    parseEnum[T](strVal)
  except ValueError:
    # Try case-insensitive match
    for enumVal in T:
      if ($enumVal).toLowerAscii() == strVal.toLowerAscii():
        return enumVal
    
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"Invalid enum value '{strVal}' for '{childName}' in {path} ({ctx.filepath})")

# ============================================================================
# Table Building Helpers
# ============================================================================

proc buildTable*[K, V](
    doc: KdlDoc,
    nodeName: string,
    keyExtractor: proc(node: KdlNode): K,
    valueBuilder: proc(node: KdlNode, ctx: var KdlConfigContext): V,
    ctx: var KdlConfigContext
): Table[K, V] =
  ## Build table from KDL nodes
  ## Each top-level node with matching name becomes a table entry
  result = initTable[K, V]()
  
  for node in doc:
    if node.name == nodeName:
      ctx.withNode(node.name):
        let key = keyExtractor(node)
        let value = valueBuilder(node, ctx)
        result[key] = value

# ============================================================================
# Validation Integration
# ============================================================================

proc validateWithContext*[T](
    value: T,
    validator: proc(val: T, fieldName: string),
    fieldName: string,
    ctx: KdlConfigContext
) =
  ## Run validator with config context for better error messages
  try:
    validator(value, fieldName)
  except CatchableError as e:
    let path = ctx.nodePath.join(".")
    raise newConfigError(
      &"{e.msg} in {path} ({ctx.filepath})")

# ============================================================================
# File Loading
# ============================================================================

proc loadKdlConfig*(filepath: string): KdlDoc =
  ## Load and parse KDL file, raise ConfigError if not found or invalid
  if not fileExists(filepath):
    raise newConfigError( &"Config file not found: {filepath}")
  
  try:
    let content = readFile(filepath)
    parseKdl(content)
  except CatchableError as e:
    raise newConfigError( 
      &"Failed to parse KDL config '{filepath}': {e.msg}")
