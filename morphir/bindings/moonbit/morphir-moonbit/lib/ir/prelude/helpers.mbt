
pub struct Length(Int64) derive(Eq, Hash, Show)
pub fn Length::new(value : Int64) -> Length {
  Length(value)
}

pub struct Index(Int64) derive(Eq, Hash, Show)
pub fn Index::new(value : Int64) -> Index {
  Index(value)
}