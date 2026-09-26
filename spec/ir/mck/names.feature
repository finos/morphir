Feature: Names
  Canonical name strings and the legacy word arrays. The generated corpus at `docs/spec/ir/fixtures/naming-conformance.json` covers the full grammar; these cases pin the encodings the IR profiles use.

  @node:Name
  Scenario Outline: names-0001 Initialism as uppercase segment
    Decision 0001. A run of two or more single-letter legacy words decodes to one initialism.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling       |
      | YAML   | value-in-USD   |
      | JSON   | "value-in-USD" |

  @node:Name
  Scenario: names-0001 Initialism as uppercase segment
    Then a reader of JSON accepts ["value", "in", "u", "s", "d"]

  @node:Name
  Scenario Outline: names-0002 Single-letter type variable is a word
    Decision 0001, consequence 4. A run of one stays a word, so a type variable canonicalizes as `a`, never `(a)` or `A`.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling |
      | YAML   | a        |
      | JSON   | "a"      |

  @node:Name
  Scenario: names-0002 Single-letter type variable is a word
    Then a reader of JSON accepts ["a"]

  @node:Name
  Scenario Outline: names-0003 Retired parenthesized encoding is rejected
    Decision 0001 retired `value-in-(usd)`. GitHub #793 owns the books fixture that still carries it. A mixed-case segment such as Usd is also invalid: a segment is all lowercase or all uppercase, never mixed.

    Then a reader of <format> rejects <input> with <diagnostic>

    Examples:
      | format | input            | diagnostic   |
      | JSON   | "value-in-(usd)" | invalid_name |
      | JSON   | "value-in-Usd"   | invalid_name |

  @node:Path
  Scenario Outline: names-0004 Path string and legacy array
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling      |
      | YAML   | morphir/SDK   |
      | JSON   | "morphir/SDK" |

  @node:Path
  Scenario: names-0004 Path string and legacy array
    Then a reader of JSON accepts [["morphir"], ["s", "d", "k"]]

  @node:FQName
  Scenario Outline: names-0005 FQName string and legacy array
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling               |
      | YAML   | morphir/SDK:list#map   |
      | JSON   | "morphir/SDK:list#map" |

  @node:FQName
  Scenario: names-0005 FQName string and legacy array
    Then a reader of JSON accepts [[["morphir"], ["s", "d", "k"]], [["list"]], ["map"]]

  @node:Path
  Scenario Outline: names-0006 The SDK package name
    Decision 0011: the SDK's canonical package name is `morphir/SDK`, because morphir-elm's `Path.fromString` splits `SDK` into single-letter words that decision 0001 decodes as one initialism. `morphir/sdk` is a different, valid name and is not rejected; distributions-0005 pins the dependency key.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling      |
      | YAML   | morphir/SDK   |
      | JSON   | "morphir/SDK" |

  @node:Path
  Scenario: names-0006 The SDK package name
    Then a reader of JSON accepts [["morphir"], ["s", "d", "k"]]

  @node:Name
  Scenario Outline: names-0007 Legacy array items may be digits
    Decision 0012: both schemas use the core legacy word grammar `^[a-z0-9]+$`, so a digits-only word is legal. `["f", "r", "2052", "a"]` decodes as the naming corpus records: the letter run `f r` is one initialism, `2052` breaks the run, and the trailing `a` is a run of one, so a word.

    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling |
      | YAML   | item-2   |
      | JSON   | "item-2" |

  @node:Name
  Scenario: names-0007 Legacy array items may be digits
    Then a reader of JSON accepts ["item", "2"]

  @node:Name
  Scenario Outline: names-0008 A digit word breaks an initialism run
    Then its canonical <format> spelling is <spelling>

    Examples:
      | format | spelling    |
      | YAML   | FR-2052-a   |
      | JSON   | "FR-2052-a" |

  @node:Name
  Scenario: names-0008 A digit word breaks an initialism run
    Then a reader of JSON accepts ["f", "r", "2052", "a"]
