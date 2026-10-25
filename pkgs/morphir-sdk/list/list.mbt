///|
pub struct List[A] {
  items : @corelist.List[A]
} derive(Eq, Debug)

///|
pub extend List with Eq::{equal, not_equal}

///|
pub extend List with @debug.Debug::{to_repr}

///|
pub fn[A] empty() -> List[A] {
  { items: @corelist.List([]), }
}

///|
pub fn[A] from_array(values : Array[A]) -> List[A] {
  { items: @corelist.List::from_iter(values.iter()), }
}

///|
pub fn[A] to_array(values : List[A]) -> Array[A] {
  values.items.to_array()
}

///|
pub fn[A] singleton(value : A) -> List[A] {
  { items: @corelist.List::singleton(value), }
}

///|
pub fn[A] cons(value : A, tail : List[A]) -> List[A] {
  { items: tail.items.prepend(value), }
}

///|
pub fn[A] repeat(n : Int32, value : A) -> List[A] {
  { items: @corelist.List::repeat(if n < 0 { 0 } else { n }, value), }
}

///|
pub fn range(
  low : @integer.Integer,
  high : @integer.Integer,
) -> List[@integer.Integer] {
  let mut out = empty()
  let mut n = high
  while n >= low {
    out = cons(n, out)
    n = @integer.subtract(n, @integer.from_int(1))
  }
  out
}

///|
pub fn[A, B] map(f : (A) -> B raise?, values : List[A]) -> List[B] raise? {
  { items: values.items.map(f), }
}

///|
pub fn[A, B] indexed_map(
  f : (Int32, A) -> B raise?,
  values : List[A],
) -> List[B] raise? {
  { items: values.items.mapi(f), }
}

///|
pub fn[A, B] foldl(
  f : (A, B) -> B raise?,
  initial : B,
  values : List[A],
) -> B raise? {
  values.items.fold(init=initial, (acc, a) => f(a, acc))
}

///|
pub fn[A, B] foldr(
  f : (A, B) -> B raise?,
  initial : B,
  values : List[A],
) -> B raise? {
  values.items.rev().fold(init=initial, (acc, a) => f(a, acc))
}

///|
pub fn[A] filter(f : (A) -> Bool raise?, values : List[A]) -> List[A] raise? {
  { items: values.items.filter(f), }
}

///|
pub fn[A, B] filter_map(
  f : (A) -> B? raise?,
  values : List[A],
) -> List[B] raise? {
  { items: values.items.filter_map(f), }
}

///|
pub fn[A] length(values : List[A]) -> Int32 {
  values.items.length()
}

///|
pub fn[A] reverse(values : List[A]) -> List[A] {
  { items: values.items.rev(), }
}

///|
pub fn[A : Eq] member(value : A, values : List[A]) -> Bool {
  values.items.contains(value)
}

///|
pub fn[A] all(f : (A) -> Bool raise?, values : List[A]) -> Bool raise? {
  values.items.all(f)
}

///|
pub fn[A] any(f : (A) -> Bool raise?, values : List[A]) -> Bool raise? {
  values.items.any(f)
}

///|
pub fn[A] maximum(cmp : (A, A) -> @sdk.Order, values : List[A]) -> A? {
  foldl(
    (a, b) => {
      match b {
        None => Some(a)
        Some(b) => Some(if cmp(a, b) == @sdk.GT { a } else { b })
      }
    },
    None,
    values,
  )
}

///|
pub fn[A] minimum(cmp : (A, A) -> @sdk.Order, values : List[A]) -> A? {
  maximum((a, b) => cmp(b, a), values)
}

///|
pub fn sum(values : List[@integer.Integer]) -> @integer.Integer {
  foldl(@integer.add, @integer.from_int(0), values)
}

///|
pub fn product(values : List[@integer.Integer]) -> @integer.Integer {
  foldl(@integer.multiply, @integer.from_int(1), values)
}

///|
pub fn sum_float(values : List[Double]) -> Double {
  foldl((value, total) => value + total, 0.0, values)
}

///|
pub fn product_float(values : List[Double]) -> Double {
  foldl((value, total) => value * total, 1.0, values)
}

///|
pub fn[A] append(a : List[A], b : List[A]) -> List[A] {
  { items: a.items.concat(b.items), }
}

///|
pub fn[A] concat(values : List[List[A]]) -> List[A] {
  foldr(append, empty(), values)
}

///|
pub fn[A, B] concat_map(
  f : (A) -> List[B] raise?,
  values : List[A],
) -> List[B] raise? {
  concat(map(f, values))
}

///|
pub fn[A] intersperse(separator : A, values : List[A]) -> List[A] {
  { items: values.items.intersperse(separator), }
}

///|
pub fn[A] is_empty(values : List[A]) -> Bool {
  values.items.is_empty()
}

///|
pub fn[A] head(values : List[A]) -> A? {
  values.items.head()
}

///|
pub fn[A] tail(values : List[A]) -> List[A]? {
  if is_empty(values) {
    None
  } else {
    Some({ items: values.items.drop(1), })
  }
}

///|
pub fn[A] take(n : Int32, values : List[A]) -> List[A] {
  { items: values.items.take(if n < 0 { 0 } else { n }), }
}

///|
pub fn[A] drop(n : Int32, values : List[A]) -> List[A] {
  { items: values.items.drop(if n < 0 { 0 } else { n }), }
}

