//! Canonical local-repository and verified installation services.
use super::{Result, host, text, verified};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use morphir_common::home::MorphirHome;
use morphir_distribution::*;
use morphir_host::{Description, DescriptionSource};
use morphir_host_native::process::{ProcessChannel, ProcessLaunch};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{ffi::OsStr, path::Path, time::Duration};

#[derive(Deserialize)]
pub(super) enum Action {
    #[serde(rename = "extension bundle")]
    Bundle,
    #[serde(rename = "extension install")]
    Install,
    #[serde(rename = "extension update")]
    Update,
    #[serde(rename = "extension list")]
    List,
    #[serde(rename = "extension search")]
    Search,
    #[serde(rename = "extension uninstall")]
    Uninstall,
    #[serde(rename = "extension repository init")]
    Init,
    #[serde(rename = "extension repository add")]
    Add,
    #[serde(rename = "extension repository list")]
    Repositories,
    #[serde(rename = "extension repository inspect")]
    Inspect,
    #[serde(rename = "extension repository enable")]
    Enable,
    #[serde(rename = "extension repository disable")]
    Disable,
    #[serde(rename = "extension repository remove")]
    Remove,
    #[serde(rename = "extension repository publish")]
    Publish,
    #[serde(rename = "extension repository verify")]
    Verify,
}

async fn describe(id: &str, bytes: &[u8], args: &[String]) -> Result<Description> {
    let work = tempfile::tempdir()?;
    let program = work.path().join("guest");
    std::fs::write(&program, bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o500))?;
    }
    let launch = args.iter().fold(
        ProcessLaunch::new(id, &program, work.path()).request_timeout(Duration::from_secs(10)),
        |launch, arg| launch.arg(arg),
    );
    let channel = ProcessChannel::spawn(launch).await?;
    let description =
        morphir_host::describe(super::diagnostics::Diagnostics::new(channel), &host(), id).await?;
    if std::fs::read_dir(work.path())?.count() != 1 {
        return Err("native probe wrote unexpected files".into());
    }
    Ok(description)
}

async fn probe(artifact: &VerifiedArtifact) -> morphir_distribution::Result<ClaimsRecord> {
    let selected = artifact.selected().artifact();
    if selected.runtime() != ArtifactRuntime::Process {
        return Err(DistributionError::Probe(
            "only local native process artifacts are supported".into(),
        ));
    }
    let declared = selected
        .claims()
        .expect("canonical resolved artifact has claims");
    let record = selected.declared_claims_record();
    let description = describe(
        &declared.extension.id,
        &std::fs::read(artifact.path()).map_err(|e| DistributionError::Probe(e.to_string()))?,
        selected.args(),
    )
    .await
    .map_err(|e| DistributionError::Probe(e.to_string()))?;
    let source = match description.source {
        DescriptionSource::Describe => {
            record
                .check_described(&description.claims)
                .map_err(|e| DistributionError::Probe(e.to_string()))?;
            ProbeSource::Describe
        }
        DescriptionSource::SessionFallback => {
            record
                .check_session(
                    &description.claims.protocol_versions[0],
                    &description.claims.extension,
                    &description.claims.capabilities,
                )
                .map_err(|e| DistributionError::Probe(e.to_string()))?;
            ProbeSource::SessionFallback
        }
    };
    Ok(record.probed(source))
}

async fn bundle(v: &Value) -> Result<Value> {
    let bytes = verified(v)?;
    if bytes.len() > 11 * 1024 * 1024 {
        return Err("native.bundle_artifact_limit: maximum 11 MiB".into());
    }
    let id = ExtensionId::parse(text(v, "extension-id")?)?;
    let platform = text(v, "platform")?;
    if platform != env!("MORPHIR_NATIVE_TARGET") {
        return Err("bundle platform must match the probing host".into());
    }
    let description = describe(id.as_str(), &bytes, &[]).await?;
    let version = text(v, "version")?;
    if description.claims.extension.version != version {
        return Err("bundle version differs from described version".into());
    }
    let filename = Path::new(text(v, "executable")?)
        .file_name()
        .and_then(OsStr::to_str)
        .ok_or("invalid filename")?;
    let filename = ArtifactFilename::parse(filename)?;
    if filename.as_str().eq_ignore_ascii_case("release.json") {
        return Err("reserved executable filename".into());
    }
    let digest = Sha256Digest::of_bytes(&bytes);
    let descriptor = json!({"schemaVersion":"2.0.0-draft.2", "extensionId":id,"shortId":text(v,"short-id")?,"version":version,
        "platformDifferences":"none", "artifacts":[{"runtime":"process","platform":platform,"filename":filename,"sha256":digest,"claims":description.claims,"claimCheck":"unchecked"}]});
    let descriptor_bytes = serde_json::to_vec_pretty(&descriptor)?;
    ReleaseBundleDescriptor::parse_json(&descriptor_bytes)?;
    let artifact = |path: String, content: Vec<u8>| json!({"path":path,"content":STANDARD.encode(content),"binary":true});
    Ok(json!({"success":true,"descriptor":descriptor,"artifacts":[
        artifact(filename.as_str().into(),bytes), artifact("release.json".into(),descriptor_bytes),
        artifact(format!("{}.sha256", filename.as_str()),format!("{digest}  {}\n",filename.as_str()).into_bytes())]}))
}

