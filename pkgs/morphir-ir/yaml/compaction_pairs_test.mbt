///|
fn read_compaction_pair(
  files : Array[(String, String)],
  physical : String,
  package_name : String,
  module_name : String,
  kind : @yaml.TreeMemberKind,
  name : String,
  json : String,
) -> @yaml.TreeMemberBody raise {
  let tree = recording_tree(
    files.map(file => if file.0 == physical { (physical, json) } else { file }),
  )
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let package_name = @ir.Path::parse(package_name)
  let module_name = @ir.Path::parse(module_name)
  ignore(reader.members(package_name, module_name, limit=1))
  assert_true(
    tree.opens.all(path => !path.contains(".type.") && !path.contains(".value.")),
  )
  let result = reader.read_member(
    package_name,
    module_name,
    kind,
    @ir.Name::parse(name),
  ) catch {
    @wire.Invalid(code, detail) => {
      let form = if json.contains("\"$schema\"") {
        "compacted"
      } else {
        "plain"
      }
      fail(form + " " + code + ": " + detail)
    }
    error => raise error
  }
  assert_eq(
    tree.opens.filter(path => {
      path.contains(".type.") || path.contains(".value.")
    }),
    [physical],
  )
  result
}

///|
fn check_classic_body_pair(body : String) -> Unit raise {
  let name = "[\"account\",\"summary\",\"authorization\",\"and\",\"reconciliation\",\"amount\"]"
  let expression = body.replace_all(old="@name@", new=name)
  let template =
    #|{"formatVersion":"3.1.0","name":"order","def":{"access":"Public","value":{"doc":"","value":{"inputTypes":[],"outputType":["Unit",{}],"body":@body@}}}}
  let plain = template.replace_all(old="@body@", new=expression)
  let compacted = @wire.compact_names(plain)
  assert_true(compacted.compacted)
  assert_true(compacted.written.contains("[[{\"$name\":"))
  let physical = "pkg/acme/orders/domain/order.value.json"
  let before = read_compaction_pair(
    orders_v3_json(),
    physical,
    "acme/orders",
    "domain",
    ValueMember,
    "order",
    plain,
  )
  let after = read_compaction_pair(
    orders_v3_json(),
    physical,
    "acme/orders",
    "domain",
    ValueMember,
    "order",
    compacted.written,
  )
  guard before is V3ValueDefinition(expected) &&
    after is V3ValueDefinition(actual) else {
    fail("expected two classic value definitions")
  }
  assert_eq(actual, expected)
}

///|
test "compacted classic record field pairs survive selected reads" {
  let body =
    #|["Record",["Unit",{}],[[@name@,["Tuple",["Unit",{}],[["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@]]]]]]
  check_classic_body_pair(body)
}

///|
test "compacted classic record update field pairs survive selected reads" {
  let body =
    #|["UpdateRecord",["Unit",{}],["Variable",["Unit",{}],@name@],[[@name@,["Tuple",["Unit",{}],[["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@]]]]]]
  check_classic_body_pair(body)
}

///|
test "compacted classic recursive binding pairs survive selected reads" {
  let body =
    #|["LetRecursion",["Unit",{}],[[@name@,{"inputTypes":[],"outputType":["Unit",{}],"body":["Tuple",["Unit",{}],[["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@],["Variable",["Unit",{}],@name@]]]}]],["Variable",["Unit",{}],@name@]]
  check_classic_body_pair(body)
}

///|
test "compacted classic constructor pairs survive selected reads" {
  let name = "[\"account\",\"summary\",\"authorization\",\"and\",\"reconciliation\",\"amount\"]"
  let template =
    #|{"formatVersion":"3.1.0","name":"order","def":{"access":"Public","value":{"doc":"","value":["CustomTypeDefinition",[@name@],{"access":"Public","value":[[@name@,[[@name@,["Variable",{},@name@]],[["first"],["Variable",{},@name@]],[["second"],["Variable",{},@name@]]]]]}]}}}
  let plain = template.replace_all(old="@name@", new=name)
  let compacted = @wire.compact_names(plain)
  assert_true(compacted.compacted)
  assert_true(compacted.written.contains("[[{\"$name\":"))
  let physical = "pkg/acme/orders/domain/order.type.json"
  let before = read_compaction_pair(
    orders_v3_json(),
    physical,
    "acme/orders",
    "domain",
    TypeMember,
    "order",
    plain,
  )
  let after = read_compaction_pair(
    orders_v3_json(),
    physical,
    "acme/orders",
    "domain",
    TypeMember,
    "order",
    compacted.written,
  )
  guard before is V3TypeDefinition(expected) &&
    after is V3TypeDefinition(actual) else {
    fail("expected two classic type definitions")
  }
  assert_eq(actual, expected)
}

///|
test "compacted v4 constructor and parameter pairs survive selected reads" {
  let template =
    #|{"formatVersion":4,"name":"order","def":{"Public":{"CustomTypeDefinition":{"typeParams":["@name@"],"access":"Public","constructors":[["@name@",[["@name@",{"Variable":"@name@"}],["second",{"Variable":"@name@"}]]]]}}}}
  let plain = template.replace_all(
    old="@name@",
    new="authorization-and-reconciliation-amount".repeat(6),
  )
  let compacted = @wire.compact_names(plain)
  assert_true(compacted.compacted)
  assert_true(compacted.written.contains("\"constructors\":[[{\"$name\":"))
  let physical = "pkg/acme/orders/domain/order.type.json"
  let before = read_compaction_pair(
    orders_v4_json(),
    physical,
    "acme/orders",
    "domain",
    TypeMember,
    "order",
    plain,
  )
  let after = read_compaction_pair(
    orders_v4_json(),
    physical,
    "acme/orders",
    "domain",
    TypeMember,
    "order",
    compacted.written,
  )
  guard before is V4TypeDefinition(expected) &&
    after is V4TypeDefinition(actual) else {
    fail("expected two v4 type definitions")
  }
  assert_eq(actual, expected)
}

///|
test "compacted v4 specification input pairs preserve selected parameter order" {
  let template =
    #|{"formatVersion":4,"name":"add","spec":{"inputs":[["@name@","morphir/SDK:basics#int"],["second","morphir/SDK:basics#int"]],"output":"morphir/SDK:basics#int","annotations":[{"name":"acme/orders:domain#note","arguments":[{"name":"@name@","value":{"Variable":"@name@"}}]}]}}
  let name = "authorization-and-reconciliation-amount".repeat(6)
  let plain = template.replace_all(old="@name@", new=name)
  let compacted = @wire.compact_names(plain)
  assert_true(compacted.compacted)
  assert_true(compacted.written.contains("\"inputs\":[[{\"$name\":"))
  let physical = "deps/morphir/_sdk/@/basics/add.value.json"
  let before = read_compaction_pair(
    orders_v4_json(),
    physical,
    "morphir/SDK",
    "basics",
    ValueMember,
    "add",
    plain,
  )
  let after = read_compaction_pair(
    orders_v4_json(),
    physical,
    "morphir/SDK",
    "basics",
    ValueMember,
    "add",
    compacted.written,
  )
  guard before is V4ValueSpecification(expected) &&
    after is V4ValueSpecification(actual) else {
    fail("expected two v4 value specifications")
  }
  assert_eq(actual, expected)
  assert_eq(actual.value.inputs.map(input => input.0.to_canonical()), [
    name, "second",
  ])
}
