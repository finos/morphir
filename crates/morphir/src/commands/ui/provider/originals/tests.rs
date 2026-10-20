use super::*;
use crate::commands::ui::provider::WorkspaceCapability;

#[test]
fn startup_grant_requires_actual_held_directory_identity_and_absolute_label() {
    let a = tempfile::tempdir().unwrap();
    let b = tempfile::tempdir().unwrap();
    let directory = Dir::open_ambient_dir(a.path(), cap_std::ambient_authority()).unwrap();
    for label in [b.path(), Path::new("relative-root")] {
        assert!(
            HostOutputLookup::issue(
                &directory,
                label,
                &ConfigLoadOptions::project_only(),
                &OutOverrides::default(),
                cap_std::ambient_authority()
            )
            .is_err()
        );
    }
    assert!(
        HostOutputLookup::issue(
            &directory,
            a.path(),
            &ConfigLoadOptions::project_only(),
            &OutOverrides::default(),
            cap_std::ambient_authority()
        )
        .unwrap()
        .granted()
        .is_ok()
    );
}

fn provider(root: &Path, options: ConfigLoadOptions, out: OutOverrides) -> NativeWorkspaceProvider {
    NativeWorkspaceProvider::discover_with_options(root, "source-authored-output-cases", options)
        .unwrap()
        .with_out_overrides(out)
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap()
}
async fn resolve(
    provider: NativeWorkspaceProvider,
    relative: &str,
) -> Result<SourceResolution, ProviderCaptureError> {
    let source = provider.initial_sources().pop().unwrap();
    let selection = OriginalsSelection::parse(&source, &project_key(&source, relative)).unwrap();
    OriginalsProvider::Native(Arc::new(provider))
        .resolve(&selection, &HostModelCaptureCapacity::default())
        .await
}
fn project(root: &Path) {
    std::fs::create_dir_all(root).unwrap();
    std::fs::write(
        root.join("morphir.toml"),
        "[project]\nname='acme/orders'\nversion='1.0.0'\n",
    )
    .unwrap();
}

struct ReplaceSelectedProject {
    path: PathBuf,
    retired: PathBuf,
}
impl LookupHooks for ReplaceSelectedProject {
    fn before_current(&self) {
        std::fs::rename(&self.path, &self.retired).unwrap();
        std::fs::create_dir(&self.path).unwrap();
        std::fs::write(
            self.path.join("morphir.toml"),
            "[invalid replacement config",
        )
        .unwrap();
    }
}
#[tokio::test]
async fn selected_project_replacement_is_refused_before_replacement_config_read() {
    let root = tempfile::tempdir().unwrap();
    let member = root.path().join("packages/orders");
    project(&member);
    std::fs::write(
        root.path().join("morphir.toml"),
        "[workspace]\nmembers=['packages/*']\n",
    )
    .unwrap();
    let provider = provider(
        root.path(),
        ConfigLoadOptions::project_only(),
        OutOverrides::default(),
    )
    .with_originals_lookup_hooks(Arc::new(ReplaceSelectedProject {
        path: member,
        retired: root.path().join("retired"),
    }));
    let result = resolve(provider, "packages/orders").await;
    let Err(ProviderCaptureError::Authority(error)) = result else {
        panic!("expected selected project refusal")
    };
    assert!(
        error.to_string().contains("selected project changed"),
        "{error}"
    );
    assert!(!root.path().join(".morphir/out").exists());
}

#[derive(Default)]
struct ModuleCopyCounter(std::sync::atomic::AtomicUsize);
impl LookupHooks for ModuleCopyCounter {
    fn before_module_copy(&self) {
        self.0.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    }
}
#[tokio::test]
async fn long_actual_module_refuses_before_its_first_witness_copy() {
    let root = tempfile::tempdir().unwrap();
    let member = root.path().join("packages/orders");
    project(&member);
    std::fs::write(
        root.path().join("morphir.toml"),
        "[workspace]\nmembers=['packages/*']\n",
    )
    .unwrap();
    let exports = tempfile::tempdir().unwrap();
    let counter = Arc::new(ModuleCopyCounter::default());
    let provider = provider(
        &member,
        ConfigLoadOptions::project_only(),
        OutOverrides {
            flag: Some(exports.path().to_owned()),
            env: None,
        },
    )
    .with_originals_lookup_hooks(counter.clone());
    let source = provider.initial_sources().pop().unwrap();
    let selection = OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap();
    let capacity =
        HostModelCaptureCapacity::with_metadata_limit(std::mem::size_of::<ResolvedProjectSource>());
    let result = OriginalsProvider::Native(Arc::new(provider))
        .resolve(&selection, &capacity)
        .await;
    assert!(matches!(
        result,
        Err(ProviderCaptureError::Capture(CaptureError::Capacity))
    ));
    assert_eq!(counter.0.load(std::sync::atomic::Ordering::SeqCst), 0);
    assert_eq!(
        capacity.usage(),
        crate::commands::ui::model_originals::ModelCaptureUsage::default()
    );
}

