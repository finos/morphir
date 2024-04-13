pub struct Name(Vec<String>);

impl Name {
    pub fn from_str(s: &str) -> Self {
        Name(s.split('.').map(|s| s.to_string()).collect())
    }
}

pub struct CanonicalNameStr(String);

pub struct Path(Vec<Name>);
impl Path {}

pub struct NamingContext;

impl NamingContext {
    pub fn default() -> Self {
        NamingContext
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_name() {
        let name = Name::from_str("a.b.c");
    }

    #[test]
    fn test_path() {
        let path = Path(vec![]);
    }

    #[test]
    fn test_naming_context() {
        let naming_context = NamingContext::default();
    }
}
