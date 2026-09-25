//! The example workspace: the `yaml itest` fence that describes it, and the processor that
//! copies it into a new temporary root before a scenario's first step.
use super::{FrozenGoldens, ItestDirs, ItestRoot, KeepTemp, library::golden_file_step};
use crate::commands::itest::{
    document_dir,
    model::{self, Workspace},
    runner::{prepare_root, read_text, temporary_root},
    scenario_id_of,
    workspace::{materialize_example, validate_workspace_paths},
};
use anyhow::{Context as _, Result};
use morphir_evaluator::ProviderId;
use morphir_gherkin::{
    Document, Fence, NodePath, Scenario, Segment,
    extension::{Context, FenceExtension, Processor, Scope},
    visit::Node,
};
use serde::Deserialize;
use std::path::{Path, PathBuf};

/// The example's own directory and its workspace metadata, from its `yaml itest` fence.
#[derive(Debug, Clone)]
pub struct ExampleWorkspace {
    /// The directory of the example's scenario document. A directory workspace's `path` is
    /// relative to it.
    pub example_dir: PathBuf,
    /// Which inputs the example copies: a directory, or only its overlay files.
    pub workspace: model::Workspace,
}

/// One overlay file of a `yaml itest` fence, written into the project after the directory's
/// inputs. `scenarios.md` writes these as `morphir:file` fences.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExampleFile {
    /// The file's portable path, relative to the project.
    pub path: String,
    /// The file's content, exactly as written.
    pub content: String,
}

/// The body of a `yaml itest` fence:
/// `{ workspace?: <workspace>, provider?: rego, files?: [{path, content}] }`.
///
/// With no fence, or an empty one, the workspace is the example's whole directory with no
/// exclusions, the provider is `rego`, and there are no overlay files.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ExampleSpec {
    /// Which inputs the example copies into its project.
    #[serde(default)]
    pub workspace: model::Workspace,
    /// The evaluator provider that checks the example's assertions.
    #[serde(default = "rego")]
    pub provider: ProviderId,
    /// Files written into the project after the workspace's inputs.
    #[serde(default)]
    pub files: Vec<ExampleFile>,
}

fn rego() -> ProviderId {
    ProviderId::Rego
}

impl Default for ExampleSpec {
    fn default() -> Self {
        Self {
            workspace: Workspace::default(),
            provider: rego(),
            files: Vec::new(),
        }
    }
}

impl ExampleSpec {
    /// Parses and checks a `yaml itest` fence body. The workspace paths and the overlay paths
    /// must be portable relative paths, and the overlay paths must not conflict.
    pub fn parse(body: &str) -> Result<Self> {
        let value: serde_json::Value = if body.trim().is_empty() {
            serde_json::Value::Null
        } else {
            serde_saphyr::from_str(body).context("invalid YAML metadata")?
        };
        let value = if value.is_null() {
            serde_json::json!({})
        } else {
            value
        };
        let spec: Self = serde_json::from_value(value).context("invalid `yaml itest` fence")?;
        spec.workspace.validate()?;
        validate_workspace_paths(
            spec.files.iter().map(|file| file.path.as_str()),
            std::iter::empty(),
        )?;
        Ok(spec)
    }

    /// Adds the overlay files of a scenario's own `yaml itest` fence, `{ files?: [{path,
    /// content}] }`, and checks every overlay path again. `workspace` and `provider` belong only
    /// in the Feature's fence.
    fn add_scenario_files(&mut self, body: &str) -> Result<()> {
        let value: serde_json::Value = if body.trim().is_empty() {
            serde_json::Value::Null
        } else {
            serde_saphyr::from_str(body).context("invalid YAML metadata")?
        };
        if let Some(fields) = value.as_object() {
            anyhow::ensure!(
                !fields.contains_key("workspace") && !fields.contains_key("provider"),
                "the `workspace` and `provider` of a `yaml itest` fence belong in the Feature description"
            );
        }
        let value = if value.is_null() {
            serde_json::json!({})
        } else {
            value
        };
        let files: ScenarioFiles =
            serde_json::from_value(value).context("invalid `yaml itest` fence")?;
        self.files.extend(files.files);
        validate_workspace_paths(
            self.files.iter().map(|file| file.path.as_str()),
            std::iter::empty(),
        )
    }

    fn overlay(&self) -> impl Iterator<Item = (&str, &str)> + Clone {
        self.files
            .iter()
            .map(|file| (file.path.as_str(), file.content.as_str()))
    }
}

