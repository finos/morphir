@wit @cli @jsonl
Feature: WIT CLI JSONL Output
  The morphir wit commands support JSONL output for batch processing
  and streaming workflows. This allows processing multiple WIT sources
  efficiently and enables pipeline-style processing.

  Background:
    Given the morphir CLI is available

  Rule: Single WIT source produces single JSONL line

    Scenario Outline: morphir wit make with --jsonl produces valid output
      When I run morphir wit make with source "<source>" and --jsonl
      Then the command should <result>
      And the JSONL output should have "success" equal to <success>
      And the JSONL output should have "valueCount" equal to <value_count>

      Examples: Valid WIT sources
        | source                                                           | result  | success | value_count |
        | package a:b; interface foo { x: func(); }                        | succeed | true    | 1           |
        | package test:math; interface math { add: func(a: u32) -> u32; }  | succeed | true    | 1           |
        | package ns:pkg; interface api { greet: func(name: string); }     | succeed | true    | 1           |

      Examples: Invalid WIT sources (command succeeds but JSONL shows failure)
        | source                          | result  | success | value_count |
        | this is not valid WIT           | succeed | false   | 0           |
        | package :invalid                | succeed | false   | 0           |

    Scenario Outline: morphir wit build with --jsonl produces valid output for valid sources
      When I run morphir wit build with source "<source>" and --jsonl
      Then the command should succeed
      And the JSONL output should have "success" equal to true
      And the JSONL output should have "roundTripValid" equal to <round_trip>

      Examples: Valid WIT sources with round-trip
        | source                                                    | round_trip |
        | package a:b; interface foo { x: func(); }                 | true       |
        | package test:api; interface api { hello: func(); }        | true       |

    Scenario: morphir wit build with --jsonl handles invalid input
      When I run morphir wit build with source "invalid wit content" and --jsonl
      Then the command should succeed
      And the JSONL output should have "success" equal to false

  Rule: JSONL output includes module structure

    Scenario Outline: Module content is included in JSONL output
      When I run morphir wit make with source "<source>" and --jsonl
      Then the command should succeed
      And the JSONL module should have sourcePackage namespace "<namespace>"
      And the JSONL module should have sourcePackage name "<package>"
      And the JSONL module should have <value_count> values

      Examples: Package identification preserved
        | source                                              | namespace | package | value_count |
        | package wasi:clocks; interface clock { now: func(); } | wasi      | clocks  | 1           |
        | package my-org:utils; interface util { help: func(); } | my-org    | utils   | 1           |
        | package test:simple; interface api { a: func(); b: func(); } | test | simple | 2          |

    Scenario Outline: Type definitions included in module output
      When I run morphir wit make with source "<source>" and --jsonl
      Then the command should succeed
      And the JSONL module should have <type_count> types

      Examples: Types are counted
        | source                                                              | type_count |
        | package a:b; interface foo { type my-alias = string; }              | 1          |
        | package a:b; interface foo { type a = u32; type b = string; }       | 2          |

  Rule: Batch JSONL input processes multiple sources

    Scenario: Multiple sources from JSONL input file
      Given a JSONL input file with the following entries:
        | name   | source                                            |
        | first  | package a:b; interface foo { x: func(); }         |
        | second | package c:d; interface bar { y: func(); }         |
        | third  | package e:f; interface baz { z: func(); }         |
      When I run morphir wit make with --jsonl-input and --jsonl
      Then the command should succeed
      And the output should contain 3 JSONL lines
      And JSONL line 1 should have "name" equal to "first"
      And JSONL line 2 should have "name" equal to "second"
      And JSONL line 3 should have "name" equal to "third"

    Scenario: Batch processing handles mixed success/failure
      Given a JSONL input file with the following entries:
        | name    | source                                     |
        | valid   | package a:b; interface foo { x: func(); }  |
        | invalid | not valid wit                              |
        | valid2  | package c:d; interface bar { y: func(); }  |
      When I run morphir wit make with --jsonl-input and --jsonl
      Then the command should fail
      And the output should contain 3 JSONL lines
      And JSONL line 1 should have "success" equal to true
      And JSONL line 2 should have "success" equal to false
      And JSONL line 3 should have "success" equal to true

    Scenario: JSONL input from stdin
      Given JSONL input via stdin:
        """
        {"name": "stdin-test", "source": "package a:b; interface foo { x: func(); }"}
        """
      When I run morphir wit make with --jsonl-input - and --jsonl
      Then the command should succeed
      And JSONL line 1 should have "name" equal to "stdin-test"
      And JSONL line 1 should have "success" equal to true

  Rule: Diagnostics are included in JSONL output

    Scenario Outline: Lossy type conversions emit warnings in JSONL
      When I run morphir wit make with source "<source>" and --jsonl
      Then the command should succeed
      And the JSONL output should have diagnostics with code "<diagnostic_code>"

      Examples: Integer types lose precision info
        | source                                                     | diagnostic_code |
        | package a:b; interface foo { get: func() -> u8; }          | WIT001          |
        | package a:b; interface foo { get: func() -> u16; }         | WIT001          |
        | package a:b; interface foo { get: func() -> u32; }         | WIT001          |
        | package a:b; interface foo { get: func() -> s8; }          | WIT001          |
        | package a:b; interface foo { get: func() -> s16; }         | WIT001          |
        | package a:b; interface foo { get: func() -> s32; }         | WIT001          |

    Scenario: Parse errors include diagnostic details
      When I run morphir wit make with source "invalid { wit" and --jsonl
      Then the command should succeed
      And the JSONL output should have "success" equal to false
      And the JSONL output should have diagnostics with severity "error"
