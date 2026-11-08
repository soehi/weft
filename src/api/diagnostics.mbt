///|
fn diagnostic(
  code : String,
  stage : String,
  message : String,
  component~ : String? = None,
  port~ : String? = None,
  field~ : String? = None,
  detail~ : String? = None,
  related~ : Array[Location] = [],
) -> Diagnostic {
  {
    code,
    stage,
    message,
    location: { component, port, field, },
    related,
    detail,
  }
}

///|
fn field_path(loc : String, field : String) -> String {
  if field == "" {
    loc
  } else {
    loc + "." + field
  }
}

///|
fn manifest_diagnostic(e : @manifest.ManifestError) -> Diagnostic {
  let (code, field, component) = match e {
    @manifest.InvalidJson(_) => ("MANIFEST_JSON", "manifest", None)
    @manifest.MissingField(loc, f) =>
      ("MANIFEST_MISSING_FIELD", field_path(loc, f), None)
    @manifest.WrongType(loc, f, _) =>
      ("MANIFEST_FIELD_TYPE", field_path(loc, f), None)
    @manifest.DuplicateComponent(name) =>
      ("MANIFEST_DUPLICATE_COMPONENT", "components", Some(name))
    @manifest.InvalidPortRef(loc, _) => ("MANIFEST_PORT_REF", loc, None)
    @manifest.InvalidNumber(loc, f) =>
      ("MANIFEST_NUMBER", field_path(loc, f), None)
    @manifest.NegativeNumber(loc, f) =>
      ("MANIFEST_NEGATIVE_NUMBER", field_path(loc, f), None)
    @manifest.NumberOutOfRange(loc, f) =>
      ("MANIFEST_NUMBER_RANGE", field_path(loc, f), None)
    @manifest.UnknownField(loc, f) =>
      ("MANIFEST_UNKNOWN_FIELD", field_path(loc, f), None)
    @manifest.UnsupportedManifestVersion(_) =>
      ("MANIFEST_VERSION", "manifest.version", None)
  }
  diagnostic(code, "manifest", e.to_string(), field=Some(field), component~)
}

///|
fn plan_diagnostic(e : @plan.PlanError) -> Diagnostic {
  let message = e.to_string()
  match e {
    @plan.UnknownComponent(c) =>
      diagnostic("PLAN_UNKNOWN_COMPONENT", "plan", message, component=Some(c))
    @plan.UnknownPort(c, p) =>
      diagnostic(
        "PLAN_UNKNOWN_PORT",
        "plan",
        message,
        component=Some(c),
        port=Some(p),
      )
    @plan.PortKindMismatch(c, p, detail) =>
      diagnostic(
        "PLAN_PORT_KIND",
        "plan",
        message,
        component=Some(c),
        port=Some(p),
        detail=Some(detail),
      )
    @plan.Cycle(names) =>
      diagnostic(
        "PLAN_CYCLE",
        "plan",
        message,
        related=names.map(c => { component: Some(c), port: None, field: None, }),
      )
    @plan.SignatureMismatch(fc, fp, tc, tp, detail) =>
      diagnostic(
        "PLAN_TYPE_MISMATCH",
        "plan",
        message,
        component=Some(fc),
        port=Some(fp),
        detail=Some(detail),
        related=[{ component: Some(tc), port: Some(tp), field: None, }],
      )
    @plan.Unsupported(c, p, detail) =>
      diagnostic(
        "PLAN_UNSUPPORTED",
        "plan",
        message,
        component=Some(c),
        port=Some(p),
        detail=Some(detail),
      )
    @plan.DuplicateBinding(c, p, first, second) =>
      diagnostic(
        "PLAN_DUPLICATE_BINDING",
        "plan",
        message,
        component=Some(c),
        port=Some(p),
        detail=Some(first + " and " + second),
      )
    @plan.UnboundImport(c, p) =>
      diagnostic(
        "PLAN_UNBOUND_IMPORT",
        "plan",
        message,
        component=Some(c),
        port=Some(p),
      )
    @plan.Unflattenable(c, p) =>
      diagnostic("PLAN_ABI", "plan", message, component=Some(c), port=Some(p))
    @plan.InvalidManifest(detail) =>
      diagnostic("PLAN_INVALID_INPUT", "plan", message, detail=Some(detail))
  }
}
