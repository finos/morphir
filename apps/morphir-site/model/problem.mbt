///|
/// One build problem. `line` is 0 when the line is not known.
pub(all) struct Problem {
  file : String
  line : Int
  message : String
} derive(Eq, Debug)

///|
pub extend Problem with Eq::{equal, not_equal}

///|
pub extend Problem with @debug.Debug::{to_repr}

///|
/// All the problems found in one step. The generator reports them together.
pub(all) suberror Invalid {
  Invalid(Array[Problem])
} derive(Eq, Debug)

///|
pub extend Invalid with Eq::{equal, not_equal}

///|
pub extend Invalid with @debug.Debug::{to_repr}

///|
pub fn problem(file : String, message : String, line? : Int = 0) -> Problem {
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
