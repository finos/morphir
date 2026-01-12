@toolchain @morphir-elm @integration
Feature: Morphir-Elm Toolchain Integration
  The morphir toolchain integrates with morphir-elm via npx to compile
  Elm source code to Morphir IR.

  Background:
    Given npx is available
    And the morphir-elm-compat example project exists

  Rule: Compiling Elm sources to Morphir IR

    @slow
    Scenario: Successfully compile Elm project to Morphir IR
      Given I am in the morphir-elm-compat example directory
      And no morphir-ir.json file exists
      When I run npx morphir-elm make
      Then the command should succeed
      And a file should exist at "morphir-ir.json"
      And the morphir-ir.json should be valid JSON

    @slow
    Scenario: Generated IR has correct format version
      Given I am in the morphir-elm-compat example directory
      When I run npx morphir-elm make
      Then the command should succeed
      And the morphir-ir.json should have format version 3

    @slow
    Scenario: Generated IR contains expected modules
      Given I am in the morphir-elm-compat example directory
      When I run npx morphir-elm make
      Then the command should succeed
      And the morphir-ir.json should contain module "main"
      And the morphir-ir.json should contain module "api"

    @slow
    Scenario: Generated IR has correct package name
      Given I am in the morphir-elm-compat example directory
      When I run npx morphir-elm make
      Then the command should succeed
      And the morphir-ir.json should have package name "elm.compat"

  Rule: Validating IR structure

    @slow
    Scenario: Main module contains expected types
      Given I am in the morphir-elm-compat example directory
      When I run npx morphir-elm make
      Then the command should succeed
      And the module "main" should have 5 types
      And the module "main" should have 4 values

    @slow
    Scenario: Api module contains expected types
      Given I am in the morphir-elm-compat example directory
      When I run npx morphir-elm make
      Then the command should succeed
      And the module "api" should have 3 types
      And the module "api" should have 3 values

  Rule: Error handling

    Scenario: Missing elm.json produces helpful error
      Given I am in a temporary directory
      And a morphir.json with name "Test" and exposed modules "Main"
      And a file "src/Main.elm" with content:
        """
        module Main exposing (hello)
        hello = "world"
        """
      When I run npx morphir-elm make
      Then the command should fail
      And the output should contain "elm.json"

  Rule: Incremental compilation

    @slow
    Scenario: Re-running make uses cached results
      Given I am in the morphir-elm-compat example directory
      When I run npx morphir-elm make
      Then the command should succeed
      And a file should exist at "morphir-hashes.json"
      When I run npx morphir-elm make
      Then the command should succeed
      And the output should contain "Building incrementally"
