///|
pub const REVISION : String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

///|
fn attributes() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn value_attributes() -> @ir.ValueAttributes {
  { source: None, inferred_type: None, extensions: Map([]), }
}

///|
fn scalar(name : String) -> @ir.Type raise {
  @ir.Type::Reference(attributes(), @ir.FQName::parse(name), [])
}

///|
fn library(
  package_name : String,
  module_name : String,
  values : Array[(String, @ir.Type, @ir.Value)],
) -> @ir.IRFile raise {
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse(package_name), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse(module_name),
          {
            access: @ir.Access::Public,
            value: {
              doc: None,
              types: Map([]),
              values: Map::from_array(
                values.map(v => {
                  (
                    @ir.Name::parse(v.0),
                    {
                      access: @ir.Access::Public,
                      value: {
                        doc: None,
                        value: @ir.ValueDefinition::ExpressionBody([], v.1, v.2),
                      },
                    },
                  )
                }),
              ),
            },
          },
        ),
      ]),
    }),
  )
}

///|
pub fn input() -> @ir.IRFile raise {
  let boolean = scalar("morphir/SDK:basics#bool")
  library("example", "main", [
    (
      "ready",
      boolean,
      @ir.Value::Literal(value_attributes(), @ir.Literal::BoolLiteral(true)),
    ),
    (
      "wanted",
      boolean,
      @ir.Value::Literal(value_attributes(), @ir.Literal::BoolLiteral(false)),
    ),
    (
      "copy",
      boolean,
      @ir.Value::Reference(
        value_attributes(),
        @ir.FQName::parse("example:main#ready"),
      ),
    ),
  ])
}

///|
/// A semantic projection supplied by a simulated test host. This fixture does
/// not authenticate signatures or claim a released upstream provider.
pub fn provider() -> @metadata.RestoredLibrary raise {
  let string = scalar("morphir/SDK:string#string")
  let dictionary = @ir.Type::Reference(
    attributes(),
    @ir.FQName::parse("morphir/SDK:dict#dict"),
    [string, string],
  )
  let names = [@ir.Name::parse("frontend"), @ir.Name::parse("backend")]
  let output = @ir.Type::Record(
    attributes(),
    Map::from_array(names.map(n => (n, dictionary))),
  )
  let body = @ir.Value::Record(
    value_attributes(),
    Map::from_array(
      names.map(n => {
        (
          n,
          @ir.Value::Reference(
            value_attributes(),
            @ir.FQName::parse("morphir/SDK:dict#empty"),
          ),
        )
      }),
    ),
  )
  {
    core: library("morphir/naming", "naming", [("target-names", output, body)]),
    format: "4.1.0",
    revision: REVISION,
    document: "morphir://ir/pkg/morphir/naming?format=4.1.0&rev=sha256:" +
    REVISION +
    "#/distribution",
    document_metadata: @ion_text.read_ion(
      "{'@context':{'@vocab':\"morphir://ir/pkg/morphir/metadata?format=4.1.0#/module/schema/value/\"},'@graph':[{'@id':\"" +
      @metadata.TARGET_NAMES_PREDICATE +
      "\",'subject-role':\"ValueDefinition\",'object-form':\"data\",interpreter:\"target-name-language-ids\"}]}",
    ),
  }
}

///|
pub fn capabilities() -> @metadata.Capabilities {
  {
    restore_library: Some(fn(_) raise { provider() }),
    load_context: None,
    target_names_interpreter: true,
    provider_observer: @metadata.ProviderObserver::noop(),
  }
}

///|
pub fn adapter(
  graph : String,
  context? : String = "{targetNames:{'@id':\"" +
    @metadata.TARGET_NAMES_PREDICATE +
    "\",'@type':\"@json\"}}",
  document? : String = "morphir://ir/pkg/example/annotations?format=4.1.0#/distribution",
) -> @ion.IonValue raise {
  @ion_text.read_ion(
    "morphir_linked_metadata_v1::{document:\"" +
    document +
    "\",'$meta':{'@context':" +
    context +
    ",'@graph':" +
    graph +
    "}}",
  )
}

///|
pub fn row(
  name : String,
  backend? : String = "wanted",
  frontend? : String = "isReady",
  property? : String = "targetNames",
) -> String {
  "{'@id':\"morphir://ir/pkg/example?format=4.0.0#/module/main/value/" +
  name +
  "\",'" +
  property +
  "':{frontend:{moonbit:\"" +
  frontend +
  "\"},backend:{moonbit:\"" +
  backend +
  "\"}}}"
}
