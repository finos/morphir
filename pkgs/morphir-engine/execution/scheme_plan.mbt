///|
/// Capability validation scope and timing. Existing compiled plans always remain strict.
/// AdmissionPolicy remains a source-compatible alias for existing consumers.
#alias(AdmissionPolicy)
pub(all) enum CapabilityPolicy {
  Strict
  Permissive
} derive(Eq, Debug)

///|
pub extend CapabilityPolicy with Eq::{equal, not_equal}

///|
pub extend CapabilityPolicy with @debug.Debug::{to_repr}

///|
pub(all) suberror SchemePlanError {
  // Historical public error constructor, retained for source compatibility.
  AdmissionInvalid(String)
}

///|
/// A validated Scheme call snapshot. No caller-owned arrays or maps are retained.
pub struct SchemePlan {
  priv source : Bytes
  priv unit_id : String
  priv suite : Bytes
  priv check_policy : CapabilityPolicy
  priv entries : Array[@protocol.PublicEntry]
  priv definitions : Array[@protocol.CustomType]
  priv limits : @data.Limits
}

///|
pub fn SchemePlan::policy(self : SchemePlan) -> CapabilityPolicy {
  self.check_policy
}

///|
/// Fresh observation only; editing it cannot change the validated declarations.
pub fn SchemePlan::boundary_json(self : SchemePlan) -> Json {
  scheme_boundary_json(self.entries, self.definitions)
}

///|
fn scheme_boundary_json(
  entries : Array[@protocol.PublicEntry],
  definitions : Array[@protocol.CustomType],
) -> Json {
  {
    "entries": entries.map(entry => {
      (
        {
          "name": entry.name,
          "inputs": entry.inputs.map(t => t.to_json()),
          "output": entry.output.to_json(),
        } : Json)
    }),
    "definitions": definitions.map(definition => {
      (
        {
          "name": definition.name,
          "constructors": definition.constructors.map(variant => {
            (
              {
                "name": variant.name,
                "inputs": variant.inputs.map(t => t.to_json()),
              } : Json)
          }),
        } : Json)
    }),
  }
}

///|
/// A separate interpreter plan. Strict selection retains the existing generator
/// gate; permissive selection never constructs a generated library or driver.
pub fn plan_scheme(
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  policy~ : CapabilityPolicy = Strict,
  limits~ : @data.Limits = @data.Limits::default(),
) -> SchemePlan raise {
  if policy is Strict {
    ignore(plan(unit, suite))
  }
  suite.validate()
  unit.validate(limits~)
  let registry = @data.Registry::new(limits~)
  let source = match registry.encode("ion-binary", unit) {
    Binary(bytes) => bytes
    Text(_) => raise AdmissionInvalid("execution.invalid_source")
  }
  let captured = registry.decode("ion-binary", {
    unit_id: unit.id,
    content: Binary(source),
  })
  let encoded_suite = suite.encode("json")
  let suite = @protocol.Suite::decode(encoded_suite, "json")
  let (entries, definitions) = selected_boundaries(captured.distribution, suite)
  @protocol.validate_invocations(suite, entries, definitions)
  if policy is Permissive {
    for entry in entries {
      ignore(
        @backend.selected_file(
          captured.distribution,
          @ir.FQName::parse(entry.name),
        ),
      ) catch {
        @backend.SelectedReferenceInvalid(code) => raise AdmissionInvalid(code)
        error => raise error
      }
    }
  }
  let selected = SchemePlan::{
    source,
    unit_id: captured.id,
    suite: encoded_suite,
    check_policy: policy,
    entries,
    definitions,
    limits,
  }
  // Descriptor count and name/dimension bounds constrain expansion before this
  // byte check, including repeated aliases. Callers only receive validated plans.
  if @utf8.encode(selected.boundary_json().stringify()).length() > 1048576 {
    raise AdmissionInvalid("execution.type_limit")
  }
  selected
}

