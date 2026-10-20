# Installed-client manual qualification

`manual-qualification-policy.json` is an explicit caller-selected example for
the ignored `installed_mck_cli` tests. It is never a production default. Set
`MORPHIR_MCK_INSTALLED_POLICY` to its absolute path and supply the absolute
package, Node, source checkout and native executable paths required by those
tests. The runner does not discover or substitute these SUT paths.

The example was selected for source revision
`01416289e7a90a8481dc751cb41340a7c3ba38cc` with 2,105 tracked source entries
and 48 installed package files. The measured cumulative comparison work was
1,447,375 bytes. Its explicit 2 MiB comparison allowance provides finite margin
for those inputs. The preceding 1,000,000-byte allowance correctly refused the
same work; that refusal does not justify skipping checks or resetting owners.
Other inputs can require different caller permissions.

For a fresh kit, copy the maintained
`crates/morphir-mck/src/workbench/model_originals/workflow/pipeline/installed_client_controls/cases24.json`
to `cases.json` in the kit directory. Use the same kit and checker policy for
`morphir mck workbench run` and `morphir mck workbench check`. The ignored tests
exercise the public commands, retain actual host/process/filesystem facts and
check that destination-byte tampering is refused by saved replay.

Successful binding still reports `expected-blocked`, `failed` at index zero
and `qualified: false`; the other 23 workflows remain unattempted. The original
151 cases and 175 roles remain required. Whole UI execution, final source and
upgraded socket-task joins, platform coverage, dynamic publication and scratch
cleanup ordering, and client release acceptance remain unqualified. Source and
package association hashes are observations, not build provenance or proof that
an executable cannot change between hashing and launch.
