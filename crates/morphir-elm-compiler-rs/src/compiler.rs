use pest_derive::Parser;

#[derive(Parser)]
#[grammar = "elm.pest"]
pub struct ElmParser;
