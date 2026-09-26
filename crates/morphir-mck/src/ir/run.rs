//! The run loop (IR suite README, "What the driver does with a case"). It
//! never parses YAML and never looks inside a canonical: an adapter returns
//! strings, and strings are compared. What an implementation cannot do is a
//! capabilities question, so a fence it declared no support for is skipped,
//! never failed.
//!
//! This is a port of the first driver's `run.ts`: record identity, order,
//! skip reasons and messages are the ones that driver wrote, so reports from
//! the two runners compare field by field (`spec/mck/migration.md`).

use regex::Regex;
use serde_json::{Map, Value};

use super::compare::{
    canonical_diff, check_canonical, check_rejected, check_warnings, describe, normalize_canonical,
    path_budget_of,
};
use crate::kit::load::{Kit, Profile as KitProfile};
use crate::kit::syntax::case::{Compare, KitCase, KitError, KitFence, Status};
use crate::kit::syntax::info_string::{Language, Role as FenceRole, set_label};
use crate::report::{Millis, Outcome, Record, RecordProfile, Report, ReportDiagnostic, Role};
use crate::transport::protocol::{
    Capabilities, DecodeResponse, Layout, PathMode, Profile, Request, TreeFile, WritePolicy,
    WriteTreeResponse, parse_capabilities, parse_decode_response, parse_write_tree_response,
};

/// The version a case without `version=` is decoded at.
pub const CURRENT_VERSION: i64 = 4;
/// The case id a kit error is reported under when no case contains it.
pub const KIT_ERROR_CASE: &str = "kit-0000";
/// The logical path of a document tree's root file, which carries the budget.
const MANIFEST: &str = "manifest";

/// Whatever answers the protocol: an adapter process, or a recording.
pub trait Testee {
    /// Sends one request and returns the body of its answer, or why the
    /// conversation ended. Any error ends the run's use of this testee.
    fn exchange(&mut self, request: &Request) -> Result<Map<String, Value>, String>;
}

impl Testee for crate::transport::Session {
    fn exchange(&mut self, request: &Request) -> Result<Map<String, Value>, String> {
        crate::transport::Session::exchange(self, request).map_err(|error| error.to_string())
    }
}

pub struct RunOptions<'a> {
    /// Selects cases by id; unanchored, as a search.
    pub filter: Option<&'a Regex>,
    pub driver_version: String,
    pub kit_version: String,
    pub started_at: String,
    /// Milliseconds from any fixed origin, for durations.
    pub clock: &'a dyn Fn() -> f64,
}

/// A finished run.
pub struct Run {
    pub report: Report,
    /// `<binding> supports IR format versions <table> (<prose>)`, for the
    /// caller to print where it likes; `None` when capabilities failed.
    pub header: Option<String>,
    pub capabilities: Option<Capabilities>,
    /// Session failures remain visible even when the selection has no fences.
    pub failure: Option<RunFailure>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RunFailure {
    Capabilities(String),
    Exchange(String),
}

/// A fence ready to send: its profile and body, or why it has none.
struct Target<'k> {
    fence: &'k KitFence,
    role: Role,
    profile: RecordProfile,
    /// The serialization the fence is written in. For every role but `file`
    /// it matches `profile`; a file fence is judged as the tree layout but
    /// still read as json or yaml.
    language: Profile,
    body: Result<String, String>,
}

fn role_of(role: FenceRole) -> Role {
    match role {
        FenceRole::Canonical => Role::Canonical,
        FenceRole::Accepted => Role::Accepted,
        FenceRole::Rejected => Role::Rejected,
        FenceRole::File => Role::File,
    }
}

fn protocol_profile(language: Language) -> Profile {
    match language {
        Language::Yaml => Profile::Yaml,
        // A text fence's own language says nothing; its target decides.
        Language::Json | Language::Text => Profile::Json,
    }
}

fn record_profile(profile: Profile) -> RecordProfile {
    match profile {
        Profile::Json => RecordProfile::Json,
        Profile::Yaml => RecordProfile::Yaml,
    }
}

fn target_of<'k>(kit: &Kit, fence: &'k KitFence) -> Target<'k> {
    let role = role_of(fence.info.role);
    let resolved = (fence.info.language == Language::Text).then(|| kit.resolve_text(fence));
    let (language, body) = match resolved {
        None => (
            protocol_profile(fence.info.language),
            Ok(fence.body.clone()),
        ),
        Some(Ok(text)) => {
            let language = match text.profile {
                KitProfile::Json => Profile::Json,
                KitProfile::Yaml => Profile::Yaml,
            };
            (language, Ok(text.content))
        }
        Some(Err(message)) => (Profile::Json, Err(message)),
    };
    let profile = if role == Role::File {
        RecordProfile::Tree
    } else {
        record_profile(language)
    };
    Target {
        fence,
        role,
        profile,
        language,
        body,
    }
}

/// A fence's verdict before its identity is attached.
#[derive(Debug, Clone, PartialEq)]
struct Verdict {
    result: Outcome,
    expected_diagnostic: Option<String>,
    observed_diagnostic: Option<ReportDiagnostic>,
    message: Option<String>,
    diff: Option<String>,
}

struct WriteIssue {
    fence_index: usize,
    message: String,
    diff: Option<String>,
}

impl Verdict {
    fn new(result: Outcome, message: Option<String>) -> Self {
        Self {
            result,
            expected_diagnostic: None,
            observed_diagnostic: None,
            message,
            diff: None,
        }
    }

    fn pass() -> Self {
        Self::new(Outcome::Pass, None)
    }

    fn fail(message: String) -> Self {
        Self::new(Outcome::Fail, Some(message))
    }

    fn kit_error(message: String) -> Self {
        Self::new(Outcome::KitError, Some(message))
    }

    fn skipped(message: String) -> Self {
        Self::new(Outcome::Skipped, Some(message))
    }
}

fn record(
    case: &KitCase,
    version: i64,
    target: &Target,
    path: PathMode,
    verdict: Verdict,
    duration: f64,
) -> Record {
    Record {
        case_id: case.id.as_str().to_owned(),
        ir_version: version,
        profile: target.profile,
        role: target.role,
        fence_index: target.fence.index,
        path: Some(path),
        result: verdict.result,
        expected_diagnostic: verdict.expected_diagnostic,
        observed_diagnostic: verdict.observed_diagnostic,
        message: verdict.message,
        check: None,
        diff: verdict.diff,
        duration_ms: Millis(duration.max(0.0)),
    }
}

/// The nearest case whose heading precedes the error, in the error's file.
fn owner_of<'k>(cases: &'k [KitCase], error: &KitError) -> Option<&'k KitCase> {
    cases
        .iter()
        .filter(|c| c.file == error.file && c.line <= error.line)
        .max_by_key(|c| c.line)
}

