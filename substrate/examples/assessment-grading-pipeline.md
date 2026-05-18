# Assessment Grading [Pipeline](../substrate/language/dataflow/pipeline.md)

Routes candidate names and test scores through two transformation steps:
the first step assigns a pass/fail status and assembles the full name;
the second step formats a one-line summary message.

## Input

- `first name`: [text][str-t]
- `last name`: [text][str-t]
- `score`: [number][num-t]

## Steps

1. [Select][select]
   - `full name` : [text][str-t]
     - [concat][cat]
       - [first name][var]
       - [last name][var]
   - `status` : [text][str-t]
     - [if][if] [score][var] [>][gt] [59][num]
       - [then][then] ["pass"][str]
     - [else][else] ["fail"][str]

2. [Select][select]
   - `summary` : [text][str-t]
     - [concat][cat]
       - [concat][cat]
         - [full name][var]
         - [": "][str]
       - [status][var]

## Output

- `summary`: [text][str-t]

## [Test cases][tc]

### Pass, fail, and boundary score

#### Inputs

| `first name` | `last name` | `score` |
| ------------ | ----------- | ------- |
| `"Alice"`    | `"Smith"`   | 85      |
| `"Bob"`      | `"Jones"`   | 45      |
| `"Carol"`    | `"White"`   | 60      |

#### Expected outputs

| `summary`              |
| ---------------------- |
| `"AliceSmith: pass"`   |
| `"BobJones: fail"`     |
| `"CarolWhite: pass"`   |

### Single row

#### Inputs

| `first name` | `last name` | `score` |
| ------------ | ----------- | ------- |
| `"David"`    | `"Lee"`     | 0       |

#### Expected outputs

| `summary`           |
| ------------------- |
| `"DavidLee: fail"`  |

[cat]: ../substrate/language/expressions/string.md#concatenate-operation
[else]: ../substrate/language/expressions/decision-tree.md#else
[gt]: ../substrate/language/expressions/ordering.md#greater-than-operation
[if]: ../substrate/language/expressions/decision-tree.md#if
[num]: ../substrate/language/expressions/number.md#literals
[num-t]: ../substrate/language/expressions/number.md
[select]: ../substrate/language/dataflow/select.md
[str]: ../substrate/language/expressions/string.md#literals
[str-t]: ../substrate/language/expressions/string.md
[tc]: ../substrate/language/concepts/test-case.md
[then]: ../substrate/language/expressions/decision-tree.md#then
[var]: ../substrate/language/expressions/README.md#variables
