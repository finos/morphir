pub(crate) mod compiler;

use crate::compiler::{ElmParser, Rule};
use pest::Parser;

fn main() {
    let file_contents: &'static str = r#"module Com.Example.Main exposing (..)
    -- This is a comment
    -- This is also a comment
    "#;
    let successful_parse = ElmParser::parse(Rule::file, &file_contents);
    println!("{:?}", successful_parse);
}
