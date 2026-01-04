package testdata

import "embed"

// Fixtures embeds all JSON fixture files for portable test execution.
//
//go:embed **/*.json
var Fixtures embed.FS
