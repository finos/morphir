///|
pub struct Set[A] {
  dict : @dict.Dict[A, Unit]
}

///|
pub fn[A] empty(
  comparator : (A, A) -> @sdk.Order raise @sdk.SdkError,
) -> Set[A] {
  { dict: @dict.empty(comparator), }
}

///|
pub fn[A] singleton(
  comparator : (A, A) -> @sdk.Order raise @sdk.SdkError,
  value : A,
) -> Set[A] {
  { dict: @dict.singleton(comparator, value, ()), }
}

///|
pub fn[A] insert(value : A, set : Set[A]) -> Set[A] raise @sdk.SdkError {
  { dict: @dict.insert(value, (), set.dict), }
}

///|
pub fn[A] remove(value : A, set : Set[A]) -> Set[A] raise @sdk.SdkError {
  { dict: @dict.remove(value, set.dict), }
}

///|
pub fn[A] is_empty(set : Set[A]) -> Bool {
  @dict.is_empty(set.dict)
}

///|
pub fn[A] member(value : A, set : Set[A]) -> Bool raise @sdk.SdkError {
  @dict.member(value, set.dict)
}

///|
pub fn[A] size(set : Set[A]) -> Int32 {
  @dict.size(set.dict)
}

///|
pub fn[A] to_list(set : Set[A]) -> @list.List[A] {
  @dict.keys(set.dict)
}

///|
pub fn[A] from_list(
  comparator : (A, A) -> @sdk.Order raise @sdk.SdkError,
  values : @list.List[A],
) -> Set[A] raise @sdk.SdkError {
  let mut set = empty(comparator)
  for value in @list.to_array(values) {
    set = insert(value, set)
  }
  set
}

///|
pub fn[A, B] map(
  comparator : (B, B) -> @sdk.Order raise @sdk.SdkError,
  f : (A) -> B raise @sdk.SdkError,
  set : Set[A],
) -> Set[B] raise @sdk.SdkError {
  let mut result = empty(comparator)
  for value in @list.to_array(to_list(set)) {
    result = insert(f(value), result)
  }
  result
}

///|
pub fn[A, B] foldl(
  f : (A, B) -> B raise @sdk.SdkError,
  initial : B,
  set : Set[A],
) -> B raise @sdk.SdkError {
  @dict.foldl((key, _, acc) => f(key, acc), initial, set.dict)
}

///|
pub fn[A, B] foldr(
  f : (A, B) -> B raise @sdk.SdkError,
  initial : B,
  set : Set[A],
) -> B raise @sdk.SdkError {
  @dict.foldr((key, _, acc) => f(key, acc), initial, set.dict)
}

///|
pub fn[A] filter(
  f : (A) -> Bool raise @sdk.SdkError,
  set : Set[A],
) -> Set[A] raise @sdk.SdkError {
  { dict: @dict.filter((key, _) => f(key), set.dict), }
}

///|
pub fn[A] partition(
  f : (A) -> Bool raise @sdk.SdkError,
  set : Set[A],
) -> (Set[A], Set[A]) raise @sdk.SdkError {
  let (yes, no) = @dict.partition((key, _) => f(key), set.dict)
  ({ dict: yes, }, { dict: no, })
}

///|
pub fn[A] union(left : Set[A], right : Set[A]) -> Set[A] raise @sdk.SdkError {
  { dict: @dict.union(left.dict, right.dict), }
}

///|
pub fn[A] intersect(
  left : Set[A],
  right : Set[A],
) -> Set[A] raise @sdk.SdkError {
  { dict: @dict.intersect(left.dict, right.dict), }
}

///|
pub fn[A] diff(left : Set[A], right : Set[A]) -> Set[A] raise @sdk.SdkError {
  { dict: @dict.diff(left.dict, right.dict), }
}
