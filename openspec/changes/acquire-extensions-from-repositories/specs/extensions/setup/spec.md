# Spec Delta

## Purpose

Gives users one guided command that installs the extensions they need ahead of time, with a short default path and a
capability view for customization.

## ADDED Requirements

### Requirement: Recommended set first
`morphir setup` SHALL first show the recommended extensions of the enabled repositories, plus the providers
the current workspace's configuration needs, and SHALL offer: install the recommended set (the default), customize,
or install nothing.

#### Scenario: Accept the default
- **WHEN** the user runs `morphir setup` and presses Enter
- **THEN** the recommended set is installed after the review step

#### Scenario: Workspace needs more
- **WHEN** the workspace configuration needs a Python frontend that is not in the recommended set
- **THEN** the first screen includes it and says that the workspace needs it

### Requirement: Customize by capability
Choosing customize SHALL show the available extensions grouped by role and then by language or target, with the
recommended set selected. Where more than one extension provides the same role and language, the user SHALL choose
one, and the recommended provider SHALL be preselected.

#### Scenario: Choose an Elm provider
- **WHEN** two extensions provide the Elm frontend
- **THEN** the Elm row lets the user pick one of them

### Requirement: Review before install
Every setup run SHALL end with one review screen that lists what will be installed, with repository, version and
publisher when recorded, and asks for one confirmation before any download.

#### Scenario: Several repositories in the selection
- **WHEN** the selection includes extensions from `finos` and `acme`
- **THEN** the review screen lists each with its repository and version, and nothing downloads until the user confirms

### Requirement: Unattended setup
`morphir setup` SHALL accept options that select the recommended set and add or remove named extensions, so that it
runs without any screen. It SHALL exit with a failure if any selected extension cannot be installed, and report each one.

#### Scenario: CI
- **WHEN** CI runs `morphir setup --defaults`
- **THEN** the recommended `finos` set is installed with no prompt

### Requirement: Safe to rerun
Running `morphir setup` again SHALL install only what is missing and SHALL report what was already installed.

#### Scenario: Second run
- **WHEN** the user runs `morphir setup --defaults` twice
- **THEN** the second run installs nothing and says that everything is installed
