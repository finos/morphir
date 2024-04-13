use extism_pdk::*;

#[host_fn("morphir:host/workspace-root")]
extern "ExtismHost" {
    fn workspace_root() -> String;
}