///|
pub fn SchemePlan::validate_outputs(
  self : SchemePlan,
  values : Array[@protocol.Value],
) -> Unit raise {
  let suite = @protocol.Suite::decode(self.suite, "json")
  if values.length() != suite.calls.length() {
    raise AdmissionInvalid("execution.output_inventory")
  }
  for i, call in suite.calls {
    let entry = self.entries.filter(e => e.name == call.entry)[0]
    @protocol.validate_as(
      values[i],
      entry.output,
      self.definitions,
      output=true,
    )
    validate_sdk_boundary(values[i])
  }
}

///|
pub fn SchemePlan::evaluate(self : SchemePlan) -> Array[@protocol.Value] raise {
  let unit = @data.Registry::new(limits=self.limits).decode("ion-binary", {
    unit_id: self.unit_id,
    content: Binary(self.source),
  })
  let suite = @protocol.Suite::decode(self.suite, "json")
  let results = []
  for call in suite.calls {
    let entry = self.entries.filter(e => e.name == call.entry)[0]
    let runtime = @scheme.Runtime::new(limits={
      steps: 1000000,
      depth: 128,
      frames: 100000,
    })
    @backend.install(runtime, accelerators=false, model_errors=true)
    let result = try {
      let selected = if self.check_policy is Permissive {
        @backend.selected_file(unit.distribution, @ir.FQName::parse(call.entry))
      } else {
        unit.distribution
      }
      let value = @backend.run_file_in(
        runtime,
        selected,
        @ir.FQName::parse(call.entry),
        call.arguments.map(scheme_input),
      )
      scheme_output(value, entry.output, self.definitions, 0)
    } catch {
      @scheme.Domain(code, _) => @protocol.ModelError(code)
      @backend.SelectedReferenceInvalid(code) => raise AdmissionInvalid(code)
      error => raise error
    }
    @protocol.validate_as(result, entry.output, self.definitions, output=true)
    results.push(result)
  }
  self.validate_outputs(results)
  results
}

///|
fn selected_boundaries(
  file : @ir.IRFile,
  suite : @protocol.Suite,
) -> (Array[@protocol.PublicEntry], Array[@protocol.CustomType]) raise {
  guard file.distribution is Library(package_name, _, package_def) else {
    raise AdmissionInvalid("execution.unsupported_distribution")
  }
  let types : Map[String, SelectedType] = Map([])
  let constructor_names : Map[String, Bool] = Map([])
  for module_name, module_def in package_def.modules {
    for local_name, definition in module_def.value.types {
      let name : @ir.FQName = { package_name, module_name, local_name, }
      types[name.to_canonical()] = {
        definition: definition.value.value,
        public: module_def.access is Public && definition.access is Public,
        exposed: definition.access is Public,
        module_name,
      }
      if definition.value.value is CustomTypeDefinition(_, variants) {
        for local_name, _ in variants.value {
          let name : @ir.FQName = { package_name, module_name, local_name, }
          let key = name.to_canonical()
          if constructor_names.contains(key) {
            raise AdmissionInvalid("execution.ambiguous_identity")
          }
          constructor_names[key] = true
        }
      }
    }
  }
  let context = SelectedBoundary::{
    types,
    definitions: Map([]),
    nodes: Ref(0),
  }
  let entries : Array[@protocol.PublicEntry] = []
  for call in suite.calls {
    let name = @ir.FQName::parse(call.entry)
    guard name.package_name == package_name &&
      package_def.modules.get(name.module_name) is Some(module_def) &&
      module_def.access is Public &&
      module_def.value.values.get(name.local_name) is Some(definition) &&
      definition.access is Public &&
      definition.value.value.to_specification() is Some(specification) else {
      raise @protocol.Invalid("execution.entry_not_public_or_supported")
    }
    if !entries.any(entry => entry.name == call.entry) {
      if specification.inputs.length() > 64 {
        raise AdmissionInvalid("execution.type_limit")
      }
      entries.push(@protocol.PublicEntry::{
        name: call.entry,
        inputs: specification.inputs.map(p => {
          context.read(p.1, 0, [], name.module_name)
        }),
        output: context.read(specification.output, 0, [], name.module_name),
      })
    }
  }
  entries.sort_by(fn(a, b) { a.name.lexical_compare(b.name) })
  let names = context.definitions.keys().collect()
  names.sort_by(fn(a, b) { a.lexical_compare(b) })
  (entries, names.map(name => context.definitions[name]))
}

