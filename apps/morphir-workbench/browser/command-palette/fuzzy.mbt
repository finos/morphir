///|
/// A fuzzy match: its score and the indexes of the matched characters in the text.
pub(all) struct Match {
  score : Int32
  positions : Array[Int32]
} derive(Eq, Debug)

///|
let match_points = 16

///|
/// The most a matched character can earn on top of `match_points`: a run of matches, or the start of the text.
let best_bonus = 8

///|
let case_points = 1

///|
let gap_start = 3

///|
let gap_extension = 1

///|
fn lower(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn is_separator(c : Char) -> Bool {
  c == '/' || c == '.' || c == '_' || c == '-' || c == ' '
}

///|
/// The bonus for matching at `index`: the start of the text, the start of a word after a separator, or a capital
/// that starts a camelCase hump.
fn boundary(text : Array[Char], index : Int32) -> Int32 {
  if index == 0 {
    return best_bonus
  }
  let before = text[index - 1]
  let here = text[index]
  if is_separator(before) {
    7
  } else if before >= 'a' && before <= 'z' && here >= 'A' && here <= 'Z' {
    6
  } else {
    0
  }
}

///|
/// Matches `query` against `text`: every character of the query, without its spaces, must appear in the text in
/// order, ignoring ASCII case. Matches at the start, after `/ . _ -` and spaces, at camelCase humps and in runs score
/// more; gaps and longer texts score less. The best alignment is found by dynamic programming, so a text matched
/// against itself scores at least as high as against any other text.
pub fn fuzzy(query : String, text : String) -> Match? {
  let wanted = query.to_array().filter(c => c != ' ')
  let chars = text.to_array()
  let m = wanted.length()
  let n = chars.length()
  if m == 0 {
    return Some({ score: 0, positions: [], })
  }
  if m > n {
    return None
  }
  let none = -1_000_000_000
  // score[i][j]: the best score for the first i+1 query characters with character i at text index j.
  let score : Array[Array[Int32]] = Array::makei(m, _ => Array::make(n, none))
  // from[i][j]: the text index of query character i-1 in that best alignment.
  let from : Array[Array[Int32]] = Array::makei(m, _ => Array::make(n, -1))
  for i in 0..<m {
    let q = wanted[i]
    // The best earlier match that leaves a gap, kept as score + gap_extension * index so the gap length cancels.
    let mut best_gap = none
    let mut best_gap_at = -1
    for j in 0..<n {
      if i > 0 && j >= 2 && score[i - 1][j - 2] != none {
        let candidate = score[i - 1][j - 2] + gap_extension * (j - 2)
        if candidate > best_gap {
          best_gap = candidate
          best_gap_at = j - 2
        }
      }
      if lower(chars[j]) != lower(q) {
        continue
      }
      let points = match_points + (if chars[j] == q { case_points } else { 0 })
      if i == 0 {
        let lead = if j < 3 { j } else { 3 }
        score[i][j] = points + boundary(chars, j) - lead
        continue
      }
      let mut best = none
      let mut best_from = -1
      if j >= 1 && score[i - 1][j - 1] != none {
        best = score[i - 1][j - 1] + points + best_bonus
        best_from = j - 1
      }
      if best_gap != none {
        // A gap from k to j costs gap_start + gap_extension * (j - k - 2).
        let gapped = best_gap -
          gap_extension * (j - 2) -
          gap_start +
          points +
          boundary(chars, j)
        if gapped > best {
          best = gapped
          best_from = best_gap_at
        }
      }
      score[i][j] = best
      from[i][j] = best_from
    }
  }
  let mut end = -1
  let mut total = none
  for j in 0..<n {
    if score[m - 1][j] > total {
      total = score[m - 1][j]
      end = j
    }
  }
  if total == none {
    return None
  }
  let positions = Array::make(m, 0)
  let mut at = end
  for k in 0..<m {
    let i = m - 1 - k
    positions[i] = at
    at = from[i][at]
  }
  Some({ score: total - (n - m) / 4, positions, })
}

///|
/// Splits `text` into runs of matched and unmatched characters, for drawing a match.
pub fn segments(
  text : String,
  positions : Array[Int32],
) -> Array[(String, Bool)] {
  let out : Array[(String, Bool)] = []
  let buffer = StringBuilder()
  let mut marked = false
  for index, c in text.to_array() {
    let here = positions.contains(index)
    if here != marked && buffer.to_string() != "" {
      out.push((buffer.to_string(), marked))
      buffer.reset()
    }
    marked = here
    buffer.write_char(c)
  }
  if buffer.to_string() != "" {
    out.push((buffer.to_string(), marked))
  }
  out
}

///|
pub extend Match with Eq::{not_equal, equal}

///|
pub extend Match with @debug.Debug::{to_repr}
