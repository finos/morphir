Feature: Versions

  @node:Value @version:3
  Scenario: versions-0001 Reading a v3 literal into the model
    A v3 tagged array with capitalized tags decodes to the same value the v4 spelling does.

    Then its canonical JSON spelling is ["Literal", {}, ["WholeNumberLiteral", 42]]

  @node:Value @version:3 @pending
  Scenario: versions-0002 Writing a Hole to v3 is refused
    The CLI refuses a v4 to v3 downgrade with `unsupported_v4_downgrade`. The kit grammar has no role for a write refusal yet; bead morphir-diwy specifies the rules for adding one. Until then this case is prose only.

  @node:FormatVersion
  Scenario: versions-0003 One YAML document
    The YAML profile admits exactly one document. A second document after `---`, or content after `...`, is refused rather than silently reading the first. YAML profile page, "Reader restrictions".

    Then its canonical YAML spelling is 4
    And a reader of YAML rejects with invalid_yaml:
      """yaml
      4
      ---
      4
      """

  @node:Distribution
  Scenario: versions-0004 No anchors, tags, merge keys or directives
    Anchors, aliases, explicit tags, merge keys, and directives are presentation and schema machinery the profile does not carry: an IR document means the same thing wherever it is read, so nothing in it may be resolved against something else. Each is refused with `unsupported_yaml_feature`. YAML profile page, "Reader restrictions".

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } } }
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: &empty {}
          def:
            modules: *empty
      """
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: !!map {}
          def:
            modules: {}
      """
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            <<: {}
            modules: {}
      """
    And a reader of YAML rejects with unsupported_yaml_feature:
      """yaml
      %YAML 1.2
      ---
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """

  @node:Distribution
  Scenario: versions-0005 Duplicate keys
    A repeated mapping key is refused with `duplicate_member`, the same diagnostic the JSON profile reports for a repeated object member: last-one-wins would make the same bytes mean different things in different readers. YAML profile page, "Reader restrictions".

    These are read and written at version 3 by any binding that declares version 3 (the Rust binding does; the reference declares only 4 and skips them). They pin the classic mirror against morphir-elm's codecs.

    Then its canonical YAML spelling is:
      """yaml
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """
    And its canonical JSON spelling is { "formatVersion": 4, "distribution": { "Library": { "packageName": "example", "dependencies": {}, "def": { "modules": {} } } } }
    And a reader of YAML rejects with duplicate_member:
      """yaml
      formatVersion: 4
      formatVersion: 4
      distribution:
        Library:
          packageName: example
          dependencies: {}
          def:
            modules: {}
      """

  @node:Literal @version:3
  Scenario: versions-0006 A v3 decimal literal keeps its text
    morphir-elm encodes `DecimalLiteral` as a string (`Decimal.toString`); a binding that reads it through a float and writes `10.5` fails this case.

    Then its canonical JSON spelling is ["DecimalLiteral", "10.50"]

  @node:TypeSpecification @version:3
  Scenario: versions-0007 A v3 derived type specification
    morphir-elm's fourth specification: `["DerivedTypeSpecification", params, { "baseType", "fromBaseType", "toBaseType" }]`, with the base type a v3 type and the two conversions v3 FQNames.

    Then its canonical JSON spelling is ["DerivedTypeSpecification", [], { "baseType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []], "fromBaseType": [[["my"], ["org"]], [["module"]], ["from", "string"]], "toBaseType": [[["my"], ["org"]], [["module"]], ["to", "string"]] }]

  @node:Type @version:3
  Scenario: versions-0008 v3 record fields are objects
    morphir-elm writes a record field as `{ "name", "tpe" }`, never as a pair.

    Then its canonical JSON spelling is ["Record", {}, [{ "name": ["first"], "tpe": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["string"]], ["string"]], []] }]]

  @node:FormatVersion @version:3
  Scenario: versions-0009 3.1.0 is supported
    IR 3.1.0 introduced the v3 `Specs` distribution (distributions-0006's classic counterpart) and the v3 document tree. Its baseline does not collapse to the bare integer `3`, the way distributions-0008 pins a later patch of a supported minor.

    Then its canonical JSON spelling is "3.1.0"

  @node:FormatVersion @version:3
  Scenario: versions-0010 3.2.0 is a later minor
    Governed by `docs/spec/ir/format-version.md`. The reader's support table names `[3.0.0,3.2.0)`, so `3.2.0` itself is refused the same way distributions-0001 refuses a v4 minor past its own table.

    Then a reader of JSON rejects "3.2.0" with unsupported_format_version_minor
