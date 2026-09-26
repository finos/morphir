//! Comparison rules (IR suite README, "What the driver does with a case"). An
//! adapter answers with strings, never parsed structures, so canonicals are
//! compared as strings, allowing exactly one trailing newline of slack;
//! warnings and rejections are checked against what the fence declared.

use std::sync::LazyLock;

use regex::Regex;
use similar::TextDiff;

use crate::report::{Outcome, ReportDiagnostic};
use crate::transport::protocol::{DecodeResponse, Diagnostic, Warning};

/// Drops one trailing `\r\n` or `\n`.
pub fn normalize_canonical(text: &str) -> &str {
    text.strip_suffix("\r\n")
        .or_else(|| text.strip_suffix('\n'))
        .unwrap_or(text)
}

/// The tree comparison needs the set's path budget, and the runner may not
/// parse either profile, so the number is read lexically from the manifest
/// fence with one expression that matches both spellings.
static PATH_BUDGET: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"(?m)"pathBudget"\s*:\s*([0-9]+)|^pathBudget\s*:\s*([0-9]+)\s*$"#).expect("valid")
});

pub fn path_budget_of(manifest: &str) -> Option<u64> {
    let captures = PATH_BUDGET.captures(manifest)?;
    captures
        .get(1)
        .or_else(|| captures.get(2))?
        .as_str()
        .parse()
        .ok()
}

/// The first differing line, or `None` when the two agree.
pub fn check_canonical(expected: &str, actual: &str) -> Option<String> {
    let e: Vec<&str> = normalize_canonical(expected).split('\n').collect();
    let a: Vec<&str> = normalize_canonical(actual).split('\n').collect();
    (0..e.len().max(a.len())).find_map(|i| {
        let el = e.get(i).copied().unwrap_or("<end>");
        let al = a.get(i).copied().unwrap_or("<end>");
        (el != al).then(|| format!("line {} differs: expected {el} got {al}", i + 1))
    })
}

/// A bounded, three-context-line diff for canonicals already known to differ.
pub fn canonical_diff(expected: &str, actual: &str, context: &str) -> String {
    const MAX_LINES: usize = 200;
    const MAX_BYTES: usize = 16 * 1024;
    let expected = format!("{}\n", normalize_canonical(expected));
    let actual = format!("{}\n", normalize_canonical(actual));
    let old = format!("expected {context}");
    let new = format!("actual {context}");
    let full = TextDiff::from_lines(&expected, &actual)
        .unified_diff()
        .context_radius(3)
        .header(&old, &new)
        .to_string();
    let lines: Vec<&str> = full.split_inclusive('\n').collect();
    let mut out = String::new();
    for (index, line) in lines.iter().enumerate() {
        if index >= MAX_LINES || out.len() + line.len() > MAX_BYTES {
            out.push_str(&format!("... {} diff lines omitted\n", lines.len() - index));
            break;
        }
        out.push_str(line);
    }
    out
}

/// Checks the warnings against the one code a fence may declare.
pub fn check_warnings(wanted: Option<&str>, warnings: &[Warning]) -> Option<String> {
    match wanted {
        None => warnings
            .first()
            .map(|w| format!("warned unexpectedly: {} at {}", w.code, w.cursor)),
        Some(wanted) if warnings.is_empty() => Some(format!(
            "should have warned {wanted} and nothing else (got nothing)"
        )),
        Some(wanted) => warnings.iter().find(|w| w.code != wanted).map(|bad| {
            format!(
                "should have warned {wanted} and nothing else (got {} at {})",
                bad.code, bad.cursor
            )
        }),
    }
}

pub fn describe(d: &Diagnostic) -> String {
    format!(
        "{} at {}: {}",
        d.code,
        d.cursor.as_deref().unwrap_or("/"),
        d.message.as_deref().unwrap_or("")
    )
}

/// What a `rejected` fence's check decided.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rejection {
    pub result: Outcome,
    pub expected_diagnostic: Option<String>,
    pub observed_diagnostic: Option<ReportDiagnostic>,
    pub message: Option<String>,
}