/// The body of a `yaml itest` fence in a Scenario description: `{ files?: [{path, content}] }`.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ScenarioFiles {
    #[serde(default)]
    files: Vec<ExampleFile>,
}

/// Marks a scenario whose own `yaml itest` fence has been applied.
#[derive(Debug)]
struct ScenarioFence;

/// A `FenceExtension` for the `yaml itest` fence. In the Feature description it holds the
/// frontmatter fields `workspace` and `provider`, and the overlay `files`, and inserts them as an
/// [`ExampleSpec`]. In a Scenario description it holds only `files`: overlay files of that
/// scenario alone, added to the Feature's (a `scenarios.md` section's `morphir:file` fences become
/// these). [`MaterializeExample`] turns the spec into the [`ExampleWorkspace`], since only a
/// processor sees the document's path.
///
/// It matches a fence whose language is `yaml` and whose info string has the word `itest`. The
/// Feature description and each Scenario description hold at most one.
pub struct ItestFence;

impl FenceExtension for ItestFence {
    fn matches(&self, fence: &Fence) -> bool {
        fence.info.language == "yaml" && fence.info.words.iter().any(|word| word == "itest")
    }

    fn apply(&self, fence: &Fence, scope: Scope, ctx: &mut Context) -> Result<(), String> {
        match scope {
            Scope::Feature => {
                if ctx.get::<ExampleSpec>().is_some() {
                    return Err("a Feature description holds at most one `yaml itest` fence".into());
                }
                ctx.insert(ExampleSpec::parse(&fence.body).map_err(|error| format!("{error:#}"))?);
            }
            Scope::Scenario => {
                if ctx.get::<ScenarioFence>().is_some() {
                    return Err(
                        "a Scenario description holds at most one `yaml itest` fence".into(),
                    );
                }
                let mut spec = ctx.get::<ExampleSpec>().cloned().unwrap_or_default();
                spec.add_scenario_files(&fence.body)
                    .map_err(|error| format!("{error:#}"))?;
                ctx.insert(spec);
                ctx.insert(ScenarioFence);
            }
            Scope::Rule | Scope::Examples => {
                return Err(
                    "the `yaml itest` fence belongs in the Feature description, or a Scenario \
                     description for that scenario's own files"
                        .into(),
                );
            }
        }
        Ok(())
    }
}

/// A `Processor`. It materializes the example into a new temporary root before the first step,
/// inserts [`ExampleWorkspace`] and [`ItestDirs`], and keeps the root when `KeepTemp(true)`,
/// printing `"{id}: retained {path}"` as today.
///
/// It needs an [`ItestRoot`] component, to name the scenario. It reads the [`ExampleSpec`] from a
/// `yaml itest` fence, or uses the default one. A failure fails the scenario with the reason.
pub struct MaterializeExample;

impl Processor for MaterializeExample {
    fn process(&self, doc: &Document, at: &NodePath, ctx: &mut Context) -> Result<(), String> {
        materialize(doc, at, ctx).map_err(|error| format!("{error:#}"))
    }
}

fn materialize(doc: &Document, at: &NodePath, ctx: &mut Context) -> Result<()> {
    let root = &ctx
        .get::<ItestRoot>()
        .context("no itest root: the suite needs an `ItestRoot` component")?
        .0;
    let id = scenario_id(root, doc, at)?;
    let keep = ctx.get::<KeepTemp>().is_some_and(|keep| keep.0);
    let spec = ctx.get::<ExampleSpec>().cloned().unwrap_or_default();
    let example = ExampleWorkspace {
        example_dir: example_dir(doc),
        workspace: spec.workspace.clone(),
    };
    // Freeze authored expectations before any CLI command can change files.
    let frozen = freeze_goldens(doc, at, &example.example_dir)?;
    let (temporary, guard) = temporary_root(&id, keep)?;
    prepare_root(&temporary, |project| {
        materialize_example(
            &example.example_dir,
            &example.workspace,
            spec.overlay(),
            project,
        )
    })?;
    ctx.insert(example);
    ctx.insert(ItestDirs::with_guard(temporary, guard));
    ctx.insert(frozen);
    Ok(())
}