fn unsupported(
    caps: &Capabilities,
    version: i64,
    profile: RecordProfile,
    path: PathMode,
    node: Option<&str>,
) -> Option<String> {
    if !node.is_some_and(|node| caps.nodes.iter().any(|n| n == node)) {
        return Some(format!(
            "node {} not in capabilities",
            node.unwrap_or("unset")
        ));
    }
    if !u32::try_from(version).is_ok_and(|v| caps.versions.contains(&v)) {
        return Some(format!("version {version} not in capabilities"));
    }
    let profile = match profile {
        RecordProfile::Tree => {
            return (!caps.layouts.contains(&Layout::Tree))
                .then(|| "layout tree not in capabilities".to_owned());
        }
        RecordProfile::Json => Profile::Json,
        RecordProfile::Yaml => Profile::Yaml,
    };
    if !caps.profiles.contains(&profile.into()) {
        return Some(format!("profile {profile} not in capabilities"));
    }
    (!caps.paths.contains(&path)).then(|| format!("path {path} not in capabilities"))
}

/// Expected identity and legitimate skip reason, derived without an adapter or results.
pub(crate) struct InventoryEntry {
    pub case_id: String,
    pub ir_version: i64,
    pub profile: RecordProfile,
    pub role: Role,
    pub fence_index: usize,
    pub path: Option<PathMode>,
    pub skip: Option<String>,
    pub kit_error: Option<String>,
}

impl InventoryEntry {
    pub fn matches(&self, record: &Record) -> bool {
        self.case_id == record.case_id
            && self.ir_version == record.ir_version
            && self.profile == record.profile
            && self.role == record.role
            && self.fence_index == record.fence_index
            && self.path == record.path
    }
}

pub(crate) fn inventory(
    kit: &Kit,
    caps: &Capabilities,
    filter: Option<&Regex>,
) -> Vec<InventoryEntry> {
    let mut entries: Vec<_> = kit
        .errors
        .iter()
        .map(|error| InventoryEntry {
            case_id: owner_of(&kit.cases, error)
                .map_or_else(|| KIT_ERROR_CASE.to_owned(), |c| c.id.as_str().to_owned()),
            ir_version: CURRENT_VERSION,
            profile: RecordProfile::Json,
            role: Role::Canonical,
            fence_index: 0,
            path: None,
            skip: None,
            kit_error: Some(format!("{}:{}: {}", error.file, error.line, error.message)),
        })
        .collect();
    for case in &kit.cases {
        if filter.is_some_and(|f| !f.is_match(case.id.as_str())) {
            continue;
        }
        let version = case.version.unwrap_or(CURRENT_VERSION);
        let targets: Vec<_> = case.fences.iter().map(|f| target_of(kit, f)).collect();
        let sets = file_sets(&targets);
        for &path in &caps.paths {
            let mut per_path: Vec<_> = targets
                .iter()
                .map(|target| {
                    let skip = if case.status == Status::Pending {
                        Some("pending".to_owned())
                    } else if target.body.is_err() {
                        None
                    } else if target.role == Role::File {
                        let members = sets
                            .iter()
                            .find(|(_, members)| {
                                members.iter().any(|t| t.fence.index == target.fence.index)
                            })
                            .map(|(_, m)| m);
                        members.and_then(|members| {
                            if members.iter().any(|t| t.body.is_err()) {
                                return None;
                            }
                            unsupported(
                                caps,
                                version,
                                RecordProfile::Tree,
                                path,
                                case.node.as_deref(),
                            )
                            .or_else(|| {
                                let language = members[0].language;
                                (members.iter().all(|t| t.language == language)
                                    && !caps.profiles.contains(&language.into()))
                                .then(|| format!("profile {language} not in capabilities"))
                            })
                        })
                    } else {
                        unsupported(caps, version, target.profile, path, case.node.as_deref())
                    };
                    InventoryEntry {
                        case_id: case.id.as_str().to_owned(),
                        ir_version: version,
                        profile: target.profile,
                        role: target.role,
                        fence_index: target.fence.index,
                        path: Some(path),
                        skip,
                        kit_error: None,
                    }
                })
                .collect();
            per_path.sort_by_key(|entry| entry.fence_index);
            entries.extend(per_path);
        }
    }
    entries
}

fn decode(testee: &mut dyn Testee, request: &Request) -> Result<DecodeResponse, String> {
    let body = testee.exchange(request)?;
    parse_decode_response(&Value::Object(body)).map_err(|error| error.0)
}

fn write_tree(testee: &mut dyn Testee, request: &Request) -> Result<WriteTreeResponse, String> {
    let body = testee.exchange(request)?;
    parse_write_tree_response(&Value::Object(body)).map_err(|error| error.0)
}

fn judge_accepted(
    target: &Target,
    response: &DecodeResponse,
    expected: Option<&str>,
    case_id: &str,
) -> Verdict {
    let (canonical, warnings) = match response {
        DecodeResponse::Rejected(d) => {
            return Verdict {
                observed_diagnostic: Some(d.into()),
                ..Verdict::fail(format!(
                    "{} fence failed to decode: {}",
                    role_name(target.role),
                    describe(d)
                ))
            };
        }
        DecodeResponse::Ok {
            canonical,
            warnings,
            ..
        } => (canonical, warnings),
    };
    if let Some(problem) = check_warnings(target.fence.info.key("warning"), warnings) {
        return Verdict::fail(problem);
    }
    let Some((_, got)) = canonical
        .iter()
        .find(|(p, _)| record_profile(*p) == target.profile)
    else {
        return Verdict::fail(format!(
            "adapter returned no {} canonical",
            profile_name(target.profile)
        ));
    };
    let body = target.body.as_deref().unwrap_or("");
    let want = match expected {
        Some(expected) => expected,
        // A canonical fence with no sibling of its own profile is its own expectation.
        None if target.role == Role::Canonical => normalize_canonical(body),
        None => {
            return Verdict::kit_error(format!(
                "no canonical {} fence in {case_id}",
                profile_name(target.profile)
            ));
        }
    };
    match check_canonical(want, got) {
        None => Verdict::pass(),
        Some(reason) => Verdict {
            diff: Some(canonical_diff(
                want,
                got,
                &format!(
                    "{case_id} fence {} profile {}",
                    target.fence.index,
                    profile_name(target.profile)
                ),
            )),
            ..Verdict::fail(reason)
        },
    }
}

fn role_name(role: Role) -> &'static str {
    match role {
        Role::Canonical => "canonical",
        Role::Accepted => "accepted",
        Role::Rejected => "rejected",
        Role::File => "file",
    }
}

fn profile_name(profile: RecordProfile) -> &'static str {
    match profile {
        RecordProfile::Json => "json",
        RecordProfile::Yaml => "yaml",
        RecordProfile::Tree => "tree",
    }
}

