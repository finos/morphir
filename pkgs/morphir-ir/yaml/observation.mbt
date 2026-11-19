///|
/// Normalized inventory data for an explicitly selected adapter. The caller
/// owns paging and provenance; these facts are not a kit verdict or receipt.
pub fn TreeModule::observation(self : TreeModule) -> Json {
  let fields = [
    ("package", @wire.text(self.package_name.to_canonical())),
    ("path", @wire.text(self.path.to_canonical())),
    ("role", tree_role_observation(self.role)),
    ("document", @wire.text(self.document)),
  ]
  if self.access is Some(access) {
    fields.push(
      (
        "access",
        @wire.text(
          match access {
            Public => "Public"
            Private => "Private"
          },
        ),
      ),
    )
  }
  @wire.obj(fields)
}

///|
fn tree_role_observation(role : TreeRole) -> Json {
  @wire.text(
    match role {
      Definition => "definition"
      Specification => "specification"
    },
  )
}

///|
fn tree_kind_observation(kind : TreeMemberKind) -> Json {
  @wire.text(
    match kind {
      TypeMember => "type"
      ValueMember => "value"
    },
  )
}

///|
pub fn TreeMember::observation(self : TreeMember) -> Json {
  @wire.obj([
    ("name", @wire.text(self.name.to_canonical())),
    ("kind", tree_kind_observation(self.kind)),
    ("role", tree_role_observation(self.role)),
    ("document", @wire.text(self.document)),
  ])
}

///|
/// A direct expression reference, not a dependency summary or evaluation.
/// Return the typed identity so an adapter never resolves a body reference
/// through an escaped filename or the homonymous type member.
pub fn TreeMemberBody::direct_value_reference(
  self : TreeMemberBody,
) -> @ir.FQName? {
  match self {
    V3ValueDefinition(definition) =>
      match definition.value.value.body {
        Reference(_, name) => Some(name)
        _ => None
      }
    V4ValueDefinition(definition) =>
      match definition.value.value {
        ExpressionBody(_, _, Reference(_, name)) => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
fn TreeMemberBody::observation_payload(self : TreeMemberBody) -> Json raise {
  let unit : (Unit) -> Json raise = value => @wire.write_unit(value)
  let typed = fn(value) raise { @v3_json.write_type(value, unit) }
  match self {
    V3TypeDefinition(value) =>
      @v3_json.write_access(value, documented => {
        @v3_json.write_documented(documented, body => {
          @v3_json.write_type_definition(body, unit)
        })
      })
    V3ValueDefinition(value) =>
      @v3_json.write_access(value, documented => {
        @v3_json.write_documented(documented, body => {
          @v3_json.write_value_definition(body, unit, typed)
        })
      })
    V3TypeSpecification(value) =>
      @v3_json.write_documented(value, body => {
        @v3_json.write_type_specification(body, unit)
      })
    V3ValueSpecification(value) =>
      @v3_json.write_documented(value, body => {
        @v3_json.write_value_specification(body, unit)
      })
    V4TypeDefinition(value) =>
      @v4_json.write_access(value, documented => {
        @v4_json.write_documented(documented, @v4_json.write_type_definition)
      })
    V4ValueDefinition(value) =>
      @v4_json.write_access(value, documented => {
        @v4_json.write_documented(documented, @v4_json.write_definition)
      })
    V4TypeSpecification(value) =>
      @v4_json.write_documented(value, @v4_json.write_type_specification)
    V4ValueSpecification(value) =>
      @v4_json.write_documented(value, @v4_json.write_value_specification)
  }
}

///|
/// Read just the selected typed member under the tree's existing admission
/// limits. Payloads use that version's codec, including classic attributes.
/// Optional facts describe only a direct type reference, expression reference
/// or integer literal. Their absence makes no claim about nested expressions.
pub fn BoundedTree::observe_member(
  self : BoundedTree,
  package_name : @ir.Path,
  module_name : @ir.Path,
  kind : TreeMemberKind,
  name : @ir.Name,
) -> Json raise {
  let (body, document) = self.read_member_document(
    package_name, module_name, kind, name,
  )
  let role = match body {
    V3TypeDefinition(_)
    | V3ValueDefinition(_)
    | V4TypeDefinition(_)
    | V4ValueDefinition(_) => Definition
    _ => Specification
  }
  let fields = [
    ("package", @wire.text(package_name.to_canonical())),
    ("module", @wire.text(module_name.to_canonical())),
    ("name", @wire.text(name.to_canonical())),
    ("kind", tree_kind_observation(kind)),
    ("role", tree_role_observation(role)),
    ("document", @wire.text(document)),
    ("payload", body.observation_payload()),
  ]
  if body.direct_value_reference() is Some(reference) {
    fields.push(("reference", @wire.text(reference.to_canonical())))
    fields.push(("referenceKind", tree_kind_observation(ValueMember)))
  }
  match body {
    V3ValueDefinition(definition) => {
      let value = definition.value.value
      if value.output_type is Reference(_, output, _) {
        fields.push(("outputType", @wire.text(output.to_canonical())))
      }
      if value.body is Literal(_, WholeNumberLiteral(text)) {
        fields.push(("integerLiteral", @wire.number(text)))
      }
    }
    V4ValueDefinition(definition) =>
      if definition.value.value is ExpressionBody(_, output, expression) {
        if output is Reference(_, name, _) {
          fields.push(("outputType", @wire.text(name.to_canonical())))
        }
        if expression is Literal(_, IntegerLiteral(text)) {
          fields.push(("integerLiteral", @wire.number(text)))
        }
      }
    _ => ()
  }
  self.check_revision()
  @wire.obj(fields)
}

///|
/// Describe the admitted manifest without opening further documents.
pub fn BoundedTree::observation(self : BoundedTree) -> Json raise {
  self.check_revision()
  @wire.obj([
    ("irVersion", @wire.text(self.manifest.version.to_release_string())),
    ("distribution", @wire.text(self.manifest.kind.wire_name())),
    ("package", @wire.text(self.manifest.package_name.to_canonical())),
    ("pathBudget", Json::number(self.manifest.path_budget)),
    (
      "dependencies",
      Json::array(
        self.dependencies.map(path => @wire.text(path.to_canonical())),
      ),
    ),
  ])
}
