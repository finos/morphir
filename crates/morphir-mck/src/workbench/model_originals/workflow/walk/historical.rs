//! Borrow actual historical fields at matching schema sites. This does not
//! construct a current root or walk synthetic ledger allowances.
use super::super::historical::{
    HistoricalClientExpected, HistoricalClientScenario, HistoricalLimits11,
};
use super::*;
impl WalkAliases for HistoricalLimits11 {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        self.actions.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "actions",
                )),
            },
            sink,
        )?;
        self.corpus_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "corpusBytes",
                )),
            },
            sink,
        )?;
        self.events.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(Operand::Input, "Limits", None, "events")),
            },
            sink,
        )?;
        self.evidence_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "evidenceBytes",
                )),
            },
            sink,
        )?;
        self.expanded_decoded_and_read_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "expandedDecodedAndReadBytes",
                )),
            },
            sink,
        )?;
        self.expanded_wire_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "expandedWireBytes",
                )),
            },
            sink,
        )?;
        self.input_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "inputBytes",
                )),
            },
            sink,
        )?;
        self.metadata_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "metadataBytes",
                )),
            },
            sink,
        )?;
        self.observations_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "observationsBytes",
                )),
            },
            sink,
        )?;
        self.observer_byte_visits.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "observerByteVisits",
                )),
            },
            sink,
        )?;
        self.report_bytes.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Limits",
                    None,
                    "reportBytes",
                )),
            },
            sink,
        )?;
        Ok(())
    }
}
impl WalkAliases for HistoricalClientScenario {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        self.limits.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Scenario",
                    None,
                    "limits",
                )),
            },
            sink,
        )?;
        self.origin.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Input,
                    "Scenario",
                    None,
                    "origin",
                )),
            },
            sink,
        )?;
        self.runs.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(Operand::Input, "Scenario", None, "runs")),
            },
            sink,
        )?;
        Ok(())
    }
}
impl WalkAliases for HistoricalClientExpected {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        self.bindings.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "bindings",
                )),
            },
            sink,
        )?;
        self.byte_sources.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "byteSources",
                )),
            },
            sink,
        )?;
        self.checks.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "checks",
                )),
            },
            sink,
        )?;
        self.commentary.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "commentary",
                )),
            },
            sink,
        )?;
        self.lineage.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "lineage",
                )),
            },
            sink,
        )?;
        self.origin.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "origin",
                )),
            },
            sink,
        )?;
        self.outcome.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "outcome",
                )),
            },
            sink,
        )?;
        self.qualification.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "qualification",
                )),
            },
            sink,
        )?;
        self.rich_sources.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "richSources",
                )),
            },
            sink,
        )?;
        self.run_index.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "runIndex",
                )),
            },
            sink,
        )?;
        self.teardown.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "teardown",
                )),
            },
            sink,
        )?;
        self.trace_sources.walk(
            &Trail {
                parent: Some(trail),
                segment: Segment::Field(Site::descriptor(
                    Operand::Expected,
                    "ExpectedWorkflow",
                    Some("model-originals-client"),
                    "traceSources",
                )),
            },
            sink,
        )?;
        sink.enter(trail)?;
        sink.enter(trail)?;
        Ok(())
    }
}
