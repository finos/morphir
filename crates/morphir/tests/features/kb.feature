Feature: Manage the knowledge base
  As a Morphir contributor
  I want the kb subcommand tree to behave like the morphir-scala kb CLI
  So that bundles, concepts, intent and decisions can be managed from one binary

  Background:
    Given an empty repository

  Scenario: kb list fails when no knowledge base can be located
    When I run "morphir kb list"
    Then the command fails
    And stderr contains "error: could not locate a kb/ directory — pass --kb"

  Scenario: kb list succeeds against an empty knowledge base
    Given a knowledge base at "kb"
    When I run "morphir kb list --kb kb"
    Then the command succeeds
    And stdout contains "0 bundle(s), 0 concept(s)"

  Scenario: new-bundle then list and show round trip
    Given a knowledge base at "kb"
    When I run the command:
      """
      morphir kb new-bundle --kb kb --name test-bundle --title "Test Bundle" --description "A bundle for testing."
      """
    Then the command succeeds
    And stdout contains "created"
    And stdout contains "test-bundle/index.md"
    When I run "morphir kb list --kb kb"
    Then the command succeeds
    And stdout contains "test-bundle"
    And stdout contains "1 bundle(s), 0 concept(s)"
    When I run "morphir kb list --kb kb --bundle test-bundle"
    Then the command succeeds
    And stdout contains "Test Bundle"
    When I run "morphir kb show --kb kb --path /index.md --bundle test-bundle"
    Then the command succeeds
    And stdout contains "Test Bundle"
    And stdout contains "RootIndex"

  Scenario: add-concept produces a knowledge base that checks clean
    Given a knowledge base at "kb"
    When I run the command:
      """
      morphir kb new-bundle --kb kb --name test-bundle --title "Test Bundle" --description "A bundle for testing."
      """
    Then the command succeeds
    When I run the command:
      """
      morphir kb add-concept --kb kb --bundle test-bundle --path naming.md --type "Design Note" --title Naming --description "How names work."
      """
    Then the command succeeds
    And stdout contains "created"
    And stdout contains "naming.md"
    When I run "morphir kb check --kb kb --no-provenance"
    Then the command succeeds
    And stdout contains "0 error(s), 0 warning(s)"

  Scenario: check catches a concept with no type and exits non-zero
    Given a knowledge base at "kb"
    And a file "kb/bundles/demo/index.md" containing:
      """
      ---
      okf_version: "0.2"
      title: Demo
      description: A demo bundle.
      ---

      # Demo

      ## Orientation

      * [Broken](/broken.md) - Broken concept.
      """
    And a file "kb/bundles/demo/broken.md" containing:
      """
      ---
      title: Broken
      description: Broken concept.
      ---

      # Broken
      """
    When I run "morphir kb check --kb kb --no-provenance"
    Then the command fails
    And stdout contains "concept-missing-type"
    And stdout contains "1 error(s)"

  Scenario: search matches concept metadata as text and as JSON
    Given a knowledge base at "kb"
    And a file "kb/bundles/demo/index.md" containing:
      """
      ---
      okf_version: "0.2"
      title: Demo
      description: A demo bundle.
      ---

      # Demo

      ## Orientation

      * [Naming](/naming.md) - How names work.
      """
    And a file "kb/bundles/demo/naming.md" containing:
      """
      ---
      type: Design Note
      title: Naming
      description: How names work.
      ---

      # Naming

      How names work.
      """
    When I run "morphir kb search --kb kb --query naming"
    Then the command succeeds
    And stdout contains "/naming.md"
    And stdout contains "1 match(es)"
    When I run "morphir kb search --kb kb --query naming --json"
    Then the command succeeds
    And stdout is valid JSON
    And the JSON value at "/matches" is 1

  Scenario: index builds and query refuses anything that is not read-only
    Given a knowledge base at "kb"
    And a file "kb/bundles/demo/index.md" containing:
      """
      ---
      okf_version: "0.2"
      title: Demo
      description: A demo bundle.
      ---

      # Demo

      ## Orientation
      """
    When I run "morphir kb index --kb kb"
    Then the command succeeds
    And stdout contains "built"
    When I run the command:
      """
      morphir kb query --kb kb --sql "SELECT count(*) AS docs FROM doc"
      """
    Then the command succeeds
    And stdout contains "docs"
    And stdout contains "1 row(s)"
    When I run the command:
      """
      morphir kb query --kb kb --sql "DELETE FROM doc"
      """
    Then the command fails
    And stderr contains "error: refusing to run `delete`: kb query is read-only (SELECT, WITH, PRAGMA, EXPLAIN)"

  Scenario: refresh dry-run reports without writing
    Given a knowledge base at "kb"
    And a file "kb/bundles/demo/index.md" containing:
      """
      ---
      okf_version: "0.2"
      title: Demo
      description: A demo bundle.
      ---

      # Demo

      ## Orientation
      """
    When I run "morphir kb refresh --dry-run --kb kb"
    Then the command succeeds
    And stdout contains "would rebuild"
    And stdout contains "0 description(s) to fix"

  Scenario: intent lifecycle from init to the release guard
    Given a knowledge base at "kb"
    When I run "morphir kb intent init --kb kb"
    Then the command succeeds
    And stdout contains "created"
    And stdout contains "intent/index.md"
    When I run the command:
      """
      morphir kb intent new --kb kb --title "Ship the port" --description "Port the kb CLI." --kind feature
      """
    Then the command succeeds
    And stdout contains "created"
    When I run "morphir kb intent list --kb kb"
    Then the command succeeds
    And stdout contains "0001"
    And stdout contains "Ship the port"
    When I run "morphir kb intent start 0001 --kb kb"
    Then the command succeeds
    And stdout contains "intent 0001 → InProgress"
    When I run "morphir kb intent release 0001 --kb kb"
    Then the command fails
    And stderr contains "error: releasing needs --capability"

  Scenario: intent check reports and exits by severity
    Given a knowledge base at "kb"
    When I run "morphir kb intent init --kb kb"
    Then the command succeeds
    When I run "morphir kb intent check --kb kb"
    Then the command succeeds
    And stdout contains "0 error(s)"
    When I run "morphir kb intent check --kb kb --strict"
    Then the command fails
    And stdout contains "intent-no-system"

  Scenario: decision list on an empty knowledge base
    Given a knowledge base at "kb"
    When I run "morphir kb decision list --kb kb"
    Then the command succeeds
    And stdout is exactly "no decision records"

  Scenario: indexed search narrows by the same facets the scanning search does
    Given a knowledge base at "kb"
    And a file "kb/bundles/demo/index.md" containing:
      """
      ---
      okf_version: "0.2"
      title: Demo
      description: A demo bundle.
      ---

      # Demo

      ## Orientation

      * [Naming](/naming.md) - How names work.
      * [Naming Rules](/rules.md) - How naming rules work.
      """
    And a file "kb/bundles/demo/naming.md" containing:
      """
      ---
      type: Design Note
      title: Naming
      description: How names work.
      ---

      # Naming

      How names work.
      """
    And a file "kb/bundles/demo/rules.md" containing:
      """
      ---
      type: Reference
      title: Naming Rules
      description: How naming rules work.
      ---

      # Naming Rules

      How naming rules work.
      """
    When I run "morphir kb index --kb kb"
    Then the command succeeds
    When I run "morphir kb search --kb kb --index --query naming"
    Then the command succeeds
    And stdout contains "/naming.md"
    And stdout contains "/rules.md"
    And stdout contains "3 row(s)"
    When I run "morphir kb search --kb kb --index --query naming --type Reference"
    Then the command succeeds
    And stdout contains "/rules.md"
    And stdout does not contain "/naming.md"
    And stdout contains "1 row(s)"

  Scenario: sync diff with no argument diffs the whole mirror
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff --kb kb"
    Then the command succeeds
    And stdout contains "=== docs/types.md ==="
    And stdout contains "1 of 3 file(s) differ"

  Scenario: sync diff with one literal path keeps its single-file rendering
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff docs/index.md --kb kb"
    Then the command succeeds
    And stdout is exactly "docs/index.md: identical"
    When I run "morphir kb sync diff docs/types.md --kb kb"
    Then the command succeeds
    And stdout contains "+Local edit."
    And stdout does not contain "==="
    And stdout does not contain "file(s) differ"

  Scenario: sync diff takes several patterns at once
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff docs/types.md schemas/thing.yaml --kb kb"
    Then the command succeeds
    And stdout contains "=== docs/types.md ==="
    And stdout contains "1 of 2 file(s) differ"

  Scenario: sync diff takes a glob in the sync.yaml dialect
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff docs/** --kb kb"
    Then the command succeeds
    And stdout contains "=== docs/types.md ==="
    And stdout contains "1 of 2 file(s) differ"

  Scenario: sync diff --json emits a parseable envelope
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff --json --kb kb"
    Then the command succeeds
    And stdout is valid JSON
    And the JSON value at "/summary/differing" is 1
    And the JSON value at "/summary/compared" is 3

  Scenario: sync diff --raw emits the patch and nothing else
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff --raw --kb kb"
    Then the command succeeds
    And stdout contains "diff --git a/docs/types.md b/docs/types.md"
    And stdout does not contain "==="
    And stdout does not contain "file(s) differ"

  Scenario: sync diff refuses --json together with --raw
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff --json --raw --kb kb"
    Then the command fails
    And stderr contains "cannot be used with"

  Scenario: sync diff reads the remaining patterns from stdin when given -
    Given a mirror whose local copy of "docs/types.md" has been edited
    And stdin holds:
      """
      docs/types.md
      docs/index.md

      """
    When I run "morphir kb sync diff - --kb kb"
    Then the command succeeds
    And stdout contains "=== docs/types.md ==="
    And stdout contains "1 of 2 file(s) differ"

  Scenario: sync diff unions stdin with the patterns given literally
    Given a mirror whose local copy of "docs/types.md" has been edited
    And stdin holds:
      """
      docs/types.md
      """
    When I run "morphir kb sync diff schemas/thing.yaml - --kb kb"
    Then the command succeeds
    And stdout contains "=== docs/types.md ==="
    And stdout contains "1 of 2 file(s) differ"

  Scenario: sync diff -z splits what stdin holds on NUL
    Given a mirror whose local copy of "docs/types.md" has been edited
    And stdin holds NUL-delimited:
      """
      docs/types.md
      docs/index.md

      """
    When I run "morphir kb sync diff - -z --kb kb"
    Then the command succeeds
    And stdout contains "=== docs/types.md ==="
    And stdout contains "1 of 2 file(s) differ"

  Scenario: sync diff refuses -z when nothing is being read from stdin
    Given a mirror whose local copy of "docs/types.md" has been edited
    When I run "morphir kb sync diff -z --kb kb"
    Then the command fails
    And stderr contains "error: -z/--null says how to split what stdin holds"
