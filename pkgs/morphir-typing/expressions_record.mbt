///|
/// A record literal is closed.
fn Infer::value_record(
  self : Infer,
  fields : Map[@ir.Name, @ir.Value],
  path : String,
) -> Ty raise Located {
  Rec(self.field_types(fields, path), None)
}

///|
/// The type of each field value, by canonical name. Each field is at `path_field`.
fn Infer::field_types(
  self : Infer,
  fields : Map[@ir.Name, @ir.Value],
  path : String,
) -> Map[String, Ty] raise Located {
  let out : Map[String, Ty] = Map([])
  for name, field in fields {
    out[name.to_canonical()] = self.value(
      field,
      @identities.path_field(path, name),
    )
  }
  out
}

///|
/// `record.name`: the record is `{ ρ | name : α }`, and the result is `α`.
fn Infer::value_field(
  self : Infer,
  record : @ir.Value,
  name : @ir.Name,
  path : String,
) -> Ty raise Located {
  let rt = self.value(record, @identities.path_record(path))
  let field = self.fresh()
  self.unify(
    path,
    Rec(Map([(name.to_canonical(), field)]), Some(self.fresh())),
    rt,
  )
  field
}

///|
/// `.name` is `{ ρ | name : α } -> α`.
fn Infer::value_field_function(self : Infer, name : @ir.Name) -> Ty {
  let field = self.fresh()
  Fun(Rec(Map([(name.to_canonical(), field)]), Some(self.fresh())), field)
}

///|
/// `{ record | fields }`: the record must have each field with the type of its new value. The result has the
/// type of the record.
fn Infer::value_update(
  self : Infer,
  record : @ir.Value,
  fields : Map[@ir.Name, @ir.Value],
  path : String,
) -> Ty raise Located {
  let rt = self.value(record, @identities.path_record(path))
  let updates = self.field_types(fields, path)
  self.unify(path, Rec(updates, Some(self.fresh())), rt)
  rt
}
