//! Opt-in probe of the pinned canonical host's public Extism loader.
//! Build inside the canonical workspace to preserve its lockfile and features.
use morphir_host::HostError;
use morphir_host_native::extism::{ExtensionContainer, MorphirHostFunctions};

fn main() {
    let path = std::env::args_os().nth(1).expect("component path");
    let bytes = std::fs::read(path).expect("read validated component");
    assert!(
        bytes.starts_with(b"\0asm\x0d\0\x01\0"),
        "expected a component, not a core module"
    );
    let core_path = std::env::args_os()
        .nth(2)
        .expect("matching core module path");
    let core = std::fs::read(core_path).expect("read validated core module");
    assert!(
        core.starts_with(b"\0asm\x01\0\0\0"),
        "expected a core module control"
    );
    // This core fixture is not an Extism guest. Reaching the missing guest-info
    // export proves parsing succeeded, without claiming its ABI is supported.
    match ExtensionContainer::from_bytes(
        "core-host-control",
        &core,
        MorphirHostFunctions::default(),
    ) {
        Err(HostError::Invalid(message))
            if message
                == "Failed to get extension info: Function not found: morphir_extension_info" => {}
        Err(error) => panic!("unexpected core control failure: {error:?}"),
        Ok(_) => panic!("core fixture unexpectedly implements the Extism guest contract"),
    }
    match ExtensionContainer::from_bytes(
        "component-host-study",
        &bytes,
        MorphirHostFunctions::default(),
    ) {
        Err(HostError::Invalid(message))
            if message == "Failed to create plugin: failed to parse WebAssembly module" =>
        {
            println!("unsupported: {message}");
        }
        Err(error) => panic!("unexpected canonical host failure: {error:?}"),
        Ok(_) => panic!("canonical host changed: component unexpectedly loaded"),
    }
}
