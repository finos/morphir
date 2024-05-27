use deno_core::v8;
use deno_core::JsRuntime;
use deno_core::RuntimeOptions;


pub fn eval(
    context: &mut JsRuntime,
    code: &'static str,
) -> Result<serde_json::Value, String> {
    let res = context.execute_script("<anon>", code);
    match res {
        Ok(global) => {
            let scope = &mut context.handle_scope();
            let local = v8::Local::new(scope, global);
            // Deserialize a `v8` object into a Rust type using `serde_v8`,
            // in this case deserialize to a JSON `Value`.
            let deserialized_value =
                serde_v8::from_v8::<serde_json::Value>(scope, local);

            match deserialized_value {
                Ok(value) => Ok(value),
                Err(err) => Err(format!("Cannot deserialize value: {err:?}")),
            }
        }
        Err(err) => Err(format!("Evaling error: {err:?}")),
    }
}

use extism_pdk::*;
use extism_pdk::Json as JSON;
#[plugin_fn]
pub fn evaljs(code: String) -> FnResult<JSON<serde_json::Value>> {
    let mut runtime = JsRuntime::new(RuntimeOptions::default());
    let  ownedCode:&'static str = code.leak();
    let res = eval(&mut runtime, &ownedCode).expect("Eval failed");
    Ok(JSON(res))
}