/// A case's `file` fences, grouped into the sets they declare, in first-seen order.
fn file_sets<'t, 'k>(targets: &'t [Target<'k>]) -> Vec<(String, Vec<&'t Target<'k>>)> {
    let mut sets: Vec<(String, Vec<&Target>)> = Vec::new();
    for target in targets.iter().filter(|t| t.role == Role::File) {
        let name = target.fence.info.set();
        match sets.iter_mut().find(|(n, _)| n == name) {
            Some((_, members)) => members.push(target),
            None => sets.push((name.to_owned(), vec![target])),
        }
    }
    sets
}

struct SetRun<'r, 'k> {
    name: &'r str,
    members: &'r [&'r Target<'k>],
    case: &'r KitCase,
    version: i64,
    path: PathMode,
    caps: Option<&'r Capabilities>,
    dead: Option<&'r str>,
    canonicals: &'r [(RecordProfile, String)],
    canonical_bodies: &'r [(RecordProfile, String)],
}

/// The tree comparison for one set on one path: read the set as a tree and
/// hold its canonical to the case's canonical fence of the set's profile;
/// unless the set says `mode=read`, write that canonical back and compare
/// every file with the fence that carries its path.
fn run_file_set(run: &SetRun, testee: &mut dyn Testee) -> Result<Vec<(usize, Verdict)>, String> {
    let label = set_label(run.name);
    let all = |verdict: Verdict| {
        run.members
            .iter()
            .map(|t| (t.fence.index, verdict.clone()))
            .collect::<Vec<_>>()
    };

    // Pending is skipped only while the adapter lives (departure 14).
    if run.case.status == Status::Pending && run.dead.is_none() {
        return Ok(all(Verdict::skipped("pending".to_owned())));
    }
    if let Some(unresolved) = run.members.iter().find_map(|t| t.body.as_ref().err()) {
        return Ok(run
            .members
            .iter()
            .map(|t| {
                let verdict = match &t.body {
                    Err(message) => Verdict::kit_error(format!("set {label}: {message}")),
                    Ok(_) => Verdict::kit_error(unresolved.clone()),
                };
                (t.fence.index, verdict)
            })
            .collect());
    }
    let (Some(caps), None) = (run.caps, run.dead) else {
        let message = match (run.caps, run.dead) {
            (None, dead) => dead.unwrap_or("no capabilities").to_owned(),
            (Some(_), Some(dead)) => format!("adapter unavailable: {dead}"),
            (Some(_), None) => unreachable!(),
        };
        return Ok(all(Verdict::kit_error(message)));
    };
    if let Some(skip) = unsupported(
        caps,
        run.version,
        RecordProfile::Tree,
        run.path,
        run.case.node.as_deref(),
    ) {
        return Ok(all(Verdict::skipped(skip)));
    }
    let language = run.members[0].language;
    if run.members.iter().any(|t| t.language != language) {
        return Ok(all(Verdict::kit_error(format!(
            "mixed profiles in set {label}"
        ))));
    }
    if !caps.profiles.contains(&language.into()) {
        return Ok(all(Verdict::skipped(format!(
            "profile {language} not in capabilities"
        ))));
    }
    let Some(manifest) = run
        .members
        .iter()
        .find(|t| t.fence.info.key("path") == Some(MANIFEST))
    else {
        return Ok(all(Verdict::kit_error(format!(
            "set {label} has no manifest"
        ))));
    };
    let body_of = |t: &Target| t.body.clone().unwrap_or_default();
    let Some(path_budget) = path_budget_of(&body_of(manifest)) else {
        return Ok(all(Verdict::kit_error(format!(
            "set {label}: manifest has no readable pathBudget"
        ))));
    };
    let wanted = record_profile(language);
    let lookup = |list: &[(RecordProfile, String)]| {
        list.iter()
            .find(|(p, _)| *p == wanted)
            .map(|(_, s)| s.clone())
    };
    let (Some(expected), Some(canonical_body)) =
        (lookup(run.canonicals), lookup(run.canonical_bodies))
    else {
        return Ok(all(Verdict::kit_error(format!(
            "no canonical {language} fence in {}",
            run.case.id
        ))));
    };

    let strip = run.case.compare != Compare::Attributes;
    let node = run.case.node.clone().unwrap_or_default();
    let files = run
        .members
        .iter()
        .map(|t| TreeFile {
            path: t.fence.info.key("path").unwrap_or("").to_owned(),
            content: body_of(t),
        })
        .collect();
    let version = u32::try_from(run.version).unwrap_or(u32::MAX);
    let read_request = Request::ReadTree {
        version,
        profile: language,
        path: run.path,
        strip,
        node,
        files,
    };
    let read_response = decode(testee, &read_request)?;

    let writes: Vec<WriteIssue> = if manifest.fence.info.key("mode") == Some("read") {
        Vec::new()
    } else {
        let request = Request::WriteTree {
            version,
            path: run.path,
            policy: WritePolicy {
                profile: language,
                path_budget,
            },
            input: canonical_body,
        };
        judge_tree_write(
            label,
            run.case.id.as_str(),
            run.members,
            manifest,
            &write_tree(testee, &request)?,
        )
    };

    Ok(run
        .members
        .iter()
        .map(|t| {
            let read = judge_tree_read(
                label,
                run.case.id.as_str(),
                t.fence.index,
                language,
                &read_response,
                &expected,
            );
            let write = writes
                .iter()
                .find(|issue| issue.fence_index == t.fence.index);
            let verdict = match (read.result, write) {
                (Outcome::Pass, None) => Verdict::pass(),
                (Outcome::Pass, Some(issue)) => Verdict {
                    diff: issue.diff.clone(),
                    ..Verdict::fail(issue.message.clone())
                },
                (_, Some(issue)) => Verdict {
                    message: Some(format!(
                        "{}; {}",
                        read.message.clone().unwrap_or_default(),
                        issue.message
                    )),
                    diff: {
                        let parts = [read.diff.clone(), issue.diff.clone()]
                            .into_iter()
                            .flatten()
                            .collect::<Vec<_>>();
                        (!parts.is_empty()).then(|| parts.join("\n"))
                    },
                    ..read.clone()
                },
                (_, None) => read.clone(),
            };
            (t.fence.index, verdict)
        })
        .collect())
}

fn judge_tree_read(
    label: &str,
    case_id: &str,
    fence_index: usize,
    language: Profile,
    response: &DecodeResponse,
    expected: &str,
) -> Verdict {
    match response {
        DecodeResponse::Rejected(d) => Verdict {
            observed_diagnostic: Some(d.into()),
            ..Verdict::fail(format!("set {label} failed to readTree: {}", describe(d)))
        },
        DecodeResponse::Ok { warnings, .. } => {
            // `file` fences declare no `warning=`, so a set is held to none.
            if let Some(problem) = check_warnings(None, warnings) {
                return Verdict::fail(format!("set {label}: {problem}"));
            }
            match response.canonical(language) {
                None => Verdict::fail(format!(
                    "set {label}: adapter returned no {language} canonical"
                )),
                Some(got) => match check_canonical(expected, got) {
                    None => Verdict::pass(),
                    Some(reason) => Verdict {
                        diff: Some(canonical_diff(
                            expected,
                            got,
                            &format!("{case_id} fence {fence_index} profile {language} tree read"),
                        )),
                        ..Verdict::fail(format!("set {label} read back differently: {reason}"))
                    },
                },
            }
        }
    }
}