///|
/// Discover one complete public type boundary without compiling executable code.
/// This is an input-editor description, not permission to execute. A run must
/// still use plan_scheme_capabilities to validate its source, inputs and policy.
pub fn scheme_entry_boundary(
  file : @ir.IRFile,
  entry : String,
) -> (@protocol.PublicEntry, Array[@protocol.CustomType]) raise {
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [{ "id": "boundary", "entry": entry, "arguments": [] }],
  })
  let (entries, definitions) = selected_boundaries(file, suite)
  if @utf8.encode(scheme_boundary_json(entries, definitions).stringify()).length() >
    1048576 {
    raise AdmissionInvalid("execution.type_limit")
  }
  (entries[0], definitions)
}

///|
priv struct SelectedType {
  definition : @ir.TypeDefinition
  public : Bool
  exposed : Bool
  module_name : @ir.ModuleName
}

///|
priv struct SelectedBoundary {
  types : Map[String, SelectedType]
  definitions : Map[String, @protocol.CustomType]
  nodes : Ref[Int32]
}

///|
fn SelectedBoundary::count(self : SelectedBoundary) -> Unit raise {
  self.nodes.val += 1
  if self.nodes.val > 10000 {
    raise AdmissionInvalid("execution.type_limit")
  }
}

///|
fn selected_type_name(name : String) -> Unit raise {
  if name.length() == 0 || name.length() > 1024 {
    raise AdmissionInvalid("execution.type_limit")
  }
}

