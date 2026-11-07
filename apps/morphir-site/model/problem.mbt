///|
/// One build problem. `line` is 0 when the line is not known.
#derive(Eq, Debug)
pub(all) struct Problem {
  file : String
  line : Int32
  message : String
}

///|
pub extend Problem with Eq::{equal, not_equal}

///|
pub extend Problem with @debug.Debug::{to_repr}

///|
/// All the problems found in one step. The generator reports them together.
#derive(Eq, Debug)
pub(all) suberror Invalid {
  Invalid(Array[Problem])
}

///|
pub extend Invalid with Eq::{equal, not_equal}

///|
pub extend Invalid with @debug.Debug::{to_repr}

///|
pub fn problem(file : String, message : String, line~ : Int32 = 0) -> Problem {
  { file, line, message, }
}

///|
pub fn Problem::render(self : Problem) -> String {
  if self.line > 0 {
    "\{self.file}:\{self.line}: \{self.message}"
  } else {
    "\{self.file}: \{self.message}"
  }
}
