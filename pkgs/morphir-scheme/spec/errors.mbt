///|
pub(all) suberror SpecError {
  SpecError(line~ : Int32, column~ : Int32, message~ : String)
} derive(Eq, Debug)

///|
pub extend SpecError with Eq::{equal, not_equal}

///|
pub extend SpecError with @debug.Debug::{to_repr}

///|
priv struct Context {
  source : String
  package_name : @ir.Path
}

///|
fn[T] Context::fail(
  self : Context,
  at : @scheme.Located,
  message : String,
) -> T raise SpecError {
  let (line, column) = @scheme.line_column(self.source, at.start)
  raise SpecError(line~, column~, message~)
}
