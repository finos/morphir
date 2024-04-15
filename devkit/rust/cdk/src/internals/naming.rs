use lasso::{Spur, ThreadedRodeo};
use state::InitCell;
use std::sync::Arc;

static NAMING_CONTEXT: InitCell<NamingContext> = InitCell::new();
type Text = Spur;

pub struct NamingContext {
    rodeo: Arc<ThreadedRodeo>,
}

impl NamingContext {
    pub fn new() -> Self {
        Self {
            rodeo: Arc::new(ThreadedRodeo::new()),
        }
    }

    pub fn default() -> &'static Self {
        NAMING_CONTEXT.get_or_init(|| Self::new())
    }

    pub fn get_text(&self, text: &str) -> Option<Text> {
        self.rodeo.get(text)
    }

    pub fn resolve(&self, text: Text) -> &str {
        self.rodeo.resolve(&text)
    }

    pub fn get_run(&self, text: &str) -> Run {
        let sym = self.rodeo.get_or_intern(text);
        let rodeo = self.rodeo.clone();
        Run {
            text: sym,
            rodeo: rodeo,
        }
    }

    pub fn run_to_str(&self, run: Run) -> &str {
        self.resolve(run.text)
    }

    pub fn text(&self, text: &str) -> Text {
        self.rodeo.get_or_intern(text)
    }
}

pub struct Name(Vec<Run>);

impl Name {
    pub fn from_str(s: &str, naming_context: NamingContext) -> Self {
        Name(s.split('.').map(|s| naming_context.get_run(s)).collect())
    }
}

#[derive(Debug)]
pub struct Run {
    text: Text,
    rodeo: Arc<ThreadedRodeo>,
}

impl Run {
    pub fn to_str(&self) -> &str {
        self.rodeo.resolve(&self.text)
    }
}

pub struct CanonicalNameStr(String);

pub struct Path(Vec<Name>);
impl Path {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn can_create_interned_text_from_naming_context() {
        let ctx = NamingContext::new();
        let text1 = ctx.text("text");
        let text2 = ctx.text("text");
        assert_eq!(text1, text2);
    }

    #[test]
    fn two_runs_created_from_the_same_string_return_the_same_text() {
        let context = NamingContext::new();
        let run1 = context.get_run("test");
        let run2 = context.get_run("test");

        assert_eq!(run1.text, run2.text);
    }

    #[test]
    fn can_get_a_str_from_a_run_using_a_naming_context() {
        let context = NamingContext::new();
        let run = context.get_run("This is fine!");
        let actual = context.run_to_str(run);
        assert_eq!(actual, "This is fine!");
    }
}