/// Reads every golden file the steps of the scenario at `at` name (its own steps, and its
/// feature's and rule's backgrounds), relative to `example_dir`, through `runner::read_text`: a
/// path that is not portable, that traverses a symlink, or that is not a regular UTF-8 file fails
/// the scenario before its first step.
fn freeze_goldens(doc: &Document, at: &NodePath, example_dir: &Path) -> Result<FrozenGoldens> {
    let scenario = scenario_at(doc, at).with_context(|| format!("{at} is not a scenario"))?;
    let feature = doc
        .feature
        .as_ref()
        .context("the document has no Feature")?;
    let rule = at.segments().iter().find_map(|segment| match segment {
        Segment::Rule(index) => feature.rules.get(*index),
        _ => None,
    });
    let backgrounds = feature
        .background
        .iter()
        .chain(rule.and_then(|rule| rule.background.as_ref()));
    let mut frozen = FrozenGoldens::default();
    for step in backgrounds
        .flat_map(|background| &background.steps)
        .chain(&scenario.steps)
    {
        let Some(golden) = golden_file_step(&step.text) else {
            continue;
        };
        if frozen.0.contains_key(&golden.golden_file) {
            continue;
        }
        let text = read_text(example_dir, &golden.golden_file).with_context(|| {
            format!(
                "golden {:?}: load expectation before commands",
                golden.golden_file
            )
        })?;
        frozen.0.insert(golden.golden_file, text);
    }
    Ok(frozen)
}

/// The directory that holds `doc`.
fn example_dir(doc: &Document) -> PathBuf {
    document_dir(&doc.path)
}

/// The scenario at `at`, or the outline that owns the examples block at `at`.
fn scenario_at<'d>(doc: &'d Document, at: &NodePath) -> Option<&'d Scenario> {
    match doc.node(at)? {
        Node::Scenario(scenario) => Some(scenario),
        Node::Examples(_) => match doc.node(&at.parent()?)? {
            Node::Scenario(scenario) => Some(scenario),
            _ => None,
        },
        _ => None,
    }
}

