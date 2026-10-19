use super::super::{DecodeLimits, Decoder};
use super::*;
use serde_json::{Value, json};

struct Sink<'source> {
    limit: usize,
    visits: usize,
    fault: bool,
    aliases: Vec<(&'source FixtureAlias, Site)>,
}
impl<'source> AliasSink<'source> for Sink<'source> {
    type Error = ();
    fn enter(&mut self, _trail: &Trail<'_>) -> Result<(), ()> {
        if self.fault {
            return Err(());
        }
        if self.visits == self.limit {
            self.fault = true;
            return Err(());
        }
        self.visits += 1;
        Ok(())
    }
    fn alias(&mut self, alias: &'source FixtureAlias, trail: &Trail<'_>) -> Result<(), ()> {
        let mut current = Some(trail);
        while let Some(at) = current {
            if let Segment::Field(site) = at.segment {
                self.aliases.push((alias, site));
                return Ok(());
            }
            current = at.parent;
        }
        panic!("alias omitted its code-issued field site")
    }
}
fn source() -> input::Scenario {
    let mut raw: Value = serde_json::from_str(include_str!("../pairing/input.json")).unwrap();
    raw["runs"] = json!([{"role":"model-originals-client","fixture":{
        "files":[{"alias":"FileA","bytes":{"kind":"utf8","text":"{\"alias\":\"Hidden\"}"}}],
        "literalPeers":[{"alias":"PeerA","frames":[{"kind":"literal","text":"{\"alias\":\"Hidden\"}"}],"requests":[]}],
        "runtime":{"kind":"controlled-native-workspace-v1","peer":"PeerA","runtime":"RuntimeA","entryUrl":"https://proton.localhost/","mapping":"capability-checks"}
    },"actions":[
        {"kind":"begin-native-initialize","pending":"InitializeA","runtime":"RuntimeA"},
        {"kind":"await-native-boundary","pending":"InitializeA","boundary":"initialized"},
        {"kind":"cancel-opening","attempt":"OpeningA"}
    ]}]);
    Decoder::new(
        DecodeLimits::new(1_048_576, 67_108_864, 1_000_000, 67_108_864, 1_000_000).unwrap(),
    )
    .decode(&raw.to_string())
    .unwrap()
}
#[test]
fn actual_domain_walk_borrows_aliases_with_exact_static_sites_and_ignores_payload_strings() {
    let source = source();
    let mut sink = Sink {
        limit: 10000,
        visits: 0,
        fault: false,
        aliases: vec![],
    };
    source
        .walk(
            &Trail {
                parent: None,
                segment: Segment::Root,
            },
            &mut sink,
        )
        .unwrap();
    let actual: Vec<_> = sink
        .aliases
        .iter()
        .map(|(a, s)| (a.as_str(), s.declaration, s.variant, s.field))
        .collect();
    assert_eq!(
        actual,
        vec![
            (
                "InitializeA",
                "ClientAction",
                Some("begin-native-initialize"),
                "pending"
            ),
            (
                "RuntimeA",
                "ClientAction",
                Some("begin-native-initialize"),
                "runtime"
            ),
            (
                "InitializeA",
                "ClientAction",
                Some("await-native-boundary"),
                "pending"
            ),
            (
                "OpeningA",
                "ClientAction",
                Some("cancel-opening"),
                "attempt"
            ),
            ("FileA", "ClientFixtureFilesItem", None, "alias"),
            ("PeerA", "ClientFixtureLiteralPeersItem", None, "alias"),
            (
                "PeerA",
                "ClientRuntime",
                Some("controlled-native-workspace-v1"),
                "peer"
            ),
            (
                "RuntimeA",
                "ClientRuntime",
                Some("controlled-native-workspace-v1"),
                "runtime"
            )
        ]
    );
    let input::Run::ModelOriginalsClient { fixture, .. } = &source.runs.0[0] else {
        panic!("source role")
    };
    assert!(std::ptr::eq(sink.aliases[4].0, &fixture.files.0[0].alias));
    assert!(
        sink.aliases
            .iter()
            .all(|(_, site)| site.operand == Operand::Input)
    );
}
#[test]
fn exhausted_walk_owner_refuses_before_any_alias_and_stays_latched() {
    let source = source();
    let mut sink = Sink {
        limit: 1,
        visits: 0,
        fault: false,
        aliases: vec![],
    };
    let trail = Trail {
        parent: None,
        segment: Segment::Root,
    };
    assert!(source.walk(&trail, &mut sink).is_err());
    assert!(sink.aliases.is_empty());
    assert_eq!(sink.visits, 1);
    assert!(source.walk(&trail, &mut sink).is_err());
    assert!(sink.aliases.is_empty());
    assert_eq!(sink.visits, 1);
}
