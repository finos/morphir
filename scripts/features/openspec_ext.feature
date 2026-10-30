Feature: Shared OpenSpec snapshot checks
  Scenario Outline: Check an installed snapshot
    Given a snapshot with "<condition>"
    When the snapshot checker runs
    Then the snapshot is "<result>"

    Examples:
      | condition           | result   |
      | valid files         | accepted |
      | edited template     | rejected |
      | malformed config    | rejected |
      | wrong schema        | rejected |
      | malformed lock      | rejected |

  Scenario: Setup preferences are independent of personal defaults
    Given personal preferences use commands and a custom profile
    When setup preferences are prepared
    Then setup selects core skills and preserves personal preferences