/// The write half, as a message and optional diff per failing fence index.
fn judge_tree_write(
    label: &str,
    case_id: &str,
    members: &[&Target],
    manifest: &Target,
    response: &WriteTreeResponse,
) -> Vec<WriteIssue> {
    let files = match response {
        WriteTreeResponse::Rejected(d) => {
            let message = format!("set {label} failed to writeTree: {}", describe(d));
            return members
                .iter()
                .map(|t| WriteIssue {
                    fence_index: t.fence.index,
                    message: message.clone(),
                    diff: None,
                })
                .collect();
        }
        WriteTreeResponse::Ok { files } => files,
    };
    let mut produced: Vec<(&str, &str)> = files
        .iter()
        .map(|f| (f.path.as_str(), f.content.as_str()))
        .collect();
    let mut out: Vec<WriteIssue> = Vec::new();
    for t in members {
        let logical = t.fence.info.key("path").unwrap_or("");
        // The last file with the path wins, as a Map built from the list would.
        let content = produced
            .iter()
            .rev()
            .find(|(p, _)| *p == logical)
            .map(|(_, c)| *c);
        produced.retain(|(p, _)| *p != logical);
        match content {
            None => out.push(WriteIssue {
                fence_index: t.fence.index,
                message: format!("writeTree did not produce {logical}"),
                diff: None,
            }),
            Some(content) => {
                let expected = t.body.as_deref().unwrap_or("");
                if let Some(reason) = check_canonical(expected, content) {
                    out.push(WriteIssue {
                        fence_index: t.fence.index,
                        message: format!("writeTree wrote {logical} differently: {reason}"),
                        diff: Some(canonical_diff(
                            expected,
                            content,
                            &format!(
                                "{} fence {} profile tree path {logical}",
                                case_id, t.fence.index
                            ),
                        )),
                    });
                }
            }
        }
    }
    // A file the set does not have is the set's problem as a whole, so it is
    // reported on its manifest's record.
    let mut extra: Vec<&str> = produced.iter().map(|(p, _)| *p).collect();
    extra.sort_by(|a, b| crate::kit::syntax::text::utf16_cmp(a, b));
    extra.dedup();
    if !extra.is_empty() {
        let extra = extra
            .iter()
            .map(|p| format!("writeTree produced {p}, which the set does not have"))
            .collect::<Vec<_>>()
            .join("; ");
        match out
            .iter_mut()
            .find(|issue| issue.fence_index == manifest.fence.index)
        {
            Some(issue) => issue.message = format!("{}; {extra}", issue.message),
            None => out.push(WriteIssue {
                fence_index: manifest.fence.index,
                message: extra,
                diff: None,
            }),
        }
    }
    out
}

/// The two paths must agree fence by fence: the same verdict for the same
/// stated reason. Disagreeing records all fail, naming both signatures.
fn reconcile_paths(by_path: &mut [(PathMode, Vec<Record>)], case: &KitCase) {
    if by_path.len() < 2 {
        return;
    }
    let signature = |r: &Record| {
        format!(
            "{}|{}|{}",
            r.result.as_str(),
            r.message.as_deref().unwrap_or(""),
            r.observed_diagnostic
                .as_ref()
                .map_or("", |d| d.code.as_str())
        )
    };
    for fence in &case.fences {
        let mut signatures: Vec<String> = Vec::new();
        for (_, records) in by_path.iter() {
            if let Some(r) = records.iter().find(|r| r.fence_index == fence.index) {
                let sig = signature(r);
                if !signatures.contains(&sig) {
                    signatures.push(sig);
                }
            }
        }
        if signatures.len() <= 1 {
            continue;
        }
        let message = format!("paths disagree: {}", signatures.join(" vs "));
        for (_, records) in by_path.iter_mut() {
            if let Some(r) = records.iter_mut().find(|r| r.fence_index == fence.index) {
                r.result = Outcome::Fail;
                r.message = Some(message.clone());
            }
        }
    }
}

/// The state one run carries from case to case: the adapter's answer to
/// `capabilities`, and whether the conversation has ended.
pub struct RunState {
    /// The adapter's declared capabilities, or `None` if it never answered.
    pub caps: Option<Capabilities>,
    /// Why the adapter can no longer be used, once it has failed.
    pub dead: Option<String>,
}

impl RunState {
    /// Asks the testee for its capabilities, as the first request of a run.
    pub fn open(testee: &mut dyn Testee) -> Self {
        let mut dead: Option<String> = None;
        let negotiated = testee
            .exchange(&Request::capabilities_v2())
            .and_then(|body| {
                if is_v1_capabilities_rejection(&body)? {
                    testee.exchange(&Request::Capabilities)
                } else {
                    Ok(body)
                }
            });
        let caps = match negotiated
            .and_then(|body| parse_capabilities(&Value::Object(body)).map_err(|error| error.0))
        {
            Ok(caps) => Some(caps),
            Err(error) => {
                dead = Some(error);
                None
            }
        };
        RunState { caps, dead }
    }

    /// `<binding> supports IR format versions <table> (<prose>)`, or `None`.
    pub fn header(&self) -> Option<String> {
        self.caps.as_ref().map(|c| {
            format!(
                "{} supports IR format versions {} ({})",
                c.binding,
                c.format_versions,
                c.table.prose()
            )
        })
    }

    /// How the conversation failed, if it did.
    pub fn failure(&self) -> Option<RunFailure> {
        self.dead.clone().map(|message| {
            if self.caps.is_some() {
                RunFailure::Exchange(message)
            } else {
                RunFailure::Capabilities(message)
            }
        })
    }
}

fn is_v1_capabilities_rejection(body: &Map<String, Value>) -> Result<bool, String> {
    if body.get("ok") != Some(&Value::Bool(false)) {
        return Ok(false);
    }
    match parse_decode_response(&Value::Object(body.clone())).map_err(|error| error.0)? {
        DecodeResponse::Rejected(diagnostic) => Ok(diagnostic.code == "protocol_error"),
        DecodeResponse::Ok { .. } => Ok(false),
    }
}

