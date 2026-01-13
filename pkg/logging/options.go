package logging

import (
	"io"
	"os"
)

// config holds the internal configuration for Logger construction.
type config struct {
	level         string
	format        string
	filePath      string
	workspaceRoot string
	stderr        io.Writer
	noColor       bool
}

// defaultConfig returns the default configuration.
func defaultConfig() *config {
	return &config{
		level:   "info",
		format:  "text",
		stderr:  os.Stderr,
		noColor: false,
	}
}

// Option configures Logger construction.
type Option func(*config)

// WithLevel sets the log level.
// Valid levels: trace, debug, info, warn, error, fatal, disabled.
// Default is "info".
func WithLevel(level string) Option {
	return func(c *config) {
		c.level = level
	}
}

// WithFormat sets the output format.
// Valid formats: "text" (colored console output) or "json" (structured JSON).
// Default is "text".
func WithFormat(format string) Option {
	return func(c *config) {
		c.format = format
	}
}

// WithFile enables logging to a file in addition to stderr.
// If path is relative and workspaceRoot is provided, the file is created
// in {workspaceRoot}/.morphir/logs/{path}.
// If path is absolute, it is used as-is.
// If path is empty, file logging is disabled.
func WithFile(path, workspaceRoot string) Option {
	return func(c *config) {
		c.filePath = path
		c.workspaceRoot = workspaceRoot
	}
}

// WithStderr overrides the stderr writer.
// This is primarily useful for testing.
func WithStderr(w io.Writer) Option {
	return func(c *config) {
		c.stderr = w
	}
}

// WithNoColor disables colored output in text format.
// This is automatically detected in most cases but can be forced.
func WithNoColor() Option {
	return func(c *config) {
		c.noColor = true
	}
}