#[tokio::test]
async fn opened_member_dot_uses_actual_enclosing_current_module_and_original_output_grant() {
    let root = tempfile::tempdir().unwrap();
    let member = root.path().join("a/b/c/orders");
    project(&member);
    std::fs::write(
        root.path().join("morphir.toml"),
        "[workspace]\nmembers=['a/**/orders']\nout_dir='shared'\n",
    )
    .unwrap();
    let exports = tempfile::tempdir().unwrap();
    let actual = resolve(
        provider(
            &member,
            ConfigLoadOptions::project_only(),
            OutOverrides {
                flag: Some(exports.path().to_owned()),
                env: Some("ignored".into()),
            },
        ),
        ".",
    )
    .await
    .unwrap();
    let SourceResolution::Compiled(actual) = actual else {
        panic!("expected actual output grant")
    };
    assert_eq!(actual.module().as_str(), "a/b/c/orders");
    assert!(actual.output().entries().unwrap().next().is_none());
    let refused = resolve(
        provider(
            &member,
            ConfigLoadOptions::project_only(),
            OutOverrides::default(),
        ),
        ".",
    )
    .await;
    assert!(matches!(refused, Err(ProviderCaptureError::Authority(_))));
    assert!(!root.path().join("shared").exists());
}

#[tokio::test]
async fn output_policy_reuses_real_system_global_current_layers_without_portable_filter() {
    use morphir_devkit::config::SourceSelection;
    let root = tempfile::tempdir().unwrap();
    project(root.path());
    let layers = tempfile::tempdir().unwrap();
    let system = layers.path().join("system.toml");
    let global = layers.path().join("global.toml");
    std::fs::write(&system, "[workspace]\nout_dir='system'\n").unwrap();
    std::fs::write(&global, "[workspace]\nout_dir='global'\n").unwrap();
    std::fs::create_dir(root.path().join("global")).unwrap();
    std::fs::write(root.path().join("global/binding"), "global winner").unwrap();
    let mut options = ConfigLoadOptions::project_only();
    options.system = SourceSelection::Explicit(system);
    options.global = SourceSelection::Explicit(global);
    let actual = resolve(provider(root.path(), options, OutOverrides::default()), ".")
        .await
        .unwrap();
    let SourceResolution::Compiled(actual) = actual else {
        panic!("expected global output")
    };
    assert_eq!(actual.module().as_str(), "");
    assert_eq!(
        actual.output().read_to_string("binding").unwrap(),
        "global winner"
    );
}

#[tokio::test]
async fn source_formats_keep_real_toml_yaml_and_legacy_json_current_semantics() {
    for (name, contents) in [
        (
            "morphir.toml",
            "project.name='acme/orders'\nproject.version='1.0.0'\n",
        ),
        (
            "morphir.yaml",
            "project:\n  name: acme/orders\n  version: 1.0.0\n",
        ),
        (
            "morphir.json",
            r#"{"name":"Acme.Orders","sourceDirectory":"src","exposedModules":[],"ignored":1,"ignored":2}"#,
        ),
    ] {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(root.path().join(name), contents).unwrap();
        std::fs::create_dir_all(root.path().join(".morphir/out")).unwrap();
        let actual = resolve(
            provider(
                root.path(),
                ConfigLoadOptions::project_only(),
                OutOverrides::default(),
            ),
            ".",
        )
        .await
        .unwrap();
        let SourceResolution::Compiled(actual) = actual else {
            panic!("{name}: missing output")
        };
        assert_eq!(actual.module().as_str(), "", "{name}");
    }
}
