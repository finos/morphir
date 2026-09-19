//! IR format-version support tables (`docs/spec/ir/format-version.md`,
//! "Recognition and compatibility"): a union of intervals over release
//! strings in Maven-style interval notation, one canonical spelling,
//! membership, and the prose rendering the runner prints.
//!
//! The runner needs these to check an adapter's `formatVersions` claim. It
//! implements the specification here rather than borrowing any binding's
//! codec, and is tested against the parent-owned conformance corpus
//! (`docs/spec/ir/fixtures/format-version-conformance.json`).

use std::cmp::Ordering;
use std::fmt;

/// The largest value of a release component.
pub const COMPONENT_MAX: u32 = u32::MAX;

/// An exact release `major.minor.patch`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Release {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

impl Release {
    pub const fn new(major: u32, minor: u32, patch: u32) -> Self {
        Self {
            major,
            minor,
            patch,
        }
    }

    /// Parses a release string: three unsigned decimal components without
    /// leading zeros, each at most `COMPONENT_MAX`, with a major of at least 3.
    pub fn parse(text: &str) -> Result<Self, String> {
        let component = |part: &str| -> Option<u32> {
            let digits = !part.is_empty() && part.bytes().all(|b| b.is_ascii_digit());
            let canonical = part == "0" || !part.starts_with('0');
            (digits && canonical)
                .then(|| part.parse::<u32>().ok())
                .flatten()
        };
        let parts: Vec<&str> = text.split('.').collect();
        let [major, minor, patch] = parts.as_slice() else {
            return Err(format!("\"{text}\" is not a release string"));
        };
        let well_formed = [major, minor, patch].iter().all(|part| {
            !part.is_empty()
                && part.bytes().all(|b| b.is_ascii_digit())
                && (**part == "0" || !part.starts_with('0'))
        });
        if !well_formed {
            return Err(format!("\"{text}\" is not a release string"));
        }
        let (Some(major), Some(minor), Some(patch)) =
            (component(major), component(minor), component(patch))
        else {
            return Err(format!("\"{text}\" has a component above {COMPONENT_MAX}"));
        };
        if major < 3 {
            return Err(format!(
                "release strings are valid only for major 3 and later, got \"{text}\""
            ));
        }
        Ok(Self {
            major,
            minor,
            patch,
        })
    }

    /// The next patch, without carrying: `None` at the patch maximum. Used for
    /// the canonical spelling, which never moves a bound into another minor.
    fn next(self) -> Option<Self> {
        (self.patch != COMPONENT_MAX).then(|| Self {
            patch: self.patch + 1,
            ..self
        })
    }

    /// The release immediately after this one, carrying into the minor and
    /// then the major: which release an exclusive bound admits first.
    fn successor(self) -> Option<Self> {
        if self.patch != COMPONENT_MAX {
            Some(Self {
                patch: self.patch + 1,
                ..self
            })
        } else if self.minor != COMPONENT_MAX {
            Some(Self {
                minor: self.minor + 1,
                patch: 0,
                ..self
            })
        } else if self.major != COMPONENT_MAX {
            Some(Self::new(self.major + 1, 0, 0))
        } else {
            None
        }
    }
}

impl fmt::Display for Release {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}.{}", self.major, self.minor, self.patch)
    }
}

/// The smallest release the domain has: nothing below major 3 can be written.
pub const DOMAIN_FLOOR: Release = Release::new(3, 0, 0);

/// One bound of an interval.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Bound {
    pub release: Release,
    pub inclusive: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Interval {
    pub lower: Option<Bound>,
    pub upper: Option<Bound>,
}

impl Interval {
    /// The smallest release the lower bound admits, or `None` when none exists.
    fn smallest_admitted(&self) -> Option<Release> {
        match self.lower {
            None => Some(DOMAIN_FLOOR),
            Some(Bound {
                release,
                inclusive: true,
            }) => Some(release),
            Some(Bound {
                release,
                inclusive: false,
            }) => release.successor(),
        }
    }

    fn below_upper(&self, release: Release) -> bool {
        match self.upper {
            None => true,
            Some(upper) => match release.cmp(&upper.release) {
                Ordering::Less => true,
                Ordering::Equal => upper.inclusive,
                Ordering::Greater => false,
            },
        }
    }