/// The kit-error records for `kit.errors`, in legacy order.
pub fn kit_error_records(kit: &Kit) -> Vec<Record> {
    let mut records: Vec<Record> = Vec::new();
    for error in &kit.errors {
        let owner = owner_of(&kit.cases, error);
        records.push(Record {
            case_id: owner.map_or_else(|| KIT_ERROR_CASE.to_owned(), |c| c.id.as_str().to_owned()),
            ir_version: CURRENT_VERSION,
            profile: RecordProfile::Json,
            role: Role::Canonical,
            fence_index: 0,
            path: None,
            result: Outcome::KitError,
            expected_diagnostic: None,
            observed_diagnostic: None,
            message: Some(format!("{}:{}: {}", error.file, error.line, error.message)),
            check: None,
            diff: None,
            duration_ms: Millis(0.0),
        });
    }
    records
}

/// Every record of one case, exactly as `run_kit` writes them.
pub fn run_case(
    kit: &Kit,
    case: &KitCase,
    state: &mut RunState,
    testee: &mut dyn Testee,
    clock: &dyn Fn() -> f64,
) -> Vec<Record> {
    let version = case.version.unwrap_or(CURRENT_VERSION);
    let targets: Vec<Target> = case.fences.iter().map(|f| target_of(kit, f)).collect();
    // The expectation every accepted fence and file set is held to,
    // normalized, with the unnormalized body a tree write is fed.
    let mut canonicals: Vec<(RecordProfile, String)> = Vec::new();
    let mut canonical_bodies: Vec<(RecordProfile, String)> = Vec::new();
    for t in targets.iter().filter(|t| t.role == Role::Canonical) {
        if let Ok(body) = &t.body {
            canonicals.retain(|(p, _)| *p != t.profile);
            canonicals.push((t.profile, normalize_canonical(body).to_owned()));
            canonical_bodies.retain(|(p, _)| *p != t.profile);
            canonical_bodies.push((t.profile, body.clone()));
        }
    }
    let paths: Vec<PathMode> = state
        .caps
        .as_ref()
        .map_or_else(|| vec![PathMode::Current], |c| c.paths.clone());
    let sets = file_sets(&targets);
    let mut by_path: Vec<(PathMode, Vec<Record>)> = Vec::new();

    for &path in &paths {
        let mut per_path: Vec<Record> = Vec::new();
        for target in targets.iter().filter(|t| t.role != Role::File) {
            let started = clock();
            let verdict = 'verdict: {
                // After an adapter failure a pending fence is a kit error
                // like any other, so a dead adapter never passes a run
                // (departure 14).
                if case.status == Status::Pending && state.dead.is_none() {
                    break 'verdict Verdict::skipped("pending".to_owned());
                }
                let body = match &target.body {
                    Ok(body) => body,
                    Err(message) => break 'verdict Verdict::kit_error(message.clone()),
                };
                let caps = match (&state.caps, &state.dead) {
                    (Some(caps), None) => caps,
                    (None, Some(dead)) => break 'verdict Verdict::kit_error(dead.clone()),
                    (_, Some(dead)) => {
                        break 'verdict Verdict::kit_error(format!("adapter unavailable: {dead}"));
                    }
                    (None, None) => {
                        unreachable!("capabilities either succeeded or recorded why not")
                    }
                };
                if let Some(skip) =
                    unsupported(caps, version, target.profile, path, case.node.as_deref())
                {
                    break 'verdict Verdict::skipped(skip);
                }
                let request = Request::Decode {
                    version: u32::try_from(version).unwrap_or(u32::MAX),
                    profile: target.language,
                    path,
                    strip: case.compare != Compare::Attributes,
                    node: case.node.clone().unwrap_or_default(),
                    input: body.clone(),
                };
                match decode(testee, &request) {
                    Err(error) => {
                        state.dead = Some(error.clone());
                        Verdict::kit_error(error)
                    }
                    Ok(response) if target.role == Role::Rejected => {
                        let check = check_rejected(
                            target.fence.info.key("diagnostic"),
                            target.fence.info.key("expect"),
                            &response,
                        );
                        Verdict {
                            result: check.result,
                            expected_diagnostic: check.expected_diagnostic,
                            observed_diagnostic: check.observed_diagnostic,
                            message: check.message,
                            diff: None,
                        }
                    }
                    Ok(response) => {
                        let expected = canonicals
                            .iter()
                            .find(|(p, _)| *p == target.profile)
                            .map(|(_, s)| s.as_str());
                        judge_accepted(target, &response, expected, case.id.as_str())
                    }
                }
            };
            per_path.push(record(
                case,
                version,
                target,
                path,
                verdict,
                clock() - started,
            ));
        }

        for (name, members) in &sets {
            let started = clock();
            let set_run = SetRun {
                name,
                members,
                case,
                version,
                path,
                caps: state.caps.as_ref(),
                dead: state.dead.as_deref(),
                canonicals: &canonicals,
                canonical_bodies: &canonical_bodies,
            };
            let verdicts = match run_file_set(&set_run, testee) {
                Ok(verdicts) => verdicts,
                Err(error) => {
                    state.dead = Some(error.clone());
                    members
                        .iter()
                        .map(|t| (t.fence.index, Verdict::kit_error(error.clone())))
                        .collect()
                }
            };
            let duration = clock() - started;
            for target in members {
                let verdict = verdicts
                    .iter()
                    .find(|(index, _)| *index == target.fence.index)
                    .map(|(_, v)| v.clone())
                    .unwrap_or_else(|| {
                        Verdict::kit_error(format!("set {} produced no verdict", set_label(name)))
                    });
                per_path.push(record(case, version, target, path, verdict, duration));
            }
        }
        // Sets are judged after the single-document fences; report in fence order.
        per_path.sort_by_key(|r| r.fence_index);
        by_path.push((path, per_path));
    }
    reconcile_paths(&mut by_path, case);
    by_path.into_iter().flat_map(|(_, r)| r).collect()
}

/// The v1 report around `records`.
pub fn report_of(state: &RunState, options: &RunOptions, records: Vec<Record>) -> Report {
    Report {
        contract_version: crate::report::CONTRACT_VERSION,
        binding: state
            .caps
            .as_ref()
            .map_or_else(|| "unknown".to_owned(), |c| c.binding.clone()),
        language: state
            .caps
            .as_ref()
            .map_or_else(|| "unknown".to_owned(), |c| c.language.clone()),
        format_versions: state
            .caps
            .as_ref()
            .map_or_else(|| "unknown".to_owned(), |c| c.format_versions.clone()),
        driver_version: options.driver_version.clone(),
        kit_version: options.kit_version.clone(),
        started_at: options.started_at.clone(),
        records,
    }
}

/// Runs every selected case of `kit` against `testee`.
pub fn run_kit(kit: &Kit, testee: &mut dyn Testee, options: &RunOptions) -> Run {
    let mut state = RunState::open(testee);
    let header = state.header();
    let mut records = kit_error_records(kit);

    for case in &kit.cases {
        if options
            .filter
            .is_some_and(|filter| !filter.is_match(case.id.as_str()))
        {
            continue;
        }
        records.extend(run_case(kit, case, &mut state, testee, options.clock));
    }

    let report = report_of(&state, options, records);
    let failure = state.failure();
    Run {
        report,
        header,
        failure,
        capabilities: state.caps,
    }
}

