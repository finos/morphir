use deno_core::JsRuntime;
use deno_core::RuntimeOptions;
use crate::eval;

fn main() {
    let mut runtime = JsRuntime::new(RuntimeOptions::default());

    // Evaluate some code
    let code = "let a = 1+4; a*2";
    let output: serde_json::Value =
        eval(&mut runtime, code).expect("Eval failed");

    println!("Output: {output:?}");

    let expected_output = serde_json::json!(10);
    assert_eq!(expected_output, output);
}
