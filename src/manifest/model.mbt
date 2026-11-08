// Manifest data model and its error type.
//
// A manifest is deliberately small: a flat list of named components, a list of
// directed wires, and resource limits. Anything that requires reading a binary
// (interface extraction, signature checks) belongs to the planner, not here.

///|
/// One component entry. `path` is only an opaque label for the planner; the
/// bytes are supplied separately so the manifest stays filesystem-free.
pub(all) struct ComponentDecl {
  name : String
  path : String
}

///|
/// One directed wire, addressed as `<component>.<export>` -> `<component>.<import>`.
pub(all) struct WireDecl {
  from_component : String
  from_port : String
  to_component : String
  to_port : String
}

///|
/// Resource limits attached to the plan. All fields are optional; absent means
/// "unconstrained" and is reported as such in the emitted plan.
pub(all) struct ResourceLimits {
  max_memory_pages : Int?
  quota : Int?
}

///|
/// A parsed, not-yet-validated manifest.
pub(all) struct Manifest {
  version : String
  components : Array[ComponentDecl]
  wires : Array[WireDecl]
  resources : ResourceLimits
}

///|
/// Structured manifest failure. Every variant carries enough context to name
/// the offending entry, so a plan never fails with a bare "invalid".
pub(all) suberror ManifestError {
  InvalidJson(String)
  MissingField(String, String)
  WrongType(String, String, String)
  DuplicateComponent(String)
  InvalidPortRef(String, String)
  InvalidNumber(String, String)
  NegativeNumber(String, String)
  UnsupportedManifestVersion(String)
  UnknownField(String, String)
  NumberOutOfRange(String, String)
}

///|
pub extend ManifestError with Show::{output}

///|
pub impl Show for ManifestError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn ManifestError::to_string(self : ManifestError) -> String {
  match self {
    InvalidJson(msg) => "manifest: invalid JSON: \{msg}"
    MissingField(loc, field) => "manifest: \{loc} is missing field `\{field}`"
    WrongType(loc, field, got) =>
      if field == "" {
        "manifest: \{loc} must be \{got}"
      } else {
        "manifest: \{loc} field `\{field}` must be \{got}"
      }
    DuplicateComponent(name) => "manifest: duplicate component name `\{name}`"
    InvalidPortRef(loc, got) =>
      "manifest: \{loc} must be `<component>.<port>`, got `\{got}`"
    InvalidNumber(loc, field) =>
      "manifest: \{loc} field `\{field}` must be an integer"
    NegativeNumber(loc, field) =>
      "manifest: \{loc} field `\{field}` must not be negative"
    UnknownField(loc, field) => "manifest: \{loc} has unknown field `\{field}`"
    NumberOutOfRange(loc, field) => "manifest: \{loc} field `\{field}` exceeds 2147483647"
    UnsupportedManifestVersion(v) =>
      "manifest: unsupported version `\{v}` (expected 0.1.0 or 0.2.0)"
  }
}