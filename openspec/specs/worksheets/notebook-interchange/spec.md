# worksheets/notebook-interchange Specification

## Purpose

Lets people share Scheme worksheets as Jupyter (`.ipynb`) and .NET Interactive (`.dib`) notebooks, and bring
notebooks back as worksheets, from the CLI and the Workbench.

## Requirements

### Requirement: Export a worksheet as a notebook

`morphir notebook export <worksheet>` SHALL write a notebook with one Scheme code cell per top-level worksheet form,
in source order. The format SHALL come from `--format ipynb|dib` or the output file extension; Jupyter SHALL be the
default.

#### Scenario: Three forms

- **WHEN** `worksheet.scm` holds three top-level forms and `morphir notebook export worksheet.scm -o sheet.ipynb` runs
- **THEN** `sheet.ipynb` is a valid nbformat 4 notebook with three code cells whose language is Scheme

#### Scenario: DIB output

- **WHEN** `morphir notebook export worksheet.scm -o sheet.dib` runs
- **THEN** `sheet.dib` holds one Scheme cell per top-level form

### Requirement: Comment blocks become Markdown cells

A run of whole-line `;;` comments between forms SHALL become a Markdown cell with the comment markers removed, and a
Markdown cell SHALL become such a comment block on import.

#### Scenario: Leading comment

- **WHEN** a worksheet starts with `;; # Totals` followed by a form
- **THEN** the exported notebook starts with a Markdown cell `# Totals` followed by a code cell

### Requirement: Evaluation results as outputs

With `--evaluate`, Jupyter export SHALL evaluate the worksheet and attach each observation to the cell of its form as an
output with a `text/plain` preview and a Morphir JSON result. A failed observation SHALL become an error output.
DIB export SHALL preserve source only. `--evaluate` with DIB SHALL fail with a usage error and exit code 2 before
evaluating the worksheet or writing a file. The error SHALL explain that saved outputs require Jupyter.

#### Scenario: Evaluated export

- **WHEN** `morphir notebook export worksheet.scm --evaluate -o sheet.ipynb` runs and the second form fails
- **THEN** the first cell has an execute result with the preview, and the second cell has an error output

#### Scenario: DIB evaluation is refused

- **WHEN** `morphir notebook export worksheet.scm --evaluate -o sheet.dib` runs
- **THEN** the run fails with exit code 2, explains that saved outputs require Jupyter, does not evaluate the worksheet,
  and does not create `sheet.dib`

### Requirement: Import a notebook as a worksheet

`morphir notebook import <notebook>` SHALL write a Scheme worksheet from the notebook's Scheme code cells and
Markdown cells, in cell order. Cells in other languages and raw cells SHALL be skipped with a warning that names
each cell. Outputs SHALL NOT be imported.

#### Scenario: Mixed-language notebook

- **WHEN** a Jupyter notebook has a Scheme cell, a Python cell and a Markdown cell
- **THEN** the worksheet holds the Scheme form and the comment block, and the run warns that the Python cell was skipped

### Requirement: Round trip

Export followed by import SHALL give a worksheet with the same forms and comment blocks in the same order, so that
evaluating it gives the same observations as the original.

#### Scenario: Worksheet round trip

- **WHEN** a worksheet is exported to `.ipynb` and the notebook is imported again
- **THEN** evaluating the imported worksheet gives the same observation expressions, previews and outcomes as the original

### Requirement: Invalid notebooks

Import SHALL refuse a file that is not a valid Jupyter or DIB notebook with an error that names the file and the
first problem, and SHALL NOT write a worksheet.

#### Scenario: Truncated notebook

- **WHEN** `morphir notebook import broken.ipynb -o out.scm` runs and `broken.ipynb` is not valid JSON
- **THEN** the run fails with exit code 2 and `out.scm` is not created

### Requirement: JSON results

`notebook export` and `notebook import` SHALL support `--json`, and SHALL report the output path, the format, the
cell count and the skipped cells in the `morphir/command-result` envelope.

#### Scenario: JSON export result

- **WHEN** `morphir notebook export worksheet.scm -o sheet.ipynb --json` succeeds
- **THEN** standard output holds one `morphir/command-result` document with `state` `succeeded` and a result that
  names `sheet.ipynb`, the format `ipynb` and the cell count

### Requirement: Workbench notebooks

The Workbench SHALL export the open worksheet with its latest results as a Jupyter notebook, and SHALL export a
source-only DIB notebook. The DIB export action SHALL make clear that it saves source only. The Workbench SHALL open
a Jupyter or DIB notebook as a worksheet, with the same cell mapping as the CLI.

#### Scenario: Export from the Workbench

- **WHEN** a user evaluates a worksheet in the Workbench and chooses export as Jupyter
- **THEN** the downloaded notebook has the same cells and outputs as `morphir notebook export --evaluate` gives for that worksheet

#### Scenario: Source-only DIB export from the Workbench

- **WHEN** a user evaluates a worksheet in the Workbench and chooses the source-only DIB export action
- **THEN** the downloaded notebook has the same cells as `morphir notebook export -o sheet.dib` gives for that worksheet,
  without persisted execution outputs
