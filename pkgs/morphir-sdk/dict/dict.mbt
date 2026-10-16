///|
/// An immutable ordered dictionary. The comparator is supplied by the typed
/// adapter for the Morphir key type and must define a total order.
pub struct Dict[K, V] {
  entries : Array[(K, V)]
  comparator : (K, K) -> @sdk.Order raise @sdk.SdkError
}

///|
pub fn[K, V] empty(
  comparator : (K, K) -> @sdk.Order raise @sdk.SdkError,
) -> Dict[K, V] {
  { entries: [], comparator, }
}

///|
pub fn[K, V] singleton(
  comparator : (K, K) -> @sdk.Order raise @sdk.SdkError,
  key : K,
  value : V,
) -> Dict[K, V] {
  { entries: [(key, value)], comparator, }
}

///|
fn[K, V] locate(
  key : K,
  dict : Dict[K, V],
) -> (Int32, Bool) raise @sdk.SdkError {
  let mut low = 0
  let mut high = dict.entries.length()
  while low < high {
    let middle = low + (high - low) / 2
    let (current, _) = dict.entries[middle]
    match (dict.comparator)(current, key) {
      @sdk.LT => low = middle + 1
      @sdk.EQ => return (middle, true)
      @sdk.GT => high = middle
    }
  }
  (low, false)
}

///|
pub fn[K, V] insert(
  key : K,
  value : V,
  dict : Dict[K, V],
) -> Dict[K, V] raise @sdk.SdkError {
  let (index, exists) = locate(key, dict)
  let entries = []
  for i = 0; i < dict.entries.length(); i = i + 1 {
    if i == index {
      entries.push((key, value))
    }
    if i != index || !exists {
      entries.push(dict.entries[i])
    }
  }
  if index == dict.entries.length() {
    entries.push((key, value))
  }
  { entries, comparator: dict.comparator, }
}

///|
pub fn[K, V] remove(
  key : K,
  dict : Dict[K, V],
) -> Dict[K, V] raise @sdk.SdkError {
  let (index, exists) = locate(key, dict)
  if !exists {
    return dict
  }
  let entries = []
  for i = 0; i < dict.entries.length(); i = i + 1 {
    if i != index {
      entries.push(dict.entries[i])
    }
  }
  { entries, comparator: dict.comparator, }
}

///|
pub fn[K, V] get(key : K, dict : Dict[K, V]) -> V? raise @sdk.SdkError {
  let (index, exists) = locate(key, dict)
  if exists {
    let (_, value) = dict.entries[index]
    Some(value)
  } else {
    None
  }
}

///|
pub fn[K, V] update(
  key : K,
  f : (V?) -> V? raise @sdk.SdkError,
  dict : Dict[K, V],
) -> Dict[K, V] raise @sdk.SdkError {
  match f(get(key, dict)) {
    Some(value) => insert(key, value, dict)
    None => remove(key, dict)
  }
}

///|
pub fn[K, V] is_empty(dict : Dict[K, V]) -> Bool {
  dict.entries.is_empty()
}

///|
pub fn[K, V] member(key : K, dict : Dict[K, V]) -> Bool raise @sdk.SdkError {
  let (_, exists) = locate(key, dict)
  exists
}

///|
fn[K, V] has_key(key : K, dict : Dict[K, V]) -> Bool raise @sdk.SdkError {
  let (_, exists) = locate(key, dict)
  exists
}

///|
pub fn[K, V] size(dict : Dict[K, V]) -> Int32 {
  dict.entries.length()
}

///|
pub fn[K, V] keys(dict : Dict[K, V]) -> @list.List[K] {
  let out = []
  for entry in dict.entries {
    let (key, _) = entry
    out.push(key)
  }
  @list.from_array(out)
}

///|
pub fn[K, V] values(dict : Dict[K, V]) -> @list.List[V] {
  let out = []
  for entry in dict.entries {
    let (_, value) = entry
    out.push(value)
  }
  @list.from_array(out)
}

///|
pub fn[K, V] to_list(dict : Dict[K, V]) -> @list.List[(K, V)] {
  @list.from_array(dict.entries)
}

///|
pub fn[K, V] from_list(
  comparator : (K, K) -> @sdk.Order raise @sdk.SdkError,
  entries : @list.List[(K, V)],
) -> Dict[K, V] raise @sdk.SdkError {
  let mut dict = empty(comparator)
  for entry in @list.to_array(entries) {
    let (key, value) = entry
    dict = insert(key, value, dict)
  }
  dict
}

