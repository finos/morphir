// Package logging provides structured logging for Morphir CLI and tooling.
//
// This package wraps zerolog to provide a consistent logging interface across
// all Morphir components. It supports:
//
//   - Multiple log levels (trace, debug, info, warn, error, fatal)
//   - Text format (colored console output) and JSON format
//   - Multi-writer support (stderr + file simultaneously)
//   - Workspace-aware file logging (relative paths resolve to .morphir/logs/)
//   - Functional options pattern for configuration
//
// # Basic Usage
//
//	logger, err := logging.New(
//	    logging.WithLevel("info"),
//	    logging.WithFormat("text"),
//	)
//	if err != nil {
//	    // handle error
//	}
//
//	logger.Info().Str("path", "/some/path").Msg("processing file")
//	logger.Debug().Int("count", 42).Msg("items processed")
//
// # File Logging
//
// To enable file logging in addition to stderr:
//
//	logger, err := logging.New(
//	    logging.WithLevel("debug"),
//	    logging.WithFile("morphir.log", "/path/to/workspace"),
//	)
//
// When a relative path is provided and workspaceRoot is set, the log file
// is created in the workspace's .morphir/logs/ directory.
//
// # JSON Format
//
// For log aggregation systems, use JSON format:
//
//	logger, err := logging.New(
//	    logging.WithFormat("json"),
//	)
//
// # No-op Logger
//
// For testing or when logging should be disabled:
//
//	logger := logging.Noop()
package logging
