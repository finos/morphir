pub struct NameId(Int) derive(Eq, Hash, Show)

pub fn name_id(id : Int) -> NameId {
  NameId(id)
}

pub fn NameId::from_int(id : Int) -> NameId {
  NameId(id)
}