/// A `rejected` fence names exactly one of `diagnostic=` (the expected code)
/// or `expect=` (the node kind, when the fence in fact decodes).
pub fn check_rejected(
    diagnostic: Option<&str>,
    expect: Option<&str>,
    response: &DecodeResponse,
) -> Rejection {
    let verdict = |result,
                   expected: Option<&str>,
                   observed: Option<&Diagnostic>,
                   message: Option<String>| Rejection {
        result,
        expected_diagnostic: expected.map(str::to_owned),
        observed_diagnostic: observed.map(ReportDiagnostic::from),
        message,
    };
    if let Some(wanted) = diagnostic {
        return match response {
            DecodeResponse::Rejected(d) if d.code == wanted => {
                verdict(Outcome::Pass, Some(wanted), Some(d), None)
            }
            DecodeResponse::Rejected(d) => verdict(
                Outcome::Fail,
                Some(wanted),
                Some(d),
                Some(format!("expected {wanted}, got {}", describe(d))),
            ),
            DecodeResponse::Ok { kind, .. } => verdict(
                Outcome::Fail,
                Some(wanted),
                None,
                Some(format!(
                    "expected {wanted}, but the fence decoded as {kind}"
                )),
            ),
        };
    }
    if let Some(wanted) = expect {
        return match response {
            DecodeResponse::Ok { kind, .. } if kind == wanted => {
                verdict(Outcome::Pass, None, None, None)
            }
            DecodeResponse::Ok { kind, .. } => verdict(
                Outcome::Fail,
                None,
                None,
                Some(format!("expected a {wanted}, decoded a {kind}")),
            ),
            DecodeResponse::Rejected(d) => verdict(
                Outcome::Fail,
                None,
                None,
                Some(format!("expected a {wanted}, got {}", describe(d))),
            ),
        };
    }
    verdict(
        Outcome::Fail,
        None,
        None,
        Some("rejected fence has neither diagnostic= nor expect=".to_owned()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_trailing_newline_is_slack_and_nothing_else() {
        assert_eq!(normalize_canonical("a\n"), "a");
        assert_eq!(normalize_canonical("a\r\n"), "a");
        assert_eq!(normalize_canonical("a\n\n"), "a\n");
        assert_eq!(check_canonical("a\nb\n", "a\nb"), None);
        assert_eq!(
            check_canonical("a\nb", "a\nc").unwrap(),
            "line 2 differs: expected b got c"
        );
        assert_eq!(
            check_canonical("a", "a\nb").unwrap(),
            "line 2 differs: expected <end> got b"
        );
    }

    #[test]
    fn unified_mismatch_names_the_fence_and_shows_context() {
        let diff = canonical_diff(
            "one\ntwo\nthree\nfour\nfive\n",
            "one\ntwo\nchanged\nfour\nfive\n",
            "types-0001 fence 2 profile yaml",
        );
        assert!(diff.starts_with("--- expected types-0001 fence 2 profile yaml\n+++ actual types-0001 fence 2 profile yaml\n"));
        assert!(diff.contains("@@"));
        assert!(diff.contains("-three\n+changed\n"));
        assert!(diff.contains(" two\n"));
    }

    #[test]
    fn unified_mismatch_is_bounded_and_announces_omitted_lines() {
        let expected = (0..500)
            .map(|i| format!("before-{i}\n"))
            .collect::<String>();
        let actual = (0..500).map(|i| format!("after-{i}\n")).collect::<String>();
        let diff = canonical_diff(&expected, &actual, "large-0001 fence 0 profile json");
        assert!(diff.len() <= 17_000);
        assert!(diff.contains("diff lines omitted"));
        let huge = canonical_diff(
            &"x".repeat(20_000),
            &"y".repeat(20_000),
            "large-0002 fence 0 profile ion",
        );
        assert!(huge.len() <= 17_000);
        assert!(huge.contains("diff lines omitted"));
    }

    #[test]
    fn round_trip_ion_diff_names_the_answer_profile() {
        let diff = canonical_diff(
            "{a:1}\n",
            "{a:2}\n",
            "values-0003 step 2 round-trip via yaml",
        );
        assert!(diff.contains("--- expected values-0003 step 2 round-trip via yaml"));
        assert!(diff.contains("+++ actual values-0003 step 2 round-trip via yaml"));
        assert!(diff.contains("-{a:1}\n+{a:2}\n"));
    }

    #[test]
    fn the_path_budget_is_read_from_either_profile() {
        assert_eq!(
            path_budget_of("formatVersion: 4\npathBudget: 4000\n"),
            Some(4000)
        );
        assert_eq!(path_budget_of("{\n  \"pathBudget\" : 512\n}"), Some(512));
        assert_eq!(
            path_budget_of("  pathBudget: 4000\n"),
            None,
            "a nested key is not the manifest's"
        );
        assert_eq!(path_budget_of("pathBudget: many\n"), None);
    }

    #[test]
    fn warnings_must_be_exactly_the_declared_code() {
        let w = |code: &str| Warning {
            code: code.into(),
            cursor: "/x".into(),
        };
        assert_eq!(check_warnings(None, &[]), None);
        assert_eq!(
            check_warnings(None, &[w("a")]).unwrap(),
            "warned unexpectedly: a at /x"
        );
        assert_eq!(check_warnings(Some("a"), &[w("a"), w("a")]), None);
        assert!(
            check_warnings(Some("a"), &[])
                .unwrap()
                .contains("(got nothing)")
        );
        assert!(
            check_warnings(Some("a"), &[w("a"), w("b")])
                .unwrap()
                .contains("(got b at /x)")
        );
    }

    #[test]
    fn rejections_match_the_declared_code_or_kind() {
        let rejected = DecodeResponse::Rejected(Diagnostic {
            code: "duplicate_member".into(),
            stage: None,
            cursor: Some("/a".into()),
            message: Some("twice".into()),
        });
        let decoded = DecodeResponse::Ok {
            kind: "Record".into(),
            canonical: vec![],
            warnings: vec![],
        };
        assert_eq!(
            check_rejected(Some("duplicate_member"), None, &rejected).result,
            Outcome::Pass
        );
        assert_eq!(
            check_rejected(Some("other"), None, &rejected)
                .message
                .unwrap(),
            "expected other, got duplicate_member at /a: twice"
        );
        assert_eq!(
            check_rejected(Some("other"), None, &decoded)
                .message
                .unwrap(),
            "expected other, but the fence decoded as Record"
        );
        assert_eq!(
            check_rejected(None, Some("Record"), &decoded).result,
            Outcome::Pass
        );
        assert_eq!(
            check_rejected(None, Some("Tuple"), &decoded)
                .message
                .unwrap(),
            "expected a Tuple, decoded a Record"
        );
    }
}