///|
pub fn[K, V, W] map(
  f : (K, V) -> W raise @sdk.SdkError,
  dict : Dict[K, V],
) -> Dict[K, W] raise @sdk.SdkError {
  let entries = []
  for entry in dict.entries {
    let (key, value) = entry
    entries.push((key, f(key, value)))
  }
  { entries, comparator: dict.comparator, }
}

///|
pub fn[K, V, A] foldl(
  f : (K, V, A) -> A raise @sdk.SdkError,
  initial : A,
  dict : Dict[K, V],
) -> A raise @sdk.SdkError {
  let mut acc = initial
  for entry in dict.entries {
    let (key, value) = entry
    acc = f(key, value, acc)
  }
  acc
}

///|
pub fn[K, V, A] foldr(
  f : (K, V, A) -> A raise @sdk.SdkError,
  initial : A,
  dict : Dict[K, V],
) -> A raise @sdk.SdkError {
  let mut acc = initial
  for i = dict.entries.length() - 1; i >= 0; i = i - 1 {
    let (key, value) = dict.entries[i]
    acc = f(key, value, acc)
  }
  acc
}

///|
pub fn[K, V] filter(
  f : (K, V) -> Bool raise @sdk.SdkError,
  dict : Dict[K, V],
) -> Dict[K, V] raise @sdk.SdkError {
  let entries = []
  for entry in dict.entries {
    let (key, value) = entry
    if f(key, value) {
      entries.push(entry)
    }
  }
  { entries, comparator: dict.comparator, }
}

///|
pub fn[K, V] partition(
  f : (K, V) -> Bool raise @sdk.SdkError,
  dict : Dict[K, V],
) -> (Dict[K, V], Dict[K, V]) raise @sdk.SdkError {
  let yes = []
  let no = []
  for entry in dict.entries {
    let (key, value) = entry
    if f(key, value) {
      yes.push(entry)
    } else {
      no.push(entry)
    }
  }
  (
    { entries: yes, comparator: dict.comparator, },
    { entries: no, comparator: dict.comparator, },
  )
}

///|
pub fn[K, V] union(
  left : Dict[K, V],
  right : Dict[K, V],
) -> Dict[K, V] raise @sdk.SdkError {
  let mut result = right
  for entry in left.entries {
    let (key, value) = entry
    result = insert(key, value, result)
  }
  result
}

///|
pub fn[K, V] intersect(
  left : Dict[K, V],
  right : Dict[K, V],
) -> Dict[K, V] raise @sdk.SdkError {
  let mut result = empty(left.comparator)
  for entry in left.entries {
    let (key, value) = entry
    if has_key(key, right) {
      result = insert(key, value, result)
    }
  }
  result
}

///|
pub fn[K, V] diff(
  left : Dict[K, V],
  right : Dict[K, V],
) -> Dict[K, V] raise @sdk.SdkError {
  let mut result = empty(left.comparator)
  for entry in left.entries {
    let (key, value) = entry
    if !has_key(key, right) {
      result = insert(key, value, result)
    }
  }
  result
}

///|
/// Elm Dict.merge traverses the combined key space in ascending order.
pub fn[K, A, B, R] merge(
  left_only : (K, A, R) -> R raise @sdk.SdkError,
  both : (K, A, B, R) -> R raise @sdk.SdkError,
  right_only : (K, B, R) -> R raise @sdk.SdkError,
  left : Dict[K, A],
  right : Dict[K, B],
  initial : R,
) -> R raise @sdk.SdkError {
  let mut i = 0
  let mut j = 0
  let mut result = initial
  while i < left.entries.length() || j < right.entries.length() {
    if i == left.entries.length() {
      let (key, value) = right.entries[j]
      result = right_only(key, value, result)
      j += 1
    } else if j == right.entries.length() {
      let (key, value) = left.entries[i]
      result = left_only(key, value, result)
      i += 1
    } else {
      let (left_key, left_value) = left.entries[i]
      let (right_key, right_value) = right.entries[j]
      match (left.comparator)(left_key, right_key) {
        @sdk.LT => {
          result = left_only(left_key, left_value, result)
          i += 1
        }
        @sdk.EQ => {
          result = both(left_key, left_value, right_value, result)
          i += 1
          j += 1
        }
        @sdk.GT => {
          result = right_only(right_key, right_value, result)
          j += 1
        }
      }
    }
  }
  result
}
