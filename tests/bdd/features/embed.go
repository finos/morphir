package features

import "embed"

// Features embeds all .feature files for portable test execution.
//
//go:embed */*.feature
var Features embed.FS
