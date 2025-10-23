///|
pub struct MorphirJsonOptions {
  name_encoding : NameJsonEncoding
  unit_encoding : UnitJsonEncoding
} derive(Eq, Default, Hash, Show)

///|
pub(all) enum NameJsonEncoding {
  AsString
  AsList
} derive(Eq, Hash, Show)

///|
pub(all) enum UnitJsonEncoding {
  AsNull
  AsEmptyObject
} derive(Eq, Hash, Show)

///|
pub impl Default for NameJsonEncoding with default() {
  NameJsonEncoding::AsList
}

///|
pub impl Default for UnitJsonEncoding with default() {
  UnitJsonEncoding::AsEmptyObject
}
