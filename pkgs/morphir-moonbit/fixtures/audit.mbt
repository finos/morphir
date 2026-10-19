///|
/// Compile every claimed SDK adapter and its scalar specializations.
pub fn acceptance_library() -> @ir.IRFile raise {
  let file = pricing()
  guard file.distribution is Library(package_name, dependencies, def) else {
    abort("fixture")
  }
  let modules = def.modules.copy()
  let int = scalar("morphir/SDK:basics#int")
  let int32 = scalar("morphir/SDK:int#int-32")
  let maybe_int32 = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [int32],
  )
  let dec = scalar("morphir/SDK:decimal#decimal")
  let bool = scalar("morphir/SDK:basics#bool")
  let float = scalar("morphir/SDK:basics#float")
  let text = scalar("morphir/SDK:string#string")
  let character = scalar("morphir/SDK:char#char")
  let list_int = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:list#list"),
    [int],
  )
  let maybe_int = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [int],
  )
  let maybe_dec = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [dec],
  )
  let list_text = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:list#list"),
    [text],
  )
  let list_character = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:list#list"),
    [character],
  )
  let maybe_float = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [float],
  )
  let maybe_pair = @ir.Type::Reference(
    ta(),
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [@ir.Type::Tuple(ta(), [character, text])],
  )
  let rows = [
    (
      "string-all",
      "morphir/SDK:string#all",
      arrow(arrow(character, bool), arrow(text, bool)),
    ),
    (
      "string-any",
      "morphir/SDK:string#any",
      arrow(arrow(character, bool), arrow(text, bool)),
    ),
    (
      "string-append",
      "morphir/SDK:string#append",
      arrow(text, arrow(text, text)),
    ),
    ("string-concat", "morphir/SDK:string#concat", arrow(list_text, text)),
    (
      "string-cons",
      "morphir/SDK:string#cons",
      arrow(character, arrow(text, text)),
    ),
    (
      "string-contains",
      "morphir/SDK:string#contains",
      arrow(text, arrow(text, bool)),
    ),
    (
      "string-drop-left",
      "morphir/SDK:string#drop-left",
      arrow(int, arrow(text, text)),
    ),
    (
      "string-drop-right",
      "morphir/SDK:string#drop-right",
      arrow(int, arrow(text, text)),
    ),
    (
      "string-ends-with",
      "morphir/SDK:string#ends-with",
      arrow(text, arrow(text, bool)),
    ),
    (
      "string-filter",
      "morphir/SDK:string#filter",
      arrow(arrow(character, bool), arrow(text, text)),
    ),
    (
      "string-foldl",
      "morphir/SDK:string#foldl",
      arrow(arrow(character, arrow(text, text)), arrow(text, arrow(text, text))),
    ),
    (
      "string-foldr",
      "morphir/SDK:string#foldr",
      arrow(arrow(character, arrow(text, text)), arrow(text, arrow(text, text))),
    ),
    ("string-from-char", "morphir/SDK:string#from-char", arrow(character, text)),
    ("string-from-float", "morphir/SDK:string#from-float", arrow(float, text)),
    ("string-from-int", "morphir/SDK:string#from-int", arrow(int, text)),
    (
      "string-from-list",
      "morphir/SDK:string#from-list",
      arrow(list_character, text),
    ),
    (
      "string-indexes",
      "morphir/SDK:string#indexes",
      arrow(text, arrow(text, list_int)),
    ),
    (
      "string-indices",
      "morphir/SDK:string#indices",
      arrow(text, arrow(text, list_int)),
    ),
    ("string-is-empty", "morphir/SDK:string#is-empty", arrow(text, bool)),
    (
      "string-join",
      "morphir/SDK:string#join",
      arrow(text, arrow(list_text, text)),
    ),
    ("string-left", "morphir/SDK:string#left", arrow(int, arrow(text, text))),
    ("string-length", "morphir/SDK:string#length", arrow(text, int)),
    ("string-lines", "morphir/SDK:string#lines", arrow(text, list_text)),
    (
      "string-map",
      "morphir/SDK:string#map",
      arrow(arrow(character, character), arrow(text, text)),
    ),
    (
      "string-pad",
      "morphir/SDK:string#pad",
      arrow(int, arrow(character, arrow(text, text))),
    ),
    (
      "string-pad-left",
      "morphir/SDK:string#pad-left",
      arrow(int, arrow(character, arrow(text, text))),
    ),
    (
      "string-pad-right",
      "morphir/SDK:string#pad-right",
      arrow(int, arrow(character, arrow(text, text))),
    ),
    (
      "string-repeat",
      "morphir/SDK:string#repeat",
      arrow(int, arrow(text, text)),
    ),
    (
      "string-replace",
      "morphir/SDK:string#replace",
      arrow(text, arrow(text, arrow(text, text))),
    ),
    ("string-reverse", "morphir/SDK:string#reverse", arrow(text, text)),
    ("string-right", "morphir/SDK:string#right", arrow(int, arrow(text, text))),
    (
      "string-slice",
      "morphir/SDK:string#slice",
      arrow(int, arrow(int, arrow(text, text))),
    ),
    (
      "string-split",
      "morphir/SDK:string#split",
      arrow(text, arrow(text, list_text)),
    ),
    (
      "string-starts-with",
      "morphir/SDK:string#starts-with",
      arrow(text, arrow(text, bool)),
    ),
    ("string-to-float", "morphir/SDK:string#to-float", arrow(text, maybe_float)),
    ("string-to-int", "morphir/SDK:string#to-int", arrow(text, maybe_int)),
    (
      "string-to-list",
      "morphir/SDK:string#to-list",
      arrow(text, list_character),
    ),
    ("string-to-lower", "morphir/SDK:string#to-lower", arrow(text, text)),
    ("string-to-upper", "morphir/SDK:string#to-upper", arrow(text, text)),
    ("string-trim", "morphir/SDK:string#trim", arrow(text, text)),
    ("string-trim-left", "morphir/SDK:string#trim-left", arrow(text, text)),
    ("string-trim-right", "morphir/SDK:string#trim-right", arrow(text, text)),
    ("string-uncons", "morphir/SDK:string#uncons", arrow(text, maybe_pair)),
    ("string-words", "morphir/SDK:string#words", arrow(text, list_text)),
    ("int-to-int32", "morphir/SDK:int#to-int-32", arrow(int, maybe_int32)),
    ("int-from-int32", "morphir/SDK:int#from-int-32", arrow(int32, int)),
    ("char-to-upper", "morphir/SDK:char#to-upper", arrow(character, character)),
    ("basics-add", "morphir/SDK:basics#add", arrow(int, arrow(int, int))),
    (
      "basics-subtract",
      "morphir/SDK:basics#subtract",
      arrow(int, arrow(int, int)),
    ),
    (
      "basics-multiply",
      "morphir/SDK:basics#multiply",
      arrow(int, arrow(int, int)),
    ),
    (
      "basics-divide",
      "morphir/SDK:basics#divide",
      arrow(float, arrow(float, float)),
    ),
    (
      "basics-integer-divide",
      "morphir/SDK:basics#integer-divide",
      arrow(int, arrow(int, int)),
    ),
    ("basics-power", "morphir/SDK:basics#power", arrow(int, arrow(int, int))),
    (
      "basics-power-float",
      "morphir/SDK:basics#power",
      arrow(float, arrow(float, float)),
    ),
    ("basics-to-float", "morphir/SDK:basics#to-float", arrow(int, float)),
    ("basics-sqrt", "morphir/SDK:basics#sqrt", arrow(float, float)),
    ("basics-sin", "morphir/SDK:basics#sin", arrow(float, float)),
    ("basics-cos", "morphir/SDK:basics#cos", arrow(float, float)),
    ("basics-round", "morphir/SDK:basics#round", arrow(float, int)),
    ("basics-floor", "morphir/SDK:basics#floor", arrow(float, int)),
    ("basics-ceiling", "morphir/SDK:basics#ceiling", arrow(float, int)),
    ("basics-truncate", "morphir/SDK:basics#truncate", arrow(float, int)),
    ("basics-mod-by", "morphir/SDK:basics#mod-by", arrow(int, arrow(int, int))),
    (
      "basics-remainder-by",
      "morphir/SDK:basics#remainder-by",
      arrow(int, arrow(int, int)),
    ),
    ("basics-negate", "morphir/SDK:basics#negate", arrow(int, int)),
    ("basics-abs", "morphir/SDK:basics#abs", arrow(int, int)),
    ("basics-equal", "morphir/SDK:basics#equal", arrow(int, arrow(int, bool))),
    (
      "basics-not-equal",
      "morphir/SDK:basics#not-equal",
      arrow(int, arrow(int, bool)),
    ),
    (
      "basics-less-than",
      "morphir/SDK:basics#less-than",
      arrow(int, arrow(int, bool)),
    ),
    (
      "basics-greater-than",
      "morphir/SDK:basics#greater-than",
      arrow(int, arrow(int, bool)),
    ),
    (
      "basics-less-than-or-equal",
      "morphir/SDK:basics#less-than-or-equal",
      arrow(int, arrow(int, bool)),
    ),
    (
      "basics-greater-than-or-equal",
      "morphir/SDK:basics#greater-than-or-equal",
      arrow(int, arrow(int, bool)),
    ),
    ("basics-not", "morphir/SDK:basics#not", arrow(bool, bool)),
    ("basics-and", "morphir/SDK:basics#and", arrow(bool, arrow(bool, bool))),
    ("basics-or", "morphir/SDK:basics#or", arrow(bool, arrow(bool, bool))),
    ("basics-xor", "morphir/SDK:basics#xor", arrow(bool, arrow(bool, bool))),
    ("basics-identity", "morphir/SDK:basics#identity", arrow(int, int)),
    ("basics-always", "morphir/SDK:basics#always", arrow(int, arrow(bool, int))),
    (
      "list-map",
      "morphir/SDK:list#map",
      arrow(arrow(int, int), arrow(list_int, list_int)),
    ),
    (
      "list-foldl",
      "morphir/SDK:list#foldl",
      arrow(arrow(int, arrow(int, int)), arrow(int, arrow(list_int, int))),
    ),
    (
      "list-foldr",
      "morphir/SDK:list#foldr",
      arrow(arrow(int, arrow(int, int)), arrow(int, arrow(list_int, int))),
    ),
    (
      "list-filter",
      "morphir/SDK:list#filter",
      arrow(arrow(int, bool), arrow(list_int, list_int)),
    ),
    ("list-length", "morphir/SDK:list#length", arrow(list_int, int)),
    ("list-reverse", "morphir/SDK:list#reverse", arrow(list_int, list_int)),
    ("list-sum", "morphir/SDK:list#sum", arrow(list_int, int)),
    ("list-product", "morphir/SDK:list#product", arrow(list_int, int)),
    (
      "list-append",
      "morphir/SDK:list#append",
      arrow(list_int, arrow(list_int, list_int)),
    ),
    (
      "maybe-map",
      "morphir/SDK:maybe#map",
      arrow(arrow(int, int), arrow(maybe_int, maybe_int)),
    ),
    (
      "maybe-with-default",
      "morphir/SDK:maybe#with-default",
      arrow(int, arrow(maybe_int, int)),
    ),
    ("decimal-from-int", "morphir/SDK:decimal#from-int", arrow(int, dec)),
    ("decimal-add", "morphir/SDK:decimal#add", arrow(dec, arrow(dec, dec))),
    ("decimal-sub", "morphir/SDK:decimal#sub", arrow(dec, arrow(dec, dec))),
    ("decimal-negate", "morphir/SDK:decimal#negate", arrow(dec, dec)),
    ("decimal-mul", "morphir/SDK:decimal#mul", arrow(dec, arrow(dec, dec))),
    (
      "decimal-div",
      "morphir/SDK:decimal#div",
      arrow(dec, arrow(dec, maybe_dec)),
    ),
    ("decimal-truncate", "morphir/SDK:decimal#truncate", arrow(dec, dec)),
    ("decimal-round", "morphir/SDK:decimal#round", arrow(dec, dec)),
    ("decimal-gt", "morphir/SDK:decimal#gt", arrow(dec, arrow(dec, bool))),
    ("decimal-gte", "morphir/SDK:decimal#gte", arrow(dec, arrow(dec, bool))),
    ("decimal-eq", "morphir/SDK:decimal#eq", arrow(dec, arrow(dec, bool))),
    ("decimal-neq", "morphir/SDK:decimal#neq", arrow(dec, arrow(dec, bool))),
    ("decimal-lt", "morphir/SDK:decimal#lt", arrow(dec, arrow(dec, bool))),
    ("decimal-lte", "morphir/SDK:decimal#lte", arrow(dec, arrow(dec, bool))),
    ("decimal-abs", "morphir/SDK:decimal#abs", arrow(dec, dec)),
    ("decimal-zero", "morphir/SDK:decimal#zero", dec),
    ("decimal-one", "morphir/SDK:decimal#one", dec),
    ("decimal-minus-one", "morphir/SDK:decimal#minus-one", dec),
    (
      "basics-equal-float",
      "morphir/SDK:basics#equal",
      arrow(float, arrow(float, bool)),
    ),
    (
      "basics-not-equal-float",
      "morphir/SDK:basics#not-equal",
      arrow(float, arrow(float, bool)),
    ),
    (
      "basics-less-than-float",
      "morphir/SDK:basics#less-than",
      arrow(float, arrow(float, bool)),
    ),
    (
      "basics-greater-than-float",
      "morphir/SDK:basics#greater-than",
      arrow(float, arrow(float, bool)),
    ),
    (
      "basics-less-than-or-equal-float",
      "morphir/SDK:basics#less-than-or-equal",
      arrow(float, arrow(float, bool)),
    ),
    (
      "basics-greater-than-or-equal-float",
      "morphir/SDK:basics#greater-than-or-equal",
      arrow(float, arrow(float, bool)),
    ),
    (
      "basics-equal-text",
      "morphir/SDK:basics#equal",
      arrow(text, arrow(text, bool)),
    ),
    (
      "basics-not-equal-text",
      "morphir/SDK:basics#not-equal",
      arrow(text, arrow(text, bool)),
    ),
    (
      "basics-less-than-text",
      "morphir/SDK:basics#less-than",
      arrow(text, arrow(text, bool)),
    ),
    (
      "basics-greater-than-text",
      "morphir/SDK:basics#greater-than",
      arrow(text, arrow(text, bool)),
    ),
    (
      "basics-less-than-or-equal-text",
      "morphir/SDK:basics#less-than-or-equal",
      arrow(text, arrow(text, bool)),
    ),
    (
      "basics-greater-than-or-equal-text",
      "morphir/SDK:basics#greater-than-or-equal",
      arrow(text, arrow(text, bool)),
    ),
    (
      "basics-equal-character",
      "morphir/SDK:basics#equal",
      arrow(character, arrow(character, bool)),
    ),
    (
      "basics-not-equal-character",
      "morphir/SDK:basics#not-equal",
      arrow(character, arrow(character, bool)),
    ),
    (
      "basics-less-than-character",
      "morphir/SDK:basics#less-than",
      arrow(character, arrow(character, bool)),
    ),
    (
      "basics-greater-than-character",
      "morphir/SDK:basics#greater-than",
      arrow(character, arrow(character, bool)),
    ),
    (
      "basics-less-than-or-equal-character",
      "morphir/SDK:basics#less-than-or-equal",
      arrow(character, arrow(character, bool)),
    ),
    (
      "basics-greater-than-or-equal-character",
      "morphir/SDK:basics#greater-than-or-equal",
      arrow(character, arrow(character, bool)),
    ),
    (
      "basics-add-float",
      "morphir/SDK:basics#add",
      arrow(float, arrow(float, float)),
    ),
    (
      "basics-subtract-float",
      "morphir/SDK:basics#subtract",
      arrow(float, arrow(float, float)),
    ),
    (
      "basics-multiply-float",
      "morphir/SDK:basics#multiply",
      arrow(float, arrow(float, float)),
    ),
    ("basics-negate-float", "morphir/SDK:basics#negate", arrow(float, float)),
    ("basics-abs-float", "morphir/SDK:basics#abs", arrow(float, float)),
    (
      "basics-identity-function",
      "morphir/SDK:basics#identity",
      arrow(arrow(int, int), arrow(int, int)),
    ),
  ]
  let values = Map([])
  for (local_name, sdk_name, signature) in rows {
    values[@ir.Name::parse(local_name)] = definition(
      signature,
      ref_value(sdk_name, signature),
    )
  }
  modules[@ir.Path::parse("audit")] = {
    access: @ir.Access::Public,
    value: { types: Map([]), values, doc: None, },
  }
  // A private closed record containing a private nominal type must still build.
  let path = @ir.Path::parse("internal")
  let internal = modules[path]
  let hidden = scalar("pricing:internal#hidden-type")
  let field = @ir.Name::parse("hidden")
  let shape = @ir.Type::Record(ta(), Map::from_array([(field, hidden)]))
  let hidden_case = @ir.Value::Constructor(
    { ..attrs(), inferred_type: Some(hidden), },
    @ir.FQName::parse("pricing:internal#hidden-case"),
  )
  let internal_values = internal.value.values.copy()
  internal_values[@ir.Name::parse("hidden-record")] = definition(
    shape,
    @ir.Value::Record(
      { ..attrs(), inferred_type: Some(shape), },
      Map::from_array([(field, hidden_case)]),
    ),
    access=@ir.Access::Private,
  )
  let internal_types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ] = Map::from_array([
    (
      @ir.Name::parse("hidden-type"),
      {
        access: @ir.Access::Private,
        value: {
          doc: None,
          value: @ir.TypeDefinition::CustomTypeDefinition([], {
            access: @ir.Access::Private,
            value: Map::from_array([(@ir.Name::parse("hidden-case"), [])]),
          }),
        },
      },
    ),
  ])
  modules[path] = {
    ..internal,
    value: { ..internal.value, values: internal_values, types: internal_types, },
  }
  @ir.IRFile::new(
    @ir.Distribution::Library(package_name, dependencies, { modules, }),
  )
}
