///|
test "documents per unit is a number when limited and no limit otherwise" {
  let limited : @engine.SourceCapabilities = {
    summary: "Test",
    supported: [],
    excluded: [],
    max_documents: Some(1),
    incremental: false,
    limits: Map([]),
  }
  let unlimited = { ..limited, max_documents: None, }
  assert_eq(documents_per_unit(limited), "1")
  assert_eq(documents_per_unit(unlimited), "no limit")
  assert_true(
    capabilities_json(limited).stringify().contains("\"maxDocuments\":1"),
  )
  assert_true(
    capabilities_json(unlimited).stringify().contains("\"maxDocuments\":null"),
  )
}