/// How a run ends. Zero records is never a success: an empty selection is not
/// a compatibility claim (`spec/mck/cli-contract.md`, departure 2).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunVerdict {
    Passed,
    Failed,
    NothingSelected,
}

pub fn verdict(report: &Report, strict: bool) -> RunVerdict {
    if report.records.is_empty() {
        return RunVerdict::NothingSelected;
    }
    let failed = report.records.iter().any(|r| {
        matches!(r.result, Outcome::Fail | Outcome::KitError)
            || (strict && r.result == Outcome::Skipped)
    });
    if failed {
        RunVerdict::Failed
    } else {
        RunVerdict::Passed
    }
}

#[cfg(test)]
mod tests {
    use std::borrow::Cow;
    use std::collections::BTreeMap;

    use serde_json::json;

    use super::*;
    use crate::kit::source::KitSource;
    use crate::transport::protocol::{CONTRACT_VERSION, CapabilitiesProfile};

    /// An adapter answering from a closure.
    struct Scripted<F: FnMut(&Request) -> Result<Value, String>>(F);

    impl<F: FnMut(&Request) -> Result<Value, String>> Testee for Scripted<F> {
        fn exchange(&mut self, request: &Request) -> Result<Map<String, Value>, String> {
            (self.0)(request).map(|v| v.as_object().unwrap().clone())
        }
    }

    fn caps(paths: &[&str]) -> Value {
        json!({
            "contractVersion": 1, "binding": "fake", "language": "rust", "formatVersions": "[4.0.0,4.1.0)",
            "versions": [4], "profiles": ["json", "yaml"], "layouts": ["single", "tree"], "paths": paths, "nodes": ["Type"]
        })
    }

    fn is_capabilities(request: &Request) -> bool {
        matches!(
            request,
            Request::Capabilities | Request::CapabilitiesV2 { .. }
        )
    }

    fn decoded(canonical: &str) -> Value {
        json!({ "ok": true, "kind": "Unit", "canonical": { "yaml": canonical }, "warnings": [] })
    }

    fn kit_of(files: &[(&str, &str)]) -> Kit {
        let files: BTreeMap<String, Cow<'static, [u8]>> = files
            .iter()
            .map(|(p, t)| ((*p).to_owned(), Cow::Owned(t.as_bytes().to_vec())))
            .collect();
        crate::kit::load::load_markdown_kit(KitSource::map("test kit", files)).unwrap()
    }

    fn run_with(kit: &Kit, filter: Option<&Regex>, testee: &mut dyn Testee) -> Run {
        let clock = || 0.0;
        let options = RunOptions {
            filter,
            driver_version: "test".into(),
            kit_version: "test".into(),
            started_at: "1970-01-01T00:00:00.000Z".into(),
            clock: &clock,
        };
        run_kit(kit, testee, &options)
    }

    fn outcomes(run: &Run) -> Vec<(String, Option<PathMode>, &'static str, Option<String>)> {
        run.report
            .records
            .iter()
            .map(|r| {
                (
                    r.case_id.clone(),
                    r.path,
                    r.result.as_str(),
                    r.message.clone(),
                )
            })
            .collect()
    }

    const UNIT: &str = "## types-0001: unit {node=Type}\n```yaml canonical\nUnit: {}\n```\n";

    #[test]
    fn inventory_preserves_repeated_synthetic_error_identities_and_order() {
        let kit = kit_of(&[(
            "spec/ir/mck/types.md",
            "```yaml canonical\na: 1\n```\n```json canonical\n{}\n```\n",
        )]);
        assert_eq!(kit.errors.len(), 2);
        let caps = parse_capabilities(&caps(&["current"])).unwrap();
        let entries = inventory(&kit, &caps, Some(&Regex::new("^types-9999$").unwrap()));
        assert_eq!(entries.len(), 2, "kit errors survive filtering");
        for entry in &entries {
            assert_eq!(entry.case_id, "kit-0000");
            assert_eq!(entry.fence_index, 0);
            assert_eq!(entry.path, None);
        }
        assert_eq!(
            entries[0].kit_error.as_deref(),
            Some("spec/ir/mck/types.md:1: data fence before the first case")
        );
        assert_eq!(
            entries[1].kit_error.as_deref(),
            Some("spec/ir/mck/types.md:4: data fence before the first case")
        );
    }

