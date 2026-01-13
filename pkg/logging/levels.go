package logging

import (
	"fmt"
	"strings"

	"github.com/rs/zerolog"
)

// ParseLevel converts a string level name to a zerolog.Level.
// It supports the following levels (case-insensitive):
//   - trace: Most verbose, for detailed debugging
//   - debug: Debugging information
//   - info: General operational information (default)
//   - warn/warning: Warning conditions
//   - error: Error conditions
//   - fatal: Fatal errors (will call os.Exit)
//   - panic: Panic conditions (will call panic)
//   - disabled/off: Disable all logging
//
// An empty string defaults to info level.
// Returns an error for unrecognized level names.
func ParseLevel(s string) (zerolog.Level, error) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "trace":
		return zerolog.TraceLevel, nil
	case "debug":
		return zerolog.DebugLevel, nil
	case "info", "":
		return zerolog.InfoLevel, nil
	case "warn", "warning":
		return zerolog.WarnLevel, nil
	case "error":
		return zerolog.ErrorLevel, nil
	case "fatal":
		return zerolog.FatalLevel, nil
	case "panic":
		return zerolog.PanicLevel, nil
	case "disabled", "off":
		return zerolog.Disabled, nil
	default:
		return zerolog.InfoLevel, fmt.Errorf("unknown log level: %q", s)
	}
}

// LevelString returns the string representation of a zerolog.Level.
func LevelString(level zerolog.Level) string {
	switch level {
	case zerolog.TraceLevel:
		return "trace"
	case zerolog.DebugLevel:
		return "debug"
	case zerolog.InfoLevel:
		return "info"
	case zerolog.WarnLevel:
		return "warn"
	case zerolog.ErrorLevel:
		return "error"
	case zerolog.FatalLevel:
		return "fatal"
	case zerolog.PanicLevel:
		return "panic"
	case zerolog.Disabled:
		return "disabled"
	default:
		return "unknown"
	}
}

// ValidLevels returns a slice of all valid level names.
func ValidLevels() []string {
	return []string{"trace", "debug", "info", "warn", "error", "fatal", "disabled"}
}
