use crate::codemodel::name::Name;
pub struct Path(Vec<Name>);

impl Path {
    pub fn from_string(input: &str) -> Self {
        todo!()
    }
}

#[cfg(test)]
mod test {
    #[test]
    fn test_path() {
        let path = super::Path(vec![]);
    }
}