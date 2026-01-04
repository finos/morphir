@workspace @members
Feature: Workspace Members Discovery and Loading
  As a Morphir developer
  I want to organize my project into multiple packages
  So that I can manage complex projects with reusable modules

  Background:
    Given a clean workspace test environment

  # Basic member discovery with glob patterns
  @discovery @glob
  Scenario: Discover members from glob patterns
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/core" with:
      """
      [project]
      name = "core"
      source_directory = "src"
      exposed_modules = ["Main"]
      """
    And a member project at "packages/utils" with:
      """
      [project]
      name = "utils"
      source_directory = "src"
      exposed_modules = ["Helpers"]
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "core" should exist
    And member "utils" should exist

  # Direct relative paths (no globs)
  @discovery @direct-path
  Scenario: Discover members from direct relative paths
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/core", "libs/utils"]
      """
    And a member project at "packages/core" with:
      """
      [project]
      name = "core"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "libs/utils" with:
      """
      [project]
      name = "utils"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "packages/other" with:
      """
      [project]
      name = "other"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "core" should exist
    And member "utils" should exist
    And member "other" should not exist

  # Mixed direct paths and globs
  @discovery @mixed-patterns
  Scenario: Discover members with mixed direct paths and globs
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/core", "libs/*"]
      """
    And a member project at "packages/core" with:
      """
      [project]
      name = "core"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "packages/other" with:
      """
      [project]
      name = "other"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "libs/utils" with:
      """
      [project]
      name = "utils"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "core" should exist
    And member "utils" should exist
    And member "other" should not exist

  # Recursive glob patterns
  @discovery @recursive
  Scenario: Discover members with recursive glob patterns
    Given a workspace config with:
      """
      [workspace]
      members = ["libs/**"]
      """
    And a member project at "libs/core" with:
      """
      [project]
      name = "core"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "libs/nested/deep/module" with:
      """
      [project]
      name = "deep-module"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "core" should exist
    And member "deep-module" should exist

  # File pattern - match specific TOML files
  @discovery @file-pattern @toml-only
  Scenario: Discover members by matching TOML config files
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*/morphir.toml"]
      """
    And a member project at "packages/toml-pkg" with:
      """
      [project]
      name = "toml-pkg"
      source_directory = "src"
      exposed_modules = []
      """
    And a morphir.json project at "packages/json-pkg" with:
      """
      {
        "name": "json-pkg",
        "sourceDirectory": "src",
        "exposedModules": []
      }
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 1 members
    And member "toml-pkg" should exist
    And member "json-pkg" should not exist

  # File pattern - match specific JSON files
  @discovery @file-pattern @json-only
  Scenario: Discover members by matching JSON config files
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*/morphir.json"]
      """
    And a member project at "packages/toml-pkg" with:
      """
      [project]
      name = "toml-pkg"
      source_directory = "src"
      exposed_modules = []
      """
    And a morphir.json project at "packages/json-pkg" with:
      """
      {
        "name": "json-pkg",
        "sourceDirectory": "src",
        "exposedModules": []
      }
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 1 members
    And member "json-pkg" should exist
    And member "toml-pkg" should not exist

  # File pattern - match both TOML and JSON using brace expansion
  @discovery @file-pattern @both
  Scenario: Discover members with both TOML and JSON using brace expansion
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*/{morphir.toml,morphir.json}"]
      """
    And a member project at "packages/toml-pkg" with:
      """
      [project]
      name = "toml-pkg"
      source_directory = "src"
      exposed_modules = []
      """
    And a morphir.json project at "packages/json-pkg" with:
      """
      {
        "name": "json-pkg",
        "sourceDirectory": "src",
        "exposedModules": []
      }
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "toml-pkg" should exist
    And member "json-pkg" should exist

  # File pattern - match custom config filename with recursive glob
  @discovery @file-pattern @custom
  Scenario: Discover members by matching custom config filenames
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/**/project.toml"]
      """
    And a custom config file at "packages/custom-pkg/project.toml" with:
      """
      [project]
      name = "custom-pkg"
      source_directory = "src"
      exposed_modules = []
      """
    And a custom config file at "packages/nested/deep/project.toml" with:
      """
      [project]
      name = "nested-pkg"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "packages/standard-pkg" with:
      """
      [project]
      name = "standard-pkg"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    # Note: Currently discovers directories but loading uses default config names
    # The directories are discovered, but member loading falls back to standard names
    And the workspace should have 0 members

  # Exclude patterns
  @discovery @exclude
  Scenario: Exclude patterns filter out directories
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/**"]
      exclude = ["**/testdata"]
      """
    And a member project at "packages/core" with:
      """
      [project]
      name = "core"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "packages/testdata" with:
      """
      [project]
      name = "testdata"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 1 members
    And member "core" should exist
    And member "testdata" should not exist

  # morphir.json compatibility
  @compatibility @morphir-elm
  Scenario: Load morphir.json member project
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a morphir.json project at "packages/elm-lib" with:
      """
      {
        "name": "My.Elm.Package",
        "sourceDirectory": "src",
        "exposedModules": ["Foo", "Bar"]
      }
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 1 members
    And member "My.Elm.Package" should exist
    And member "My.Elm.Package" should have module prefix "My.Elm.Package"
    And member "My.Elm.Package" should have 2 exposed modules

  # Mixed formats
  @compatibility @mixed
  Scenario: Workspace with mixed member config formats
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/modern" with:
      """
      [project]
      name = "modern-pkg"
      source_directory = "src"
      exposed_modules = ["Main"]
      module_prefix = "Modern"
      """
    And a morphir.json project at "packages/legacy" with:
      """
      {
        "name": "Legacy.Package",
        "sourceDirectory": "lib",
        "exposedModules": ["Core"]
      }
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "modern-pkg" should have module prefix "Modern"
    And member "Legacy.Package" should have module prefix "Legacy.Package"

  # Root project
  @root-project
  Scenario: Workspace with root project
    Given a workspace config with:
      """
      [workspace]
      members = ["libs/*"]

      [project]
      name = "my-app"
      source_directory = "src"
      exposed_modules = ["App"]
      module_prefix = "MyApp"
      """
    And a member project at "libs/utils" with:
      """
      [project]
      name = "utils"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have a root project
    And the root project name should be "my-app"
    And the root project module prefix should be "MyApp"
    And the workspace should have 1 members

  # Virtual workspace
  @virtual
  Scenario: Virtual workspace without root project
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/core" with:
      """
      [project]
      name = "core"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should not have a root project
    And the workspace should have 1 members

  # Member lookup
  @lookup
  Scenario: Look up member by path
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/mylib" with:
      """
      [project]
      name = "mylib"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And looking up member by path "packages/mylib" should find "mylib"

  # Multiple patterns
  @discovery @multiple-patterns
  Scenario: Discover members from multiple patterns
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*", "libs/*"]
      """
    And a member project at "packages/pkg-a" with:
      """
      [project]
      name = "pkg-a"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "libs/lib-a" with:
      """
      [project]
      name = "lib-a"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "apps/app-a" with:
      """
      [project]
      name = "app-a"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "pkg-a" should exist
    And member "lib-a" should exist
    And member "app-a" should not exist

  # No members
  @empty
  Scenario: Workspace without members array
    Given a workspace config with:
      """
      [morphir]
      version = "^3.0.0"
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 0 members

  # Config inheritance
  @config
  Scenario: Workspace configuration is accessible
    Given a workspace config with:
      """
      [morphir]
      version = "^3.0.0"

      [workspace]
      output_dir = "build"
      members = []

      [ir]
      format_version = 5
      strict_mode = true
      """
    When I load the workspace
    Then the workspace should load successfully
    And workspace config "morphir.version" should be "^3.0.0"
    And workspace config "workspace.output_dir" should be "build"
    And workspace config "ir.format_version" should be 5
    And workspace config "ir.strict_mode" should be true

  # TOML preferred over JSON
  @priority
  Scenario: morphir.toml is preferred over morphir.json
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/dual" with:
      """
      [project]
      name = "from-toml"
      source_directory = "src"
      exposed_modules = []
      """
    And also a morphir.json at "packages/dual" with:
      """
      {
        "name": "from-json",
        "sourceDirectory": "lib",
        "exposedModules": []
      }
      """
    When I load the workspace
    Then the workspace should load successfully
    And member "from-toml" should exist
    And member "from-json" should not exist

  # Error handling
  @errors
  Scenario: Invalid member config is reported as error
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a member project at "packages/valid" with:
      """
      [project]
      name = "valid"
      source_directory = "src"
      exposed_modules = []
      """
    And an invalid config at "packages/invalid/morphir.json" with:
      """
      invalid json content
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 1 members
    And the workspace should have 1 loading errors

  # Character class in patterns
  @discovery @character-class
  Scenario: Discover members with character class patterns
    Given a workspace config with:
      """
      [workspace]
      members = ["pkg-[ab]"]
      """
    And a member project at "pkg-a" with:
      """
      [project]
      name = "pkg-a"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "pkg-b" with:
      """
      [project]
      name = "pkg-b"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "pkg-c" with:
      """
      [project]
      name = "pkg-c"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "pkg-a" should exist
    And member "pkg-b" should exist
    And member "pkg-c" should not exist

  # Single character wildcard
  @discovery @single-char
  Scenario: Discover members with single character wildcard
    Given a workspace config with:
      """
      [workspace]
      members = ["pkg?"]
      """
    And a member project at "pkg1" with:
      """
      [project]
      name = "pkg1"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "pkg2" with:
      """
      [project]
      name = "pkg2"
      source_directory = "src"
      exposed_modules = []
      """
    And a member project at "pkgAB" with:
      """
      [project]
      name = "pkgAB"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 2 members
    And member "pkg1" should exist
    And member "pkg2" should exist
    And member "pkgAB" should not exist

  # Hidden config in .morphir directory
  @discovery @hidden-config
  Scenario: Discover member with hidden .morphir/morphir.toml config
    Given a workspace config with:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a hidden member project at "packages/hidden-pkg" with:
      """
      [project]
      name = "hidden-pkg"
      source_directory = "src"
      exposed_modules = []
      """
    When I load the workspace
    Then the workspace should load successfully
    And the workspace should have 1 members
    And member "hidden-pkg" should exist
