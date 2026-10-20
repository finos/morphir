//! Source-first diagnostic compatibility of the shared recipe ADT. Pure typed
//! DATA/walk work guards only, no source/expected byte or filesystem authority.
use super::super::{Decode, DecodeLimits, Decoder};
use super::*;
struct Budget {
    remaining: usize,
}
impl<'source> AliasSink<'source> for Budget {
    type Error = Site;
    fn enter(&mut self, trail: &Trail<'_>) -> Result<(), Site> {
        if self.remaining == 0 {
            if let Segment::Field(site) = trail.segment {
                return Err(site);
            }
            panic!("guarded field visit")
        }
        self.remaining -= 1;
        Ok(())
    }
    fn alias(&mut self, _: &'source FixtureAlias, _: &Trail<'_>) -> Result<(), Site> {
        Ok(())
    }
}
fn decoder() -> Decoder {
    Decoder::new(DecodeLimits::new(4096, 65536, 4096, 65536, 4096).unwrap())
}
#[test]
fn shared_recipe_expected_low_work_refusal_retains_expected_site() {
    // Exactly4 permitted visits: record,alias,length,recipe. Refusal is on the
    // next actual recipe text field. Hash is unused parser DATA, not an oracle.
    let doc=crate::json::strict::Document::parse_exact(br#"{"alias":"local","byteLength":1,"bytes":{"kind":"utf8","text":"x"},"sha256":"0000000000000000000000000000000000000000000000000000000000000000"}"#).unwrap();
    let actual = domain::ExpectedByteSource::decode(&doc, &mut decoder()).unwrap();
    let site = actual
        .walk(
            &Trail {
                parent: None,
                segment: Segment::Root,
            },
            &mut Budget { remaining: 4 },
        )
        .unwrap_err();
    assert_eq!(
        site.parts(),
        (Operand::Expected, "Bytes", Some("utf8"), "text")
    );
}
#[test]
fn shared_recipe_input_low_work_refusal_retains_input_site() {
    let doc = crate::json::strict::Document::parse_exact(br#"{"kind":"utf8","text":"x"}"#).unwrap();
    let actual = input::Bytes::decode(&doc, &mut decoder()).unwrap();
    let site = actual
        .walk(
            &Trail {
                parent: None,
                segment: Segment::Root,
            },
            &mut Budget { remaining: 1 },
        )
        .unwrap_err();
    assert_eq!(
        site.parts(),
        (Operand::Input, "Bytes", Some("utf8"), "text")
    );
}
