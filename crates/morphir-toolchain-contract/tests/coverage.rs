//! Every row of the check tables on the contract pages is pinned by a case.
//!
//! A check table has a `Cases` column. Each row names the `rule` of the
//! cases in `cases.json` and `signed/cases.json` that pin it, or says
//! `No fixture:` and why. This test fails when a row names no case and is
//! not marked, when a rule's cases report a code or path the row does not
//! list, when a code the row lists has no case, or when a case's rule
//! appears in no table.

use morphir_toolchain_contract::Code;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

const PAGES: &[&str] = &[
    "docs/spec/toolchain/toolset-recipe.md",
    "docs/spec/toolchain/toolchain-lock.md",
    "docs/spec/toolchain/installation-receipt.md",
];

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn json(path: &str) -> Value {
    let path = root().join(path);
    serde_json::from_slice(&std::fs::read(&path).unwrap())
        .unwrap_or_else(|error| panic!("{}: {error}", path.display()))
}

/// The (code, path) each case with a `rule` expects, by rule.
fn cases_by_rule() -> BTreeMap<String, Vec<(String, String, String)>> {
    let mut rules: BTreeMap<String, Vec<(String, String, String)>> = BTreeMap::new();
    let unsigned = json("docs/spec/toolchain/fixtures/0.1.0-draft.1/cases.json");
    let signed = json("docs/spec/toolchain/fixtures/0.1.0-draft.1/signed/cases.json");
    let sections = [
        &unsigned["bindings"],
        &signed["selection"],
        &signed["recipeChecks"],
        &signed["trust"],
        &signed["lockRecipe"],
        &signed["channelSelection"],
    ];
    for section in sections {
        for case in section.as_array().unwrap() {
            let Some(rule) = case["rule"].as_str() else {
                continue;
            };
            let expected = &case["expected"];
            let code = expected["code"]
                .as_str()
                .unwrap_or_else(|| panic!("{rule}: a rule's cases are refusals"));
            rules.entry(rule.to_owned()).or_default().push((
                case["name"].as_str().unwrap().to_owned(),
                code.to_owned(),
                expected["path"].as_str().unwrap().to_owned(),
            ));
        }
    }
    rules
}

/// The backticked spans of a table cell.
fn spans(cell: &str) -> Vec<&str> {
    cell.split('`').skip(1).step_by(2).collect()
}

/// A path pattern from a table cell's path spelling.
fn path_matches(pattern: &str, path: &str) -> bool {
    fn matches(pattern: &[char], path: &[char]) -> bool {
        match pattern {
            [] => path.is_empty(),
            ['[', index, ']', rest @ ..] if index.is_ascii_lowercase() => {
                let Some(['[', tail @ ..]) = Some(path) else {
                    return false;
                };
                let digits = tail.iter().take_while(|c| c.is_ascii_digit()).count();
                digits > 0 && tail.get(digits) == Some(&']') && matches(rest, &tail[digits + 1..])
            }
            ['<', 'i', 'd', '>', rest @ ..] => (1..=path.len()).any(|end| {
                path[..end]
                    .iter()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == '-')
                    && matches(rest, &path[end..])
            }),
            ['…', rest @ ..] => (0..=path.len()).any(|start| matches(rest, &path[start..])),
            [first, rest @ ..] => path.first() == Some(first) && matches(rest, &path[1..]),
        }
    }
    let pattern = pattern.chars().collect::<Vec<_>>();
    let path = path.chars().collect::<Vec<_>>();
    matches(&pattern, &path)
}

struct Row {
    page: &'static str,
    check: String,
    codes: Option<BTreeSet<String>>,
    paths: Option<Vec<String>>,
    cases: Result<Vec<String>, String>,
}

fn rows() -> Vec<Row> {
    let mut rows = Vec::new();
    for page in PAGES {
        let text = std::fs::read_to_string(root().join(page)).unwrap();
        let mut header: Option<Vec<String>> = None;
        for line in text.lines() {
            if !line.starts_with('|') {
                header = None;
                continue;
            }
            let cells = line
                .trim()
                .trim_matches('|')
                .split(" | ")
                .map(|cell| cell.trim().to_owned())
                .collect::<Vec<_>>();
            let Some(columns) = &header else {
                header = Some(cells);
                continue;
            };
            if cells.iter().all(|cell| cell.chars().all(|c| c == '-')) {
                continue;
            }
            let column = |name: &str| columns.iter().position(|column| column == name);
            let (Some(cases), Some(code), Some(path)) =
                (column("Cases"), column("Code"), column("Path"))
            else {
                continue;
            };
            assert_eq!(cells.len(), columns.len(), "{page}: {line}");
            let codes = spans(&cells[code])
                .into_iter()
                .filter(|span| Code::parse(span).is_some())
                .map(str::to_owned)
                .collect::<BTreeSet<_>>();
            let path_cell = &cells[path];
            let paths = if path_cell == "empty" {
                Some(vec![String::new()])
            } else if path_cell.contains('`') {
                Some(spans(path_cell).into_iter().map(str::to_owned).collect())
            } else {
                None
            };
            let cases_cell = &cells[cases];
            rows.push(Row {
                page,
                check: cells[0].clone(),
                codes: (!codes.is_empty()).then_some(codes),
                paths,
                cases: match cases_cell.strip_prefix("No fixture:") {
                    Some(reason) => Err(reason.trim().to_owned()),
                    None => Ok(spans(cases_cell).into_iter().map(str::to_owned).collect()),
                },
            });
        }
    }
    rows
}

#[test]
fn every_check_table_row_is_pinned_by_its_cases() {
    let cases = cases_by_rule();
    let rows = rows();
    assert!(rows.len() >= 40, "the check tables were found");
    let mut failures = Vec::new();
    let mut named = BTreeSet::new();
    for row in &rows {
        let label = format!("{}: {}", row.page, row.check);
        let rules = match &row.cases {
            Err(reason) => {
                if reason.is_empty() {
                    failures.push(format!("{label}: `No fixture:` gives no reason"));
                }
                continue;
            }
            Ok(rules) if rules.is_empty() => {
                failures.push(format!("{label}: names no case and is not marked"));
                continue;
            }
            Ok(rules) => rules,
        };
        let mut covered = BTreeSet::new();
        for rule in rules {
            named.insert(rule.clone());
            let Some(pinned) = cases.get(rule) else {
                failures.push(format!("{label}: no case has rule {rule}"));
                continue;
            };
            for (name, code, path) in pinned {
                if let Some(codes) = &row.codes
                    && !codes.contains(code)
                {
                    failures.push(format!("{label}: {name} reports {code}"));
                }
                if let Some(paths) = &row.paths
                    && !paths.iter().any(|pattern| path_matches(pattern, path))
                {
                    failures.push(format!("{label}: {name} reports path {path:?}"));
                }
                covered.insert(code.clone());
            }
        }
        if let Some(codes) = &row.codes {
            for code in codes.difference(&covered) {
                failures.push(format!("{label}: no case reports {code}"));
            }
        }
    }
    for rule in cases.keys() {
        if !named.contains(rule) {
            failures.push(format!("rule {rule} appears in no check table"));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn path_patterns_name_indexes_keys_and_suffixes() {
    assert!(path_matches(
        "hosts[i].platforms.<id>.target",
        "hosts[0].platforms.win-x64.target"
    ));
    assert!(!path_matches("hosts[i].source", "hosts.source"));
    assert!(path_matches(
        "…artifactTarget",
        "providers[0].platforms.win-x64.artifactTarget"
    ));
    assert!(path_matches("", ""));
    assert!(!path_matches("", "hosts"));
}