    fn contains(&self, release: Release) -> bool {
        if release < DOMAIN_FLOOR {
            return false;
        }
        let above_lower = match self.lower {
            None => true,
            Some(lower) => match lower.release.cmp(&release) {
                Ordering::Less => true,
                Ordering::Equal => lower.inclusive,
                Ordering::Greater => false,
            },
        };
        above_lower && self.below_upper(release)
    }

    /// Whether the interval holds any release of `major`: a question about
    /// containment, not about the majors its bounds are spelled with.
    pub fn holds_major(&self, major: u32) -> bool {
        let family_start = Release::new(major, 0, 0);
        let Some(admitted) = self.smallest_admitted() else {
            return false;
        };
        let candidate = admitted.max(family_start);
        candidate.major == major && self.below_upper(candidate)
    }

    /// The half-open canonical form, or an error when the interval is empty.
    fn normalized(self, spelled: &str) -> Result<Self, String> {
        let lower = self.lower.map(|bound| match bound {
            Bound {
                release,
                inclusive: false,
            } => match release.next() {
                Some(next) => Bound {
                    release: next,
                    inclusive: true,
                },
                None => bound,
            },
            inclusive => inclusive,
        });
        let upper = self.upper.map(|bound| match bound {
            Bound {
                release,
                inclusive: true,
            } => match release.next() {
                Some(next) => Bound {
                    release: next,
                    inclusive: false,
                },
                None => bound,
            },
            exclusive => exclusive,
        });
        let normalized = Self { lower, upper };
        match normalized.smallest_admitted() {
            Some(smallest) if normalized.below_upper(smallest) => Ok(normalized),
            _ => Err(format!("{spelled}: the interval contains no release")),
        }
    }
}

/// Orders intervals by the first release their lower bound admits, an absent
/// lower bound first; on a tie the inclusive spelling comes first.
fn compare_lower(a: &Interval, b: &Interval) -> Ordering {
    match (a.lower, b.lower) {
        (None, None) => return Ordering::Equal,
        (None, Some(_)) => return Ordering::Less,
        (Some(_), None) => return Ordering::Greater,
        _ => {}
    }
    match (a.smallest_admitted(), b.smallest_admitted()) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Greater,
        (Some(_), None) => Ordering::Less,
        (Some(x), Some(y)) => x.cmp(&y).then_with(|| {
            let inclusive = |i: &Interval| i.lower.is_some_and(|l| l.inclusive);
            inclusive(b).cmp(&inclusive(a))
        }),
    }
}

/// Whether `a`'s upper reaches `b`'s lower: overlap or adjacency.
fn touches(a: &Interval, b: &Interval) -> bool {
    let (Some(upper), Some(lower)) = (a.upper, b.lower) else {
        return true;
    };
    match lower.release.cmp(&upper.release) {
        Ordering::Less => true,
        Ordering::Equal => upper.inclusive || lower.inclusive,
        Ordering::Greater => {
            upper.inclusive
                && upper
                    .release
                    .successor()
                    .is_some_and(|s| lower.release <= s)
        }
    }
}

fn union(a: &Interval, b: &Interval) -> Interval {
    let lower = match (a.lower, b.lower) {
        (Some(_), Some(_)) => {
            if compare_lower(a, b) != Ordering::Greater {
                a.lower
            } else {
                b.lower
            }
        }
        _ => None,
    };
    let upper = match (a.upper, b.upper) {
        (Some(x), Some(y)) => Some(match x.release.cmp(&y.release) {
            Ordering::Greater => x,
            Ordering::Less => y,
            Ordering::Equal => Bound {
                release: x.release,
                inclusive: x.inclusive || y.inclusive,
            },
        }),
        _ => None,
    };
    Interval { lower, upper }
}

/// A validated, merged, sorted support table.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SupportTable(Vec<Interval>);

/// The result of checking a release against a table.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Compatibility {
    Supported,
    UnsupportedMajor,
    UnsupportedMinor,
}

impl Compatibility {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Supported => "supported",
            Self::UnsupportedMajor => "unsupported_format_version_major",
            Self::UnsupportedMinor => "unsupported_format_version_minor",
        }
    }
}

fn is_space(c: char) -> bool {
    super::kit::syntax::text::is_js_whitespace(c)
}