///|
fn SelectedBoundary::read(
  self : SelectedBoundary,
  t : @ir.Type,
  depth : Int32,
  aliases : Array[String],
  requester : @ir.ModuleName,
) -> @protocol.ValueType raise {
  self.count()
  if depth > 64 {
    raise AdmissionInvalid("execution.type_limit")
  }
  let attributes = match t {
    Variable(a, _)
    | Reference(a, _, _)
    | Tuple(a, _)
    | Union(a, _)
    | Record(a, _)
    | ExtensibleRecord(a, _, _)
    | Function(a, _, _)
    | Unit(a) => a
  }
  if !attributes.constraints.is_empty() {
    raise AdmissionInvalid("execution.unsupported_type")
  }
  fn child(t : @ir.Type) -> @protocol.ValueType raise {
    self.read(t, depth + 1, aliases, requester)
  }
  match t {
    Unit(_) => @protocol.Unit
    Function(_, _, _) => raise AdmissionInvalid("execution.boundary_function")
    Variable(_, _) | ExtensibleRecord(_, _, _) =>
      raise AdmissionInvalid("execution.unsupported_type")
    Union(_, _) => raise AdmissionInvalid("execution.unsupported_type")
    Tuple(_, items) => {
      if items.length() > 1024 {
        raise AdmissionInvalid("execution.type_limit")
      }
      if items.length() < 2 {
        raise AdmissionInvalid("execution.unsupported_type")
      }
      @protocol.Product(items.map(child))
    }
    Record(_, fields) => {
      if fields.length() > 1024 {
        raise AdmissionInvalid("execution.type_limit")
      }
      let names = fields.keys().collect()
      names.sort_by(fn(a, b) {
        a.to_canonical().lexical_compare(b.to_canonical())
      })
      @protocol.Record(
        names.map(name => {
          self.count()
          selected_type_name(name.to_canonical())
          (name.to_canonical(), child(fields[name]))
        }),
      )
    }
    Reference(_, name, arguments) => {
      let key = name.to_canonical()
      selected_type_name(key)
      match key {
        "morphir/SDK:list#list" if arguments.length() == 1 =>
          return @protocol.Sequence(child(arguments[0]))
        "morphir/SDK:maybe#maybe" if arguments.length() == 1 =>
          return @protocol.Optional(child(arguments[0]))
        "morphir/SDK:result#result" if arguments.length() == 2 =>
          return @protocol.Outcome(child(arguments[1]), child(arguments[0]))
        _ => ()
      }
      if !arguments.is_empty() {
        raise AdmissionInvalid("execution.unsupported_type")
      }
      match key {
        "morphir/SDK:int#int-32" => {
          self.definitions[key] = {
            name: key,
            constructors: [
              { name: "morphir/SDK:int#int32", inputs: [@protocol.Int], },
            ],
          }
          @protocol.Custom(key)
        }
        "morphir/SDK:basics#int" => @protocol.Int
        "morphir/SDK:basics#float" => @protocol.Float64
        "morphir/SDK:basics#bool" => @protocol.Bool
        "morphir/SDK:string#string" => @protocol.Text
        "morphir/SDK:char#char" => @protocol.Character
        "morphir/SDK:decimal#decimal" => @protocol.Decimal
        _ => {
          guard self.types.get(key) is Some(entry) else {
            raise AdmissionInvalid("execution.unresolved_custom_type")
          }
          if !entry.exposed && entry.module_name != requester {
            raise AdmissionInvalid("execution.constructor_visibility")
          }
          match entry.definition {
            TypeAliasDefinition(parameters, target) => {
              if !parameters.is_empty() || aliases.contains(key) {
                raise AdmissionInvalid("execution.unsupported_type")
              }
              self.read(target, depth + 1, aliases + [key], entry.module_name)
            }
            CustomTypeDefinition(parameters, variants) => {
              if !parameters.is_empty() {
                raise AdmissionInvalid("execution.unsupported_type")
              }
              if !entry.public || variants.access is Private {
                raise AdmissionInvalid("execution.constructor_visibility")
              }
              if !self.definitions.contains(key) {
                if self.definitions.length() >= 256 ||
                  variants.value.length() > 256 {
                  raise AdmissionInvalid("execution.type_limit")
                }
                self.count()
                self.definitions[key] = { name: key, constructors: [], }
                let names = variants.value.keys().collect()
                names.sort_by(fn(a, b) {
                  a.to_canonical().lexical_compare(b.to_canonical())
                })
                let constructors = names.map(local_name => {
                  self.count()
                  let fields = variants.value[local_name]
                  if fields.length() > 64 {
                    raise AdmissionInvalid("execution.type_limit")
                  }
                  let fq : @ir.FQName = { ..name, local_name, }
                  selected_type_name(fq.to_canonical())
                  @protocol.ConstructorType::{
                    name: fq.to_canonical(),
                    inputs: fields.map(p => {
                      self.read(p.1, 0, [], name.module_name)
                    }),
                  }
                })
                self.definitions[key] = { name: key, constructors, }
              }
              @protocol.Custom(key)
            }
            IncompleteTypeDefinition(_, _, _) =>
              raise AdmissionInvalid("execution.unsupported_type")
          }
        }
      }
    }
  }
}

///|
/// Return a newly decoded source snapshot. Editing it cannot change this plan.
pub fn SchemePlan::unit(self : SchemePlan) -> @data.IRUnit raise {
  @data.Registry::new(limits=self.limits).decode("ion-binary", {
    unit_id: self.unit_id,
    content: Binary(self.source),
  })
}

///|
/// Return a newly decoded invocation suite, independent of retained arguments.
pub fn SchemePlan::suite(self : SchemePlan) -> @protocol.Suite raise {
  @protocol.Suite::decode(self.suite, "json")
}
