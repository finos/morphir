package features

import "embed"

// Features embeds all .feature files for portable test execution.
// Supports nested directories for grouping (e.g., examples/workspace/*.feature).
//
//go:embed */*.feature */*/*.feature
var Features embed.FS
