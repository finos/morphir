use boa_engine::{Context, Source};
use extism_pdk::*;
use serde_json::Value;

#[plugin_fn]
pub fn jseval(code: String) -> FnResult<Json<Value>> {
    // Instantiate the execution context
    let mut context = Context::default();
    let source = Source::from_bytes(code.as_bytes());

    // Parse the source code
    let result = context.eval(source).unwrap();
    let json = result.to_json(&mut context).unwrap();

    let json = Json(json);
    Ok(json)
}
