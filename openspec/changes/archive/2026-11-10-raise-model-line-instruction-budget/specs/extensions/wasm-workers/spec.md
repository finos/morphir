## MODIFIED Requirements

### Requirement: Per-call budget
Each guest call SHALL have a deadline of 30 seconds for `extism-kernel-v1` and 10 seconds for `morphir-bytes-v1`,
inside the session deadline. Where the engine meters instructions, the host SHALL also apply a budget per call of
5,000,000,000 on the model line and 1,000,000,000 on MEP `0.1` and for a probe (bead: morphir-ukvn.5.64.36.26). A
budget SHALL be from 1 to 9,007,199,254,740,991 (2^53 - 1). The worker mode SHALL refuse an `--instructions` value
outside this range, or one that is not decimal digits, with a usage error that names the range (bead:
morphir-ukvn.5.64.36.33). The report SHALL state which bounds the host enforced.

#### Scenario: Runaway guest
- **WHEN** a guest loops forever inside `handle`
- **THEN** the call is stopped at its deadline, the outcome is deadline and the worker is gone

#### Scenario: Budget exhausted
- **WHEN** a guest runs more instructions than its per-call budget on an engine that meters
- **THEN** the call stops, the session fails with `extension.budget_exhausted` and the exit status is 1, not 124

#### Scenario: Budget above 2^31
- **WHEN** the native CLI runs a runaway guest of each ABI on the model line with a call budget of 2,147,483,648, a
  worker runs with `--instructions 3000000000`, and the host builds the call bounds of the model line
- **THEN** each runaway call ends with `extension.budget_exhausted` and the report gives the model-line budget
  5,000,000,000, the worker reads 3,000,000,000 and serves its calls, and the engine gets a budget of exactly
  5,000,000,000 on native and js

#### Scenario: Budget range
- **WHEN** the host makes limits with budgets of 1, 2147483648, 5000000000 and 9007199254740991, and with 0, -1 and
  9007199254740992, on native and js, and the worker mode gets `--instructions 9007199254740992`, `-1` or `0x10`
- **THEN** the first four are accepted, the next three are refused with an invalid limit, and the worker mode refuses
  each option with a usage error that names the range 1 to 9007199254740991

#### Scenario: Value-dense model within the budget
- **WHEN** the native CLI runs `generateModel` of the MoonBit portable guest on the model line with a plain IR file of
  800 public literal values in one module
- **THEN** the call completes within the budget, because the guest's cost grows linearly with the number of values
  (bead: morphir-ukvn.5.64.36.29)

#### Scenario: Host without metering
- **WHEN** the guest runs on a host whose engine has no instruction metering
- **THEN** the report lists the deadline and memory ceiling as enforced and the instruction budget as not enforced