/// The itest id of the scenario at `at` in `doc`: `<directory id>#<section>`. The directory id
/// is the document's directory relative to `root`, as `morphir itest` names directories today.
/// The section is the scenario's `@section:<id>` tag, or else today's section id of its name.
pub fn scenario_id(root: &Path, doc: &Document, at: &NodePath) -> Result<String> {
    let scenario = scenario_at(doc, at).with_context(|| format!("{at} is not a scenario"))?;
    let section = scenario.tags.iter().find_map(|tag| match tag.namespaced() {
        Some(("section", id)) => Some(id),
        _ => None,
    });
    scenario_id_of(root, &doc.path, &scenario.name, section)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::itest::steps::{FrozenGoldens, ItestDirs, ItestRoot, KeepTemp};
    use morphir_gherkin::{
        NodePath, Segment,
        extension::{Context, Extensions},
    };
    use std::{fs, path::Path};

    const FEATURE: &str = "@suite:offline
Feature: Compile a directory example
  ```yaml itest
  workspace: {kind: directory, path: ., exclude: [installed]}
  files:
    - {path: extra.txt, content: \"inline addition\\n\"}
  ```

  @section:compile-it
  Scenario: Compile it
    When I run \"morphir --version\"

  Scenario: Second One!
    When I run \"morphir --version\"
";

    fn example(root: &Path, feature: &str) -> std::path::PathBuf {
        let dir = root.join("elm/directory");
        fs::create_dir_all(dir.join("src")).unwrap();
        fs::create_dir_all(dir.join("installed")).unwrap();
        fs::write(dir.join("morphir.json"), "{}\n").unwrap();
        fs::write(dir.join("src/Main.elm"), "module Main exposing (..)\n").unwrap();
        fs::write(dir.join("installed/morphir-ir.json"), "{}\n").unwrap();
        fs::write(dir.join("scenarios.feature"), feature).unwrap();
        dir
    }

    fn context(root: &Path, dir: &Path, scenario: usize, keep: bool) -> Result<Context, String> {
        let (doc, _) = morphir_gherkin::read_document(&dir.join("scenarios.feature")).unwrap();
        let mut seed = Context::default();
        seed.insert(ItestRoot(root.to_owned()));
        seed.insert(KeepTemp(keep));
        Extensions::new()
            .with_fences(ItestFence)
            .with_processor(MaterializeExample)
            .context_for_seeded(
                &doc,
                &NodePath::feature().push(Segment::Scenario(scenario)),
                seed,
            )
            .map(|(context, _)| context)
            .map_err(|errors| {
                errors
                    .iter()
                    .map(ToString::to_string)
                    .collect::<Vec<_>>()
                    .join("\n")
            })
    }

    #[test]
    fn materialize_example_copies_the_directory_without_exclusions() {
        let temp = tempfile::tempdir().unwrap();
        let dir = example(temp.path(), FEATURE);
        let context = context(temp.path(), &dir, 0, false).unwrap();
        let dirs = context.get::<ItestDirs>().unwrap();
        assert_eq!(dirs.project, dirs.root.join("project"));
        assert_eq!(
            fs::read_to_string(dirs.project.join("morphir.json")).unwrap(),
            "{}\n"
        );
        assert!(dirs.project.join("src/Main.elm").is_file());
        assert_eq!(
            fs::read_to_string(dirs.project.join("extra.txt")).unwrap(),
            "inline addition\n"
        );
        assert!(dirs.project.join(".morphir").is_dir());
        assert!(dirs.root.join("home").is_dir());
        assert!(!dirs.project.join("installed").exists());
        assert!(!dirs.project.join("scenarios.feature").exists());
        let example = context.get::<ExampleWorkspace>().unwrap();
        assert_eq!(example.example_dir, dir);
        assert!(matches!(
            &example.workspace,
            model::Workspace::Directory { path, exclude } if path == "." && exclude == &["installed"]
        ));
        // The author's tree is never changed.
        assert!(!dir.join("extra.txt").exists());
        // The temporary root lives exactly as long as the scenario's context.
        let root = dirs.root.clone();
        drop(context);
        assert!(!root.exists());
    }

    #[test]
    fn materialize_example_keeps_the_root_on_request() {
        let temp = tempfile::tempdir().unwrap();
        let dir = example(temp.path(), FEATURE);
        let context = context(temp.path(), &dir, 1, true).unwrap();
        let root = context.get::<ItestDirs>().unwrap().root.clone();
        drop(context);
        assert!(root.join("project/morphir.json").is_file());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn materialize_example_without_a_fence_copies_the_whole_directory() {
        let temp = tempfile::tempdir().unwrap();
        let dir = example(
            temp.path(),
            "Feature: Plain\n  Scenario: S\n    When I run \"morphir --version\"\n",
        );
        let context = context(temp.path(), &dir, 0, false).unwrap();
        let dirs = context.get::<ItestDirs>().unwrap();
        assert!(dirs.project.join("installed/morphir-ir.json").is_file());
        assert!(dirs.project.join("src/Main.elm").is_file());
        assert!(!dirs.project.join("scenarios.feature").exists());
    }

    #[test]
    fn materialize_example_fails_with_the_reason() {
        let temp = tempfile::tempdir().unwrap();
        let dir = example(temp.path(), &FEATURE.replace("path: .,", "path: missing,"));
        let error = context(temp.path(), &dir, 0, false).unwrap_err();
        assert!(
            error.contains("workspace source must be a real directory"),
            "{error}"
        );
        let dir = example(
            temp.path(),
            &FEATURE.replace("path: extra.txt", "path: morphir.json"),
        );
        let error = context(temp.path(), &dir, 0, false).unwrap_err();
        assert!(
            error.contains("duplicate or conflicting workspace path"),
            "{error}"
        );
    }

    #[test]
    fn materialize_example_freezes_the_golden_files_the_steps_name() {
        let temp = tempfile::tempdir().unwrap();
        let feature = "Feature: Goldens\n  Background:\n    Then the file \"a\" at \"all\" should match the golden file \"golden/bg.txt\" with exact line endings\n\n  Scenario: S\n    When I run \"morphir --version\"\n    Then the file \"a\" at \"all\" should match the golden file \"golden/s.txt\" with LF line endings\n    Then the file \"a\" at \"all\" should match with exact line endings:\n      ```\n      inline\n      ```\n";
        let dir = example(temp.path(), feature);
        fs::create_dir_all(dir.join("golden")).unwrap();
        fs::write(dir.join("golden/bg.txt"), "background\n").unwrap();
        fs::write(dir.join("golden/s.txt"), "scenario\n").unwrap();
        let context = context(temp.path(), &dir, 0, false).unwrap();
        let frozen = &context.get::<FrozenGoldens>().unwrap().0;
        assert_eq!(frozen.len(), 2);
        assert_eq!(frozen["golden/bg.txt"], "background\n");
        assert_eq!(frozen["golden/s.txt"], "scenario\n");
        // A later change to the author's file does not reach the frozen text.
        fs::write(dir.join("golden/s.txt"), "changed\n").unwrap();
        assert_eq!(frozen["golden/s.txt"], "scenario\n");
    }

    #[test]
    fn materialize_example_fails_before_the_first_step_on_a_bad_golden_file() {
        let temp = tempfile::tempdir().unwrap();
        let feature = |golden: &str| {
            format!(
                "Feature: Goldens\n  Scenario: S\n    When I run \"morphir --version\"\n    Then the file \"a\" at \"all\" should match the golden file \"{golden}\" with exact line endings\n"
            )
        };
        let dir = example(temp.path(), &feature("missing.txt"));
        let error = context(temp.path(), &dir, 0, false).unwrap_err();
        assert!(
            error.contains("golden \"missing.txt\": load expectation before commands")
                && error.contains("is missing or is not a regular file"),
            "{error}"
        );
        let dir = example(temp.path(), &feature("../outside.txt"));
        let error = context(temp.path(), &dir, 0, false).unwrap_err();
        assert!(
            error.contains("load expectation before commands"),
            "{error}"
        );
        #[cfg(unix)]
        {
            let outside = tempfile::NamedTempFile::new().unwrap();
            std::os::unix::fs::symlink(outside.path(), dir.join("linked.txt")).unwrap();
            let dir = example(temp.path(), &feature("linked.txt"));
            let error = context(temp.path(), &dir, 0, false).unwrap_err();
            assert!(error.contains("assertion traverses a symlink"), "{error}");
        }
    }

    #[test]
    fn scenario_ids_use_the_section_tag_or_the_name() {
        let temp = tempfile::tempdir().unwrap();
        let dir = example(temp.path(), FEATURE);
        let (doc, _) = morphir_gherkin::read_document(&dir.join("scenarios.feature")).unwrap();
        let at = |i| NodePath::feature().push(Segment::Scenario(i));
        assert_eq!(
            scenario_id(temp.path(), &doc, &at(0)).unwrap(),
            "elm/directory#compile-it"
        );
        assert_eq!(
            scenario_id(temp.path(), &doc, &at(1)).unwrap(),
            "elm/directory#second-one"
        );
        assert_eq!(scenario_id(&dir, &doc, &at(0)).unwrap(), ".#compile-it");
    }

    fn fence(body: &str) -> Result<Context, String> {
        let text = format!(
            "Feature: F\n  ```yaml itest\n{body}  ```\n\n  Scenario: S\n    When I run \"morphir x\"\n"
        );
        let (doc, _) = morphir_gherkin::read_str("f.feature", &text).unwrap();
        Extensions::new()
            .with_fences(ItestFence)
            .context_for(&doc, &NodePath::feature().push(Segment::Scenario(0)))
            .map(|(context, _)| context)
            .map_err(|errors| errors[0].message.clone())
    }

    #[test]
    fn itest_fence_reads_the_workspace_provider_and_files() {
        let context = fence(
            "  provider: rego\n  workspace: {kind: inline}\n  files:\n    - {path: a/b.txt, content: x}\n",
        )
        .unwrap();
        let spec = context.get::<ExampleSpec>().unwrap();
        assert_eq!(spec.provider, morphir_evaluator::ProviderId::Rego);
        assert!(matches!(spec.workspace, model::Workspace::Inline {}));
        assert_eq!(spec.files.len(), 1);
        assert_eq!(spec.files[0].path, "a/b.txt");
        assert_eq!(spec.files[0].content, "x");

        let context = fence("").unwrap();
        let spec = context.get::<ExampleSpec>().unwrap();
        assert!(matches!(
            &spec.workspace,
            model::Workspace::Directory { path, exclude } if path == "." && exclude.is_empty()
        ));
        assert!(spec.files.is_empty());
    }

    #[test]
    fn itest_fence_rejects_invalid_bodies() {
        for (body, message) in [
            ("  unknown: 1\n", "unknown field"),
            (
                "  workspace: {kind: directory, path: ../up}\n",
                "invalid workspace directory",
            ),
            (
                "  workspace: {kind: directory, path: ., exclude: [/abs]}\n",
                "invalid workspace exclusion",
            ),
            (
                "  files:\n    - {path: a, content: \"x\"}\n    - {path: a, content: \"y\"}\n",
                "duplicate or conflicting workspace path",
            ),
            ("  provider: opa\n", "invalid `yaml itest` fence"),
        ] {
            let error = fence(body).unwrap_err();
            assert!(error.contains(message), "{body}: {error}");
        }
    }

    /// The context of scenario `index` of the `.feature` document `text`, with only
    /// [`ItestFence`], or the first error message.
    fn scenario_context(text: &str, index: usize) -> Result<Context, String> {
        let (doc, _) = morphir_gherkin::read_str("f.feature", text).unwrap();
        Extensions::new()
            .with_fences(ItestFence)
            .context_for(&doc, &NodePath::feature().push(Segment::Scenario(index)))
            .map(|(context, _)| context)
            .map_err(|errors| errors[0].message.clone())
    }

    #[test]
    fn itest_fence_in_a_scenario_adds_that_scenarios_own_files() {
        let text = "Feature: F\n  ```yaml itest\n  provider: rego\n  files:\n    - {path: shared.txt, content: s}\n  ```\n\n  Scenario: A\n    ```yaml itest\n    files:\n      - {path: extra.txt, content: a}\n    ```\n\n    When I run \"morphir x\"\n\n  Scenario: B\n    ```yaml itest\n    files:\n      - {path: extra.txt, content: b}\n    ```\n\n    When I run \"morphir x\"\n\n  Scenario: C\n    When I run \"morphir x\"\n";
        for (index, expected) in [
            (0, vec![("shared.txt", "s"), ("extra.txt", "a")]),
            (1, vec![("shared.txt", "s"), ("extra.txt", "b")]),
            (2, vec![("shared.txt", "s")]),
        ] {
            let context = scenario_context(text, index).unwrap();
            let spec = context.get::<ExampleSpec>().unwrap();
            assert_eq!(spec.provider, ProviderId::Rego);
            assert_eq!(spec.overlay().collect::<Vec<_>>(), expected);
        }
        // Without a Feature fence, a scenario's files join the default workspace.
        let text = "Feature: F\n  Scenario: A\n    ```yaml itest\n    files:\n      - {path: extra.txt, content: a}\n    ```\n\n    When I run \"morphir x\"\n";
        let context = scenario_context(text, 0).unwrap();
        let spec = context.get::<ExampleSpec>().unwrap();
        assert!(matches!(
            &spec.workspace,
            model::Workspace::Directory { path, exclude } if path == "." && exclude.is_empty()
        ));
        assert_eq!(spec.overlay().collect::<Vec<_>>(), [("extra.txt", "a")]);
    }

    #[test]
    fn itest_fence_in_a_scenario_holds_only_non_conflicting_files() {
        let scenario = |fences: &str| {
            format!(
                "Feature: F\n  ```yaml itest\n  files:\n    - {{path: shared.txt, content: s}}\n  ```\n\n  Scenario: A\n{fences}\n    When I run \"morphir x\"\n"
            )
        };
        let fence = |body: &str| format!("    ```yaml itest\n{body}    ```\n");
        for (fences, message) in [
            (
                fence("    workspace: {kind: inline}\n"),
                "belong in the Feature description",
            ),
            (fence("    unknown: 1\n"), "unknown field"),
            (
                fence("    files:\n      - {path: shared.txt, content: t}\n"),
                "duplicate or conflicting workspace path",
            ),
            (
                fence("    files:\n      - {path: ../up, content: t}\n"),
                "path escapes the workspace",
            ),
            (
                fence("    files: []\n") + "\n" + &fence("    files: []\n"),
                "at most one",
            ),
        ] {
            let error = scenario_context(&scenario(&fences), 0).unwrap_err();
            assert!(error.contains(message), "{fences}: {error}");
        }
    }

    #[test]
    fn itest_fence_belongs_in_the_feature_description() {
        let text = "Feature: F\n  Scenario: S\n    ```yaml itest\n    provider: rego\n    ```\n\n    When I run \"morphir x\"\n";
        let (doc, _) = morphir_gherkin::read_str("f.feature", text).unwrap();
        let errors = Extensions::new()
            .with_fences(ItestFence)
            .context_for(&doc, &NodePath::feature().push(Segment::Scenario(0)))
            .unwrap_err();
        assert!(
            errors[0].message.contains("Feature description"),
            "{}",
            errors[0].message
        );
    }
}
