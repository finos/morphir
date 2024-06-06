use deno_ast::MediaType;
use deno_ast::ParseParams;
use deno_ast::SourceTextInfo;
use deno_core::error::AnyError;
use deno_core::extension;
use deno_core::op2;
use deno_core::ModuleLoadResponse;
use deno_core::ModuleSourceCode;
use std::env;
use std::ffi::OsString;
use std::rc::Rc;
use std::sync::Arc;
use thiserror::Error;


#[op2(async)]
#[string]
async fn op_read_file(#[string] path: String) -> std::result:: Result<String, AnyError> {
    let contents = tokio::fs::read_to_string(path).await?;
    Ok(contents)
}

#[op2(async)]
#[string]
async fn op_write_file(#[string] path: String, #[string] contents: String) -> std::result:: Result<(), AnyError> {
    tokio::fs::write(path, contents).await?;
    Ok(())
}

#[op2(async)]
#[string]
async fn op_fetch(#[string] url: String) -> std::result:: Result<String, AnyError> {
    let body = reqwest::get(url).await?.text().await?;
    Ok(body)
}

#[op2(async)]
async fn op_set_timeout(delay: f64) -> std::result:: Result<(), AnyError> {
    tokio::time::sleep(std::time::Duration::from_millis(delay as u64)).await;
    Ok(())
}

#[op2(fast)]
fn op_remove_file(#[string] path: String) -> std::result::Result<(), AnyError> {
    std::fs::remove_file(path)?;
    Ok(())
}

struct TsModuleLoader;

impl deno_core::ModuleLoader for TsModuleLoader {
    fn resolve(
        &self,
        specifier: &str,
        referrer: &str,
        _kind: deno_core::ResolutionKind,
    ) -> std::result:: Result<deno_core::ModuleSpecifier, AnyError> {
        deno_core::resolve_import(specifier, referrer).map_err(|e| e.into())
    }

    fn load(
        &self,
        module_specifier: &deno_core::ModuleSpecifier,
        _maybe_referrer: Option<&reqwest::Url>,
        _is_dyn_import: bool,
        _requested_module_type: deno_core::RequestedModuleType,
    ) -> ModuleLoadResponse {
        let module_specifier = module_specifier.clone();

        let module_load = Box::pin(async move {
            let path = module_specifier.to_file_path().unwrap();

            let media_type = MediaType::from_path(&path);
            let (module_type, should_transpile) = match MediaType::from_path(&path) {
                MediaType::JavaScript | MediaType::Mjs | MediaType::Cjs => {
                    (deno_core::ModuleType::JavaScript, false)
                }
                MediaType::Jsx => (deno_core::ModuleType::JavaScript, true),
                MediaType::TypeScript
                | MediaType::Mts
                | MediaType::Cts
                | MediaType::Dts
                | MediaType::Dmts
                | MediaType::Dcts
                | MediaType::Tsx => (deno_core::ModuleType::JavaScript, true),
                MediaType::Json => (deno_core::ModuleType::Json, false),
                _ => panic!("Unknown extension {:?}", path.extension()),
            };

            let code = std::fs::read_to_string(&path)?;
            let code = if should_transpile {
                let parsed = deno_ast::parse_module(ParseParams {
                    specifier: module_specifier.clone(),
                    text_info: SourceTextInfo::from_string(code),
                    media_type,
                    capture_tokens: false,
                    scope_analysis: false,
                    maybe_syntax: None,
                })?;
                parsed
                    .transpile(&Default::default(), &Default::default())?
                    .into_source()
                    .text
            } else {
                code
            };
            let module = deno_core::ModuleSource::new(
                module_type,
                ModuleSourceCode::String(code.into()),
                &module_specifier,
                None,
            );
            Ok(module)
        });

        ModuleLoadResponse::Async(module_load)
    }
}

static RUNTIME_SNAPSHOT: &[u8] =
    include_bytes!(concat!(env!("OUT_DIR"), "/MORPHIRJS_SNAPSHOT.bin"));

#[derive(Debug, Error)]
pub enum Error {
    #[error("IO error: {0}")]
    IO(#[from] std::io::Error),
    #[error("Invalid file path: {0}")]
    InvalidFilePath(String),
    #[error("Deno error: {0}")]
    DenoError(#[from] deno_core::error::AnyError),
}

pub type Result<T> = std::result::Result<T, Error>;

pub struct MorphirJs {
    rt: Arc<tokio::runtime::Runtime>,
    js: deno_core::JsRuntime,
}

impl MorphirJs {
    pub fn new() -> Self {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        let js_runtime = deno_core::JsRuntime::new(deno_core::RuntimeOptions {
            module_loader: Some(Rc::new(TsModuleLoader)),
            startup_snapshot: Some(RUNTIME_SNAPSHOT),
            extensions: vec![morphirjs::init_ops()],
            ..Default::default()
        });

        Self { rt: Arc::new(rt), js: js_runtime }
    }

    pub fn from_tokio_runtime(rt: tokio::runtime::Runtime) -> Self {
        let js_runtime = deno_core::JsRuntime::new(deno_core::RuntimeOptions {
            module_loader: Some(Rc::new(TsModuleLoader)),
            startup_snapshot: Some(RUNTIME_SNAPSHOT),
            extensions: vec![morphirjs::init_ops()],
            ..Default::default()
        });

        Self { rt: Arc::new(rt), js: js_runtime }
    }

    pub fn spawn_and_run_js_file(&self, file_path: &str) {
        let rt = self.rt.clone();
        std::thread::spawn(move || {
            let file_path = file_path.to_owned();
            println!("Running JavaScript file: {}", file_path);

            if let Err(error) = rt.block_on(Self::morphir_js(&file_path)) {
                eprintln!("error: {error}");
            }
        })
        .join()
        .unwrap();
    }

    async fn morphir_js(file_path: &str) -> Result<()> {
        let main_module = deno_core::resolve_path(file_path, env::current_dir()?.as_path())?;
        let mut js_runtime = deno_core::JsRuntime::new(deno_core::RuntimeOptions {
            module_loader: Some(Rc::new(TsModuleLoader)),
            startup_snapshot: Some(RUNTIME_SNAPSHOT),
            extensions: vec![morphirjs::init_ops()],
            ..Default::default()
        });

        let mod_id = js_runtime.load_main_es_module(&main_module).await?;
        let result = js_runtime.mod_evaluate(mod_id);
        js_runtime.run_event_loop(Default::default()).await?;
        match result {
            Ok(_) => Ok(()),
            Err(e) => Err(Error::DenoError(e)),

        }
    }
}

extension! {
    morphirjs,
    ops = [
        op_read_file,
        op_write_file,
        op_remove_file,
        op_fetch,
        op_set_timeout,
    ]
}
pub(crate) async fn morphir_js(file_path: &str) -> std::result::Result<(), AnyError> {
    let main_module = deno_core::resolve_path(file_path, env::current_dir()?.as_path())?;
    let mut js_runtime = deno_core::JsRuntime::new(deno_core::RuntimeOptions {
        module_loader: Some(Rc::new(TsModuleLoader)),
        startup_snapshot: Some(RUNTIME_SNAPSHOT),
        extensions: vec![crate::js_extensions::morphirjs::init_ops()],
        ..Default::default()
    });

    let mod_id = js_runtime.load_main_es_module(&main_module).await?;
    let result = js_runtime.mod_evaluate(mod_id);
    js_runtime.run_event_loop(Default::default()).await?;
    result.await
}
