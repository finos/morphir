Feature: The kit's steps link across the finos/morphir and morphir-rust workspaces
  Scenario: A step defined in this crate's own test binary runs
    Given the kit crate's steps are linked
    Then the kit flag is set

  Scenario: A step from morphir-bdd's own base library runs
    Given a temporary directory