impl SupportTable {
    /// Parses the interval notation, normalizing and merging as it goes.
    pub fn parse(text: &str) -> Result<Self, String> {
        let mut intervals = Vec::new();
        let mut rest = text.trim_start_matches(is_space);
        while !rest.is_empty() {
            if !intervals.is_empty() {
                let offset = text.len() - rest.len();
                rest = rest
                    .strip_prefix(',')
                    .ok_or_else(|| format!("expected \",\" at offset {offset} in \"{text}\""))?
                    .trim_start_matches(is_space);
            }
            let offset = text.len() - rest.len();
            let expected = || format!("expected an interval at offset {offset} in \"{text}\"");
            let open = rest
                .chars()
                .next()
                .filter(|c| matches!(c, '[' | '('))
                .ok_or_else(expected)?;
            let close_at = rest[1..]
                .find([']', ')', '[', '('])
                .map(|i| i + 1)
                .ok_or_else(expected)?;
            let close = rest[close_at..]
                .chars()
                .next()
                .filter(|c| matches!(c, ']' | ')'))
                .ok_or_else(expected)?;
            let raw = &rest[..=close_at];
            let spelled: String = raw.chars().filter(|c| !is_space(*c)).collect();
            let inner: Vec<&str> = rest[1..close_at]
                .split(',')
                .map(|s| s.trim_matches(is_space))
                .collect();
            let release = |s: &str| Release::parse(s).map_err(|why| format!("{spelled}: {why}"));
            let interval = match inner.as_slice() {
                [exact] => {
                    if open != '[' || close != ']' {
                        return Err(format!("{spelled}: an exact release uses square brackets"));
                    }
                    let exact = release(exact)?;
                    let bound = Bound {
                        release: exact,
                        inclusive: true,
                    };
                    Interval {
                        lower: Some(bound),
                        upper: Some(bound),
                    }
                }
                ["", ""] => return Err(format!("{spelled}: at least one bound is required")),
                [lo, hi] => Interval {
                    lower: (!lo.is_empty())
                        .then(|| release(lo))
                        .transpose()?
                        .map(|r| Bound {
                            release: r,
                            inclusive: open == '[',
                        }),
                    upper: (!hi.is_empty())
                        .then(|| release(hi))
                        .transpose()?
                        .map(|r| Bound {
                            release: r,
                            inclusive: close == ']',
                        }),
                },
                _ => return Err(format!("{spelled}: an interval has at most two bounds")),
            };
            intervals.push(interval.normalized(&spelled)?);
            rest = rest[close_at + 1..].trim_start_matches(is_space);
        }
        if intervals.is_empty() {
            return Err("a support table needs at least one interval".to_owned());
        }

        intervals.sort_by(compare_lower);
        let mut merged: Vec<Interval> = Vec::new();
        for interval in intervals {
            match merged.last_mut() {
                Some(last) if touches(last, &interval) => *last = union(last, &interval),
                _ => merged.push(interval),
            }
        }
        if merged
            .iter()
            .any(|i| i.lower.is_none() && i.upper.is_none())
        {
            return Err(format!(
                "\"{text}\": the table admits every release; a support table must exclude some release"
            ));
        }
        Ok(Self(merged))
    }

    pub fn intervals(&self) -> &[Interval] {
        &self.0
    }

    /// The one canonical spelling writers, adapters and reports emit.
    pub fn canonical(&self) -> String {
        self.0
            .iter()
            .map(|i| {
                let open = if i.lower.is_some_and(|l| l.inclusive) {
                    '['
                } else {
                    '('
                };
                let close = if i.upper.is_some_and(|u| u.inclusive) {
                    ']'
                } else {
                    ')'
                };
                let lower = i.lower.map(|l| l.release.to_string()).unwrap_or_default();
                let upper = i.upper.map(|u| u.release.to_string()).unwrap_or_default();
                format!("{open}{lower},{upper}{close}")
            })
            .collect::<Vec<_>>()
            .join(",")
    }

    pub fn supports(&self, release: Release) -> bool {
        self.0.iter().any(|i| i.contains(release))
    }

    /// Whether any interval holds a release of `major`.
    pub fn touches_major(&self, major: u32) -> bool {
        self.0.iter().any(|i| i.holds_major(major))
    }

    pub fn compatibility(&self, release: Release) -> Compatibility {
        if self.supports(release) {
            Compatibility::Supported
        } else if self.touches_major(release.major) {
            Compatibility::UnsupportedMinor
        } else {
            Compatibility::UnsupportedMajor
        }
    }

