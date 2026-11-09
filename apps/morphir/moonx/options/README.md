# Moonx argument ownership

This pure package prepares arguments for the Node-backed Morphir Moonx entry.
It starts no host and imports no optional launcher runtime.

The launcher owns leading `--moonx-json`, `--moonx-help` and
`--moonx-forward` controls. `--moonx-forward` ends launcher parsing and sends
every subsequent argument literally to Morphir. Otherwise parsing stops at the
first application token. A leading `--json` selects launcher reporting too,
and remains in the array delivered to Morphir. Application `--help`, delimiters,
empty values and controls inside opaque child tails remain unchanged.

For example, `--moonx-json worksheet file.scm --json` requests launcher JSON
reporting and forwards `worksheet file.scm --json`. To forward a reserved
control literally, use `--moonx-forward --moonx-help`. The command-line library
declares flag ownership and rejects unknown leading controls. Returned arrays
are copies, so caller mutation cannot change a retained invocation.

The actual entry supplies output schemas and channels. Its delivery task stays
open until the published launcher, packaged assets and real host qualification
are complete.
