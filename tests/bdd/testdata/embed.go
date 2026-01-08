package testdata

import "embed"

// Fixtures embeds all JSON fixture files for portable test execution.
//
//go:embed **/*.json
var Fixtures embed.FS

// WITFixtures embeds all WIT fixture files for WIT bindings testing.
//
//go:embed wit/**/*.wit
var WITFixtures embed.FS
