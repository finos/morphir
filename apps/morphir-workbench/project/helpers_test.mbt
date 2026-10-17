///|
fn path(text : String) -> @ids.SourcePath {
  @ids.SourcePath::parse(text) catch {
    _ => abort(text)
  }
}

///|
fn elm_rules() -> @project.FileRules {
  {
    extensions: [@ids.FileExtension::parse(".elm") catch { _ => abort("ext") }],
    layout: ManyFiles,
  }
}

///|
fn shop() -> @project.Project {
  @project.Project::single(
    @ids.LanguageId::parse("elm") catch {
      _ => abort("lang")
    },
    @ids.SourcePackageName::parse("Shop.Orders") catch {
      _ => abort("name")
    },
    path("src/Shop/Orders/Api.elm"),
    "module Shop.Orders.Api exposing (..)\n",
    exposed=[@ids.SourceModuleName::parse("Api") catch { _ => abort("module") }],
  )
}