///|
pub fn[A] partition(
  f : (A) -> Bool raise?,
  values : List[A],
) -> (List[A], List[A]) raise? {
  let mut yes = empty()
  let mut no = empty()
  for a in values.items {
    if f(a) {
      yes = cons(a, yes)
    } else {
      no = cons(a, no)
    }
  }
  (reverse(yes), reverse(no))
}

///|
pub fn[A, B] unzip(values : List[(A, B)]) -> (List[A], List[B]) {
  let (a, b) = values.items.unzip()
  ({ items: a, }, { items: b, })
}

///|
/// Stable sort with explicit Morphir ordering; input storage is never changed.
pub fn[A] sort_with(
  cmp : (A, A) -> @sdk.Order raise?,
  values : List[A],
) -> List[A] raise? {
  let a = to_array(values)
  // Stable bottom-up merge sort, including for caller-defined comparators.
  let mut width = 1
  while width < a.length() {
    let previous = a.copy()
    let mut start = 0
    while start < a.length() {
      let middle = Int32::min(start + width, a.length())
      let end = Int32::min(middle + width, a.length())
      let mut i = start
      let mut j = middle
      let mut k = start
      while k < end {
        if j >= end || (i < middle && cmp(previous[i], previous[j]) != @sdk.GT) {
          a[k] = previous[i]
          i += 1
        } else {
          a[k] = previous[j]
          j += 1
        }
        k += 1
      }
      start = end
    }
    width = if width > a.length() / 2 { a.length() } else { width * 2 }
  }
  from_array(a)
}

///|
pub fn[A] sort(cmp : (A, A) -> @sdk.Order, values : List[A]) -> List[A] {
  sort_with(cmp, values)
}

///|
pub fn[A, B] sort_by(
  key : (A) -> B raise?,
  cmp : (B, B) -> @sdk.Order,
  values : List[A],
) -> List[A] raise? {
  sort_with((a, b) => cmp(key(a), key(b)), values)
}

///|
pub fn[A, B, Z] map2(
  f : (A, B) -> Z raise?,
  v0 : List[A],
  v1 : List[B],
) -> List[Z] raise? {
  let a0 = to_array(v0)
  let a1 = to_array(v1)
  let mut count = a0.length()
  count = Int32::min(count, a1.length())
  let out = []
  for i = 0; i < count; i = i + 1 {
    out.push(f(a0[i], a1[i]))
  }
  from_array(out)
}

///|
pub fn[A, B, C, Z] map3(
  f : (A, B, C) -> Z raise?,
  v0 : List[A],
  v1 : List[B],
  v2 : List[C],
) -> List[Z] raise? {
  let a0 = to_array(v0)
  let a1 = to_array(v1)
  let a2 = to_array(v2)
  let mut count = a0.length()
  count = Int32::min(count, a1.length())
  count = Int32::min(count, a2.length())
  let out = []
  for i = 0; i < count; i = i + 1 {
    out.push(f(a0[i], a1[i], a2[i]))
  }
  from_array(out)
}

///|
pub fn[A, B, C, D, Z] map4(
  f : (A, B, C, D) -> Z raise?,
  v0 : List[A],
  v1 : List[B],
  v2 : List[C],
  v3 : List[D],
) -> List[Z] raise? {
  let a0 = to_array(v0)
  let a1 = to_array(v1)
  let a2 = to_array(v2)
  let a3 = to_array(v3)
  let mut count = a0.length()
  count = Int32::min(count, a1.length())
  count = Int32::min(count, a2.length())
  count = Int32::min(count, a3.length())
  let out = []
  for i = 0; i < count; i = i + 1 {
    out.push(f(a0[i], a1[i], a2[i], a3[i]))
  }
  from_array(out)
}

///|
pub fn[A, B, C, D, E, Z] map5(
  f : (A, B, C, D, E) -> Z raise?,
  v0 : List[A],
  v1 : List[B],
  v2 : List[C],
  v3 : List[D],
  v4 : List[E],
) -> List[Z] raise? {
  let a0 = to_array(v0)
  let a1 = to_array(v1)
  let a2 = to_array(v2)
  let a3 = to_array(v3)
  let a4 = to_array(v4)
  let mut count = a0.length()
  count = Int32::min(count, a1.length())
  count = Int32::min(count, a2.length())
  count = Int32::min(count, a3.length())
  count = Int32::min(count, a4.length())
  let out = []
  for i = 0; i < count; i = i + 1 {
    out.push(f(a0[i], a1[i], a2[i], a3[i], a4[i]))
  }
  from_array(out)
}

///|
pub fn[A, B] inner_join(
  right : List[B],
  matches : (A, B) -> Bool raise?,
  left : List[A],
) -> List[(A, B)] raise? {
  let out = []
  for a in left.items {
    for b in right.items {
      if matches(a, b) {
        out.push((a, b))
      }
    }
  }
  from_array(out)
}

///|
pub fn[A, B] left_join(
  right : List[B],
  matches : (A, B) -> Bool raise?,
  left : List[A],
) -> List[(A, B?)] raise? {
  let out = []
  for a in left.items {
    let mut found = false
    for b in right.items {
      if matches(a, b) {
        found = true
        out.push((a, Some(b)))
      }
    }
    if !found {
      out.push((a, None))
    }
  }
  from_array(out)
}