    /// The prose reading, as the capabilities header line prints it.
    pub fn prose(&self) -> String {
        self.0
            .iter()
            .map(|i| {
                let lo = i.lower.map(|l| l.release.to_string());
                let hi = i.upper.map(|u| u.release.to_string());
                let lower_inclusive = i.lower.is_some_and(|l| l.inclusive);
                let upper_inclusive = i.upper.is_some_and(|u| u.inclusive);
                match (lo, hi) {
                    (None, None) => "every release".to_owned(),
                    (None, Some(hi)) if upper_inclusive => format!("{hi} and earlier"),
                    (None, Some(hi)) => format!("earlier than {hi}"),
                    (Some(lo), None) if lower_inclusive => format!("{lo} and later"),
                    (Some(lo), None) => format!("after {lo}"),
                    (Some(lo), Some(hi)) => {
                        let start = if lower_inclusive {
                            lo
                        } else {
                            format!("after {lo}")
                        };
                        if upper_inclusive {
                            format!("{start} through {hi}")
                        } else {
                            format!("{start} up to but not including {hi}")
                        }
                    }
                }
            })
            .collect::<Vec<_>>()
            .join(", or ")
    }
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;

    fn corpus() -> Value {
        let raw = include_str!("../../../docs/spec/ir/fixtures/format-version-conformance.json");
        serde_json::from_str(raw.trim_start_matches('\u{FEFF}')).unwrap()
    }

    #[test]
    fn parses_and_spells_every_corpus_table() {
        let cases = corpus()["supportTableCases"]["parse"]
            .as_array()
            .unwrap()
            .clone();
        assert!(cases.len() >= 30);
        for case in cases {
            let name = case["name"].as_str().unwrap();
            let parsed = SupportTable::parse(case["input"].as_str().unwrap());
            if case["invalid"].as_bool() == Some(true) {
                assert!(parsed.is_err(), "{name}: expected invalid, got {parsed:?}");
            } else {
                let table = parsed.unwrap_or_else(|e| panic!("{name}: {e}"));
                assert_eq!(
                    table.canonical(),
                    case["canonical"].as_str().unwrap(),
                    "{name}"
                );
                assert_eq!(
                    SupportTable::parse(&table.canonical()).unwrap(),
                    table,
                    "{name}: canonical round-trips"
                );
            }
        }
    }

    #[test]
    fn answers_every_corpus_membership_question() {
        for case in corpus()["supportTableCases"]["membership"]
            .as_array()
            .unwrap()
        {
            let table = SupportTable::parse(case["table"].as_str().unwrap()).unwrap();
            let text = case["release"].as_str().unwrap();
            let expected = case["compatibility"].as_str().unwrap();
            // Releases below the domain are not release strings, but the
            // corpus asks about 2.0.0 as a recognized historical major.
            let release = Release::parse(text).unwrap_or_else(|_| {
                let parts: Vec<u32> = text.split('.').map(|p| p.parse().unwrap()).collect();
                Release::new(parts[0], parts[1], parts[2])
            });
            assert_eq!(
                table.compatibility(release).as_str(),
                expected,
                "{} in {}",
                text,
                case["table"]
            );
        }
    }

    #[test]
    fn renders_every_corpus_table_as_prose() {
        for case in corpus()["supportTableCases"]["render"].as_array().unwrap() {
            let table = SupportTable::parse(case["table"].as_str().unwrap()).unwrap();
            assert_eq!(
                table.prose(),
                case["prose"].as_str().unwrap(),
                "{}",
                case["table"]
            );
        }
    }

    #[test]
    fn the_reference_table_reads_as_the_driver_header_does() {
        let table = SupportTable::parse("[4.0.0,4.1.0)").unwrap();
        assert_eq!(table.prose(), "4.0.0 up to but not including 4.1.0");
        assert!(table.touches_major(4) && !table.touches_major(3));
    }

    #[test]
    fn releases_are_strict() {
        assert_eq!(Release::parse("4.0.1"), Ok(Release::new(4, 0, 1)));
        for bad in [
            "4",
            "4.0",
            "4.0.0.0",
            "04.0.0",
            "4.00.0",
            "4.0.0-beta",
            "+4.0.0",
            " 4.0.0",
            "2.0.0",
            "4.4294967296.0",
            "4..0",
        ] {
            assert!(Release::parse(bad).is_err(), "{bad}");
        }
        assert!(Release::parse("4.4294967295.0").is_ok());
    }
}