    #[test]
    fn kit_errors_are_reported_under_their_case_or_the_reserved_id() {
        let kit = kit_of(&[(
            "spec/ir/mck/types.md",
            "```yaml canonical\na: 1\n```\n## types-0001: unit {node=Type bogus=1}\n```yaml canonical\nUnit: {}\n```\n",
        )]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| {
                Ok(if is_capabilities(r) {
                    caps(&["current"])
                } else {
                    decoded("Unit: {}\n")
                })
            }),
        );
        let errors: Vec<_> = run
            .report
            .records
            .iter()
            .filter(|r| r.result == Outcome::KitError)
            .collect();
        assert_eq!(errors.len(), 2);
        assert_eq!(
            (errors[0].case_id.as_str(), errors[0].path),
            ("kit-0000", None)
        );
        assert_eq!(
            errors[0].message.as_deref(),
            Some("spec/ir/mck/types.md:1: data fence before the first case")
        );
        assert_eq!(errors[1].case_id, "types-0001");
        assert!(
            errors[1]
                .message
                .as_deref()
                .unwrap()
                .ends_with("unknown heading key \"bogus\"")
        );
    }

    #[test]
    fn an_adapter_that_fails_capabilities_turns_every_fence_into_a_kit_error() {
        let kit = kit_of(&[("spec/ir/mck/types.md", UNIT)]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|_: &Request| {
                Err::<Value, _>("failed to start adapter: nope".to_owned())
            }),
        );
        assert_eq!(run.header, None);
        assert!(matches!(run.failure, Some(RunFailure::Capabilities(_))));
        assert_eq!(run.report.binding, "unknown");
        assert_eq!(run.report.format_versions, "unknown");
        assert_eq!(
            outcomes(&run),
            vec![(
                "types-0001".into(),
                Some(PathMode::Current),
                "kit-error",
                Some("failed to start adapter: nope".into())
            )]
        );
    }

    #[test]
    fn v2_driver_uses_v1_adapter_after_version_rejection() {
        let mut requests = Vec::new();
        let state = RunState::open(&mut Scripted(|request: &Request| {
            requests.push(request.clone());
            match request {
                Request::CapabilitiesV2 { .. } => Ok(json!({
                    "ok": false,
                    "diagnostic": {"code": "protocol_error", "message": "unknown field contractVersion"}
                })),
                Request::Capabilities => Ok(caps(&["current"])),
                _ => panic!("unexpected request"),
            }
        }));
        assert!(state.dead.is_none());
        assert_eq!(
            state.caps.unwrap().contract_version,
            semver::Version::new(1, 0, 0)
        );
        assert_eq!(
            requests,
            vec![Request::capabilities_v2(), Request::Capabilities]
        );
    }

    #[test]
    fn malformed_version_rejection_is_a_protocol_error_without_retry() {
        let mut requests = Vec::new();
        let state = RunState::open(&mut Scripted(|request: &Request| {
            requests.push(request.clone());
            Ok(json!({
                "ok": false,
                "diagnostic": {"code": "protocol_error"},
                "extra": true
            }))
        }));
        assert_eq!(requests, vec![Request::capabilities_v2()]);
        assert!(state.caps.is_none());
        assert!(state.dead.unwrap().contains("unknown field \"extra\""));
    }

    #[test]
    fn v2_driver_accepts_an_ion_capable_adapter() {
        let state = RunState::open(&mut Scripted(|request: &Request| {
            assert_eq!(*request, Request::capabilities_v2());
            let mut response = caps(&["current"]);
            response["contractVersion"] = json!(CONTRACT_VERSION);
            response["profiles"] = json!(["json", "yaml", "ion"]);
            Ok(response)
        }));
        assert!(state.dead.is_none());
        let caps = state.caps.unwrap();
        assert_eq!(
            caps.contract_version,
            semver::Version::parse(CONTRACT_VERSION).unwrap()
        );
        assert!(caps.profiles.contains(&CapabilitiesProfile::Ion));
    }

    #[test]
    fn a_transport_failure_mid_run_marks_later_fences_unavailable() {
        let kit = kit_of(&[(
            "spec/ir/mck/types.md",
            &format!(
                "{UNIT}## types-0002: two {{node=Type}}\n```yaml canonical\nUnit: {{}}\n```\n"
            ),
        )]);
        let mut calls = 0;
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| {
                calls += 1;
                match (r, calls) {
                    (Request::Capabilities | Request::CapabilitiesV2 { .. }, _) => {
                        Ok(caps(&["current"]))
                    }
                    (_, 2) => Err("adapter exited with code 3".to_owned()),
                    _ => Ok(decoded("Unit: {}\n")),
                }
            }),
        );
        assert_eq!(
            outcomes(&run),
            vec![
                (
                    "types-0001".into(),
                    Some(PathMode::Current),
                    "kit-error",
                    Some("adapter exited with code 3".into())
                ),
                (
                    "types-0002".into(),
                    Some(PathMode::Current),
                    "kit-error",
                    Some("adapter unavailable: adapter exited with code 3".into())
                ),
            ]
        );
    }

    /// A pending case is skipped only while the adapter is alive: after a
    /// failure a dead adapter could otherwise pass an all-pending selection
    /// (departure 14). A pending case may not carry file fences, so the set
    /// path is reached only by a kit that already reports that error.
    #[test]
    fn pending_fences_after_an_adapter_failure_are_kit_errors() {
        let kit = kit_of(&[
            (
                "spec/ir/mck/types.md",
                "## types-0001: undecided {node=Type status=pending}\n```json rejected diagnostic=x\n1\n```\n",
            ),
            (
                "spec/ir/mck/document-tree.md",
                "## document-tree-0001: tree {node=Type status=pending}\n```yaml canonical\nUnit: {}\n```\n```yaml file path=manifest\npathBudget: 4000\n```\n",
            ),
        ]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|_: &Request| {
                Err::<Value, _>("failed to start adapter: nope".to_owned())
            }),
        );
        let results: Vec<_> = outcomes(&run)
            .into_iter()
            .map(|(id, _, result, message)| (id, result, message))
            .collect();
        assert_eq!(
            results,
            vec![
                (
                    "document-tree-0001".into(),
                    "kit-error",
                    Some("spec/ir/mck/document-tree.md:2: pending case may not carry canonical, accepted, or file fences (document-tree-0001)".into())
                ),
                (
                    "document-tree-0001".into(),
                    "kit-error",
                    Some("failed to start adapter: nope".into())
                ),
                (
                    "document-tree-0001".into(),
                    "kit-error",
                    Some("failed to start adapter: nope".into())
                ),
                (
                    "types-0001".into(),
                    "kit-error",
                    Some("failed to start adapter: nope".into())
                ),
            ]
        );
        assert_eq!(verdict(&run.report, false), RunVerdict::Failed);

        let kit = kit_of(&[(
            "spec/ir/mck/types.md",
            &format!(
                "{UNIT}## types-0002: undecided {{node=Type status=pending}}\n```json rejected diagnostic=x\n1\n```\n"
            ),
        )]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| match r {
                Request::Capabilities | Request::CapabilitiesV2 { .. } => Ok(caps(&["current"])),
                _ => Err("adapter exited with code 3".to_owned()),
            }),
        );
        assert_eq!(
            outcomes(&run).last().unwrap().3.as_deref(),
            Some("adapter unavailable: adapter exited with code 3")
        );
        assert!(
            run.report
                .records
                .iter()
                .all(|r| r.result == Outcome::KitError)
        );
    }

    #[test]
    fn pending_and_unsupported_fences_are_skipped_with_their_reason() {
        let kit = kit_of(&[(
            "spec/ir/mck/types.md",
            "## types-0001: undecided {node=Type status=pending}\n```json rejected diagnostic=x\n1\n```\n## types-0002: other node {node=Value}\n```yaml canonical\na: 1\n```\n## types-0003: no node\n```yaml canonical\na: 1\n```\n## types-0004: v3 {node=Type version=3}\n```yaml canonical\na: 1\n```\n",
        )]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|_: &Request| Ok(caps(&["current"]))),
        );
        let skips: Vec<_> = run
            .report
            .records
            .iter()
            .map(|r| r.message.clone().unwrap())
            .collect();
        assert_eq!(
            skips,
            vec![
                "pending",
                "node Value not in capabilities",
                "node unset not in capabilities",
                "version 3 not in capabilities"
            ]
        );
        assert!(
            run.report
                .records
                .iter()
                .all(|r| r.result == Outcome::Skipped)
        );
    }

    #[test]
    fn paths_that_disagree_fail_on_both_with_both_signatures() {
        let kit = kit_of(&[("spec/ir/mck/types.md", UNIT)]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| match r {
                Request::Capabilities | Request::CapabilitiesV2 { .. } => {
                    Ok(caps(&["current", "pinned"]))
                }
                Request::Decode {
                    path: PathMode::Current,
                    ..
                } => Ok(decoded("Unit: {}\n")),
                _ => Ok(decoded("Other: {}\n")),
            }),
        );
        let message =
            "paths disagree: pass|| vs fail|line 1 differs: expected Unit: {} got Other: {}|";
        assert_eq!(
            outcomes(&run),
            vec![
                (
                    "types-0001".into(),
                    Some(PathMode::Current),
                    "fail",
                    Some(message.into())
                ),
                (
                    "types-0001".into(),
                    Some(PathMode::Pinned),
                    "fail",
                    Some(message.into())
                ),
            ]
        );
    }

    #[test]
    fn a_file_the_set_does_not_have_is_reported_on_its_manifest() {
        let kit = kit_of(&[(
            "spec/ir/mck/document-tree.md",
            "## document-tree-0001: tree {node=Type}\n```yaml canonical\nUnit: {}\n```\n```yaml file path=manifest\npathBudget: 4000\n```\n```yaml file path=pkg/a\nb: 1\n```\n",
        )]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| match r {
                Request::Capabilities | Request::CapabilitiesV2 { .. } => Ok(caps(&["current"])),
                Request::WriteTree { policy, .. } => {
                    assert_eq!(policy.path_budget, 4000);
                    Ok(json!({ "ok": true, "files": [
                    { "path": "manifest", "content": "pathBudget: 4000\n" },
                    { "path": "pkg/a", "content": "b: 1\n" },
                    { "path": "pkg/z", "content": "" }
                ] }))
                }
                _ => Ok(decoded("Unit: {}\n")),
            }),
        );
        let files: Vec<_> = run
            .report
            .records
            .iter()
            .filter(|r| r.role == Role::File)
            .map(|r| (r.result.as_str(), r.message.clone()))
            .collect();
        assert_eq!(
            files,
            vec![
                (
                    "fail",
                    Some("writeTree produced pkg/z, which the set does not have".into())
                ),
                ("pass", None)
            ]
        );
    }

    #[test]
    fn canonical_and_accepted_failures_keep_reason_and_attach_diff() {
        let kit = kit_of(&[(
            "spec/ir/mck/types.md",
            "## types-0001: unit {node=Type}\n```yaml canonical\nUnit: {}\n```\n```yaml accepted\nUnit : {}\n```\n",
        )]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| {
                Ok(if is_capabilities(r) {
                    caps(&["current"])
                } else {
                    decoded("Other: {}\n")
                })
            }),
        );
        let records = &run.report.records;
        assert_eq!(records.len(), 2);
        for (index, record) in records.iter().enumerate() {
            assert_eq!(record.result, Outcome::Fail);
            assert_eq!(
                record.message.as_deref(),
                Some("line 1 differs: expected Unit: {} got Other: {}")
            );
            let diff = record.diff.as_deref().unwrap();
            assert!(diff.contains(&format!(
                "--- expected types-0001 fence {index} profile yaml"
            )));
            assert!(diff.contains("-Unit: {}\n+Other: {}\n"));
        }
    }

    #[test]
    fn tree_read_and_each_written_file_get_named_diffs() {
        let kit = kit_of(&[(
            "spec/ir/mck/document-tree.md",
            "## document-tree-0001: tree {node=Type}\n```yaml canonical\nUnit: {}\n```\n```yaml file path=manifest\npathBudget: 4000\n```\n```yaml file path=pkg/a\nb: 1\n```\n",
        )]);
        let run = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| match r {
                Request::Capabilities | Request::CapabilitiesV2 { .. } => Ok(caps(&["current"])),
                Request::WriteTree { .. } => Ok(json!({ "ok": true, "files": [
                    { "path": "manifest", "content": "pathBudget: 3000\n" },
                    { "path": "pkg/a", "content": "b: 2\n" }
                ] })),
                _ => Ok(decoded("Other: {}\n")),
            }),
        );
        let files: Vec<_> = run
            .report
            .records
            .iter()
            .filter(|r| r.role == Role::File)
            .collect();
        assert_eq!(files.len(), 2);
        for (file, path) in files.iter().zip(["manifest", "pkg/a"]) {
            assert_eq!(file.result, Outcome::Fail);
            assert!(
                file.message
                    .as_deref()
                    .unwrap()
                    .contains("read back differently")
            );
            let diff = file.diff.as_deref().unwrap();
            assert!(diff.starts_with(&format!(
                "--- expected document-tree-0001 fence {} profile yaml tree read",
                file.fence_index
            )));
            assert!(diff.contains(&format!("profile tree path {path}")));
        }

        let no_text = run_with(
            &kit,
            None,
            &mut Scripted(|r: &Request| match r {
                Request::Capabilities | Request::CapabilitiesV2 { .. } => Ok(caps(&["current"])),
                Request::WriteTree { .. } => Ok(json!({ "ok": true, "files": [] })),
                _ => Ok(json!({ "ok": false, "diagnostic": { "code": "invalid_tree" } })),
            }),
        );
        assert!(
            no_text
                .report
                .records
                .iter()
                .filter(|r| r.role == Role::File)
                .all(|r| r.diff.is_none())
        );
    }

    #[test]
    fn the_filter_selects_by_case_id_and_an_empty_run_is_never_a_success() {
        let kit = kit_of(&[("spec/ir/mck/types.md", UNIT)]);
        let answer = |r: &Request| {
            Ok(if is_capabilities(r) {
                caps(&["current"])
            } else {
                decoded("Unit: {}\n")
            })
        };
        let none = Regex::new("^values-").unwrap();
        let run = run_with(&kit, Some(&none), &mut Scripted(answer));
        assert!(run.report.records.is_empty());
        assert_eq!(verdict(&run.report, false), RunVerdict::NothingSelected);

        let some = Regex::new("types-0").unwrap();
        let run = run_with(&kit, Some(&some), &mut Scripted(answer));
        assert_eq!(verdict(&run.report, false), RunVerdict::Passed);
        let mut skipped = run.report.clone();
        skipped.records[0].result = Outcome::Skipped;
        assert_eq!(verdict(&skipped, false), RunVerdict::Passed);
        assert_eq!(verdict(&skipped, true), RunVerdict::Failed);
    }

    #[test]
    fn kit_error_records_then_run_case_then_report_of_reproduce_run_kit() {
        let kit = kit_of(&[
            ("spec/ir/mck/types.md", UNIT),
            (
                "spec/ir/mck/values.md",
                "## values-0001: literal {node=Type}\n```yaml canonical\nLiteral: {}\n```\n",
            ),
        ]);
        let answer = |r: &Request| {
            Ok(if is_capabilities(r) {
                caps(&["current"])
            } else {
                decoded("Unit: {}\n")
            })
        };

        let expected = run_with(&kit, None, &mut Scripted(answer));

        let clock = || 0.0;
        let options = RunOptions {
            filter: None,
            driver_version: "test".into(),
            kit_version: "test".into(),
            started_at: "1970-01-01T00:00:00.000Z".into(),
            clock: &clock,
        };
        let mut testee = Scripted(answer);
        let mut state = RunState::open(&mut testee);
        let mut records = kit_error_records(&kit);
        for case in &kit.cases {
            records.extend(run_case(&kit, case, &mut state, &mut testee, options.clock));
        }
        let report = report_of(&state, &options, records);

        assert_eq!(report, expected.report);
    }
}
