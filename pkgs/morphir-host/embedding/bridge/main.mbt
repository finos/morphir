///|
priv struct Pin {
  name : String
  sha256 : String
} derive(FromJson)

///|
priv struct Import {
  name : String
  pin : Pin
} derive(FromJson)

///|
priv struct Entry {
  pin : Pin
  dependencies : Array[Import]
} derive(FromJson)

///|
priv struct Input {
  root : Pin
  packages : Array[Entry]
} derive(FromJson)

///|
fn Pin::validated(self : Pin) -> @assembly.PackagePin raise {
  @assembly.PackagePin::new(self.name, self.sha256)
}

///|
// JSON is the explicit JavaScript boundary. Graph decisions remain in MoonBit.
#export_name("plan")
pub fn plan(input : String) -> String {
  try {
    let value : Input = @json.from_json(@json.parse(input))
    let result = @assembly.plan(
      value.root.validated(),
      value.packages.map(entry => {
        @assembly.Package::new(
          entry.pin.validated(),
          entry.dependencies.map(dep => {
            @assembly.Dependency::new(dep.name, dep.pin.validated())
          }),
        )
      }),
    )
    Json::object({
      "order": Json::array(
        result.packages().map(p => Json::string(p.pin().name())),
      ),
    }).stringify()
  } catch {
    error =>
      Json::object({ "error": Json::string(error.to_string()) }).stringify()
  }
}