pub(super) async fn run(v: &Value, action: Action) -> Result<Value> {
    if matches!(action, Action::Bundle) {
        return bundle(v).await;
    }
    let home = MorphirHome::resolve_from(Some(OsStr::new(text(v, "home")?)), None)?;
    let repositories = ExtensionRepositories::new(&home);
    let path = v["path"].as_str().unwrap_or("");
    let name = || RepositoryName::parse(path);
    let version = semver::Version::parse("0.1.0")?;
    match action {
        Action::Init => {
            let repo = LocalExtensionRepository::init(path)?;
            Ok(json!({"directory":repo.root()}))
        }
        Action::Add => Ok(serde_json::to_value(repositories.add(
            name()?,
            RepositoryEndpoint::local_directory(text(v, "directory")?)?,
        )?)?),
        Action::Repositories => Ok(serde_json::to_value(repositories.list()?)?),
        Action::Inspect => Ok(serde_json::to_value(repositories.get(&name()?)?)?),
        Action::Enable => Ok(serde_json::to_value(repositories.enable(&name()?)?)?),
        Action::Disable => Ok(serde_json::to_value(repositories.disable(&name()?)?)?),
        Action::Remove => Ok(serde_json::to_value(repositories.remove(&name()?)?)?),
        Action::Verify => {
            let proof = repositories.verify(&name()?)?;
            Ok(json!({"histories":proof.history_count(),"releases":proof.release_count()}))
        }
        Action::Search => Ok(Value::Array(
            repositories
                .search(&ExtensionSearchQuery::parse(path)?)?
                .iter()
                .map(|r| json!({"repository":r.repository(),"release":r.release()}))
                .collect(),
        )),
        Action::List => {
            let entries = list_installed(&home)?;
            // Offline replay rehashes each installed artifact. Inventory never activates code.
            let results: Result<Vec<Value>> = entries.iter().map(|snapshot| {
                let activated = activate_installed_snapshot(&home, snapshot)?;
                Ok(json!({"installed":snapshot.installed(),"selection":snapshot.selection(),"verified":true,"extension":activated.extension_info()}))
            }).collect();
            Ok(Value::Array(results?))
        }
        Action::Uninstall => Ok(serde_json::to_value(uninstall_extension(
            &home,
            &ExtensionId::parse(path)?,
        )?)?),
        Action::Publish => {
            let configured = repositories.get(&RepositoryName::parse(text(v, "repository")?)?)?;
            if configured.state() != RepositoryState::Enabled {
                return Err("repository is disabled".into());
            }
            let root = configured
                .endpoint()
                .local_directory_path()
                .ok_or("local repository required")?
                .to_owned();
            let path = path.to_owned();
            let runtime = tokio::runtime::Handle::current();
            let published = tokio::task::spawn_blocking(move || {
                LocalExtensionRepository::open(root)?.publish_with_process_probe(
                    path,
                    |artifact, bytes| {
                        let description = runtime
                            .block_on(describe(&artifact.claims().extension.id, bytes, &[]))
                            .map_err(|e| DistributionError::Probe(e.to_string()))?;
                        match description.source {
                            DescriptionSource::Describe => {
                                Ok(PublicationDescription::Describe(description.claims))
                            }
                            DescriptionSource::SessionFallback => Err(DistributionError::Probe(
                                "publication requires direct describe".into(),
                            )),
                        }
                    },
                )
            })
            .await??;
            Ok(
                json!({"status":format!("{:?}",published.status()),"release":published.release(),"artifactPath":published.artifact_path()}),
            )
        }
        Action::Install | Action::Update => {
            let id = ExtensionId::parse(path)?;
            let existing = list_installed(&home)?;
            let installed = existing.iter().any(|s| s.installed().extension_id() == &id);
            if installed != matches!(action, Action::Update) {
                return Err(
                    "install requires an absent extension; update requires an installed extension"
                        .into(),
                );
            }
            let selection = Selection::Exact(semver::Version::parse(text(v, "version")?)?);
            let selected = repositories.resolve(
                &RepositoryName::parse(text(v, "repository")?)?,
                &id,
                selection,
                &Platform::current(),
                &version,
            )?;
            let installer = ExtensionInstaller::new(&home);
            if matches!(action, Action::Install) {
                let entry = installer
                    .install_with_probe(selected, &version, async |a| probe(a).await)
                    .await?;
                Ok(
                    json!({"installed":entry,"probe":"canonical describe","activation": "verified before commit"}),
                )
            } else {
                // The shared replacement installer has no probe callback. Probe the
                // immutable resolved digest in an isolated home before calling it;
                // install rechecks the same digest and commits under its state lock.
                let stage = tempfile::tempdir_in(home.root())?;
                let staging = MorphirHome::resolve_from(Some(stage.path().as_os_str()), None)?;
                let artifact = ArtifactStore::from_home(&staging).materialize(selected.clone())?;
                let checked = probe(&artifact).await?;
                let entry = installer.install(selected, &version)?;
                Ok(
                    json!({"installed":entry,"probe":checked,"activation":"verified before commit","lockProbe":"canonical replacement retains repository claim record"}),
                )
            }
        }
        Action::Bundle => unreachable!(),
    }
}
