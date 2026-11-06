// Planner-facing interface model.
//
// A component exposes a set of *ports*. A port is either a plain function or an
// interface (instance) containing functions. Wires address `component.port`,
// where a port name is either `f` (plain func) or `iface.f` (function inside an
// interface). We normalize both shapes into `Port` with a flat function list so
// the planner never has to special-case them again.

///|
/// A single function signature, kept together with the type table it indexes.
/// The table travels with the signature so canonical flattening can be done
/// without reaching back into the source package.
pub(all) struct FuncSig {
  name : String
  is_async : Bool
  params : Array[ParamSig]
  result : ValTy?
}

///|
pub(all) struct ParamSig {
  name : String
  ty : ValTy
}

///|
/// A value type mirroring the component-model value types. Indices refer to
/// `Iface::types`. Primitives are inlined.
pub(all) enum ValTy {
  Bool
  S8
  U8
  S16
  U16
  S32
  U32
  S64
  U64
  F32
  F64
  Char
  String
  ErrorContext
  Index(Int)
} derive(Debug, Eq)

///|
pub extend ValTy with Debug::{to_repr}

///|
pub extend ValTy with Eq::{not_equal, equal}

///|
pub extend ValTy with Show::{to_string, output}

///|
pub impl Show for ValTy with fn output(self, logger) {
  let name = match self {
    Bool => "Bool"
    S8 => "S8"
    U8 => "U8"
    S16 => "S16"
    U16 => "U16"
    S32 => "S32"
    U32 => "U32"
    S64 => "S64"
    U64 => "U64"
    F32 => "F32"
    F64 => "F64"
    Char => "Char"
    String => "String"
    ErrorContext => "ErrorContext"
    Index(i) => "Index(\{i})"
  }
  logger.write_string(name)
}

///|
/// A resolved type definition. `None` means "not a value type" (e.g. a scalar
/// or alias that was already inlined); indices that are not value types are
/// never referenced from `ValTy::Index` by construction.
pub(all) enum TypeDef {
  Func(FuncSig)
  Record(Array[ParamSig])
  List(ValTy)
  FixedList(ValTy, Int)
  MapType(ValTy, ValTy)
  Tuple(Array[ValTy])
  Option(ValTy)
  Result(ValTy?, ValTy?)
  Variant(Array[CaseSig])
  Flags(Array[String])
  Enum(Array[String])
  Own(Int)
  Borrow(Int)
  Future(ValTy?)
  Stream(ValTy?)
  Resource
}

///|
pub(all) struct CaseSig {
  label : String
  payload : ValTy?
}

///|
/// One addressable port of a component.
pub(all) enum Port {
  /// A top-level function export/import, addressed as `<comp>.<name>`.
  Func(FuncSig)
  /// An interface export/import, addressed as `<comp>.<iface>.<func>`.
  Interface(String, Array[FuncSig])
}

///|
/// A named port entry (name is the first address segment).
pub(all) struct PortEntry {
  name : String
  port : Port
}

///|
/// Everything the planner needs to know about one component.
pub(all) struct Iface {
  /// Component name from the manifest.
  name : String
  /// Declared artifact path, carried through for the emitted plan.
  path : String
  /// Exports, sorted by name for determinism.
  exports : Array[PortEntry]
  /// Imports, sorted by name for determinism.
  imports : Array[PortEntry]
  /// Type table backing every `ValTy::Index` in this interface.
  types : Array[TypeDef?]
}

///|
/// A decoded component: the manifest declaration plus its interface.
pub(all) struct Component {
  decl : @manifest.ComponentDecl
  iface : Iface
}

///|
/// IR failures during decoding. Always names the component.
pub(all) suberror IrError {
  DecodeFailed(String, String)
  UnsupportedType(String)
}

///|
pub extend IrError with Show::{output}

///|
pub impl Show for IrError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn IrError::to_string(self : IrError) -> String {
  match self {
    DecodeFailed(comp, msg) => "ir: cannot decode `\{comp}`: \{msg}"
    UnsupportedType(comp) => "ir: `\{comp}` uses a value type this planner cannot express"
  }
}