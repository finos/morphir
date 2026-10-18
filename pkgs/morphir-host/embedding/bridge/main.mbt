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
fn Pin::validated(
  self : Pin,
) -> @assembly.PackagePin raise @assembly.AssemblyError {
  @assembly.PackagePin::new(self.name, self.sha256)
}

///|
fn planned(value : Input) -> Array[String] raise @assembly.AssemblyError {
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
  result.packages().map(p => p.pin().name())
}

///|
// JSON is the explicit JavaScript boundary. Graph decisions remain in MoonBit.
#export_name("plan")
pub fn plan(input : String) -> String {
  try {
    let value : Input = @json.from_json(@json.parse(input))
    let order = planned(value) catch {
      error =>
        return Json::object({ "error": Json::string(@debug.to_string(error)) }).stringify()
    }
    Json::object({ "order": Json::array(order.map(Json::string)) }).stringify()
  } catch {
    error =>
      Json::object({ "error": Json::string(error.to_string()) }).stringify()
  }
}
