package logging

import (
	"io"
	stdlog "log"

	"github.com/rs/zerolog"
)

// Logger wraps zerolog.Logger with Morphir-specific configuration.
// It provides structured logging with support for multiple outputs,
// configurable levels, and both text and JSON formats.
//
// Logger is immutable and safe for concurrent use.
type Logger struct {
	zl zerolog.Logger
}

// New creates a Logger with the given options.
// Default configuration:
//   - Level: info
//   - Format: text (colored console)
//   - Output: stderr only
//
// Returns an error if the configuration is invalid (e.g., unknown level).
func New(opts ...Option) (Logger, error) {
	cfg := defaultConfig()
	for _, opt := range opts {
		opt(cfg)
	}

	// Parse and validate level
	level, err := ParseLevel(cfg.level)
	if err != nil {
		return Logger{}, err
	}

	// Build the writer
	writer, err := buildWriter(cfg)
	if err != nil {
		return Logger{}, err
	}

	// Create zerolog logger
	zl := zerolog.New(writer).
		Level(level).
		With().
		Timestamp().
		Logger()

	return Logger{zl: zl}, nil
}

// Noop returns a disabled logger that discards all output.
// Useful for testing or when logging should be completely disabled.
func Noop() Logger {
	return Logger{zl: zerolog.Nop()}
}

// Trace logs at trace level (most verbose).
func (l Logger) Trace() *zerolog.Event {
	return l.zl.Trace()
}

// Debug logs at debug level.
func (l Logger) Debug() *zerolog.Event {
	return l.zl.Debug()
}

// Info logs at info level.
func (l Logger) Info() *zerolog.Event {
	return l.zl.Info()
}

// Warn logs at warn level.
func (l Logger) Warn() *zerolog.Event {
	return l.zl.Warn()
}

// Error logs at error level.
func (l Logger) Error() *zerolog.Event {
	return l.zl.Error()
}

// Fatal logs at fatal level then calls os.Exit(1).
func (l Logger) Fatal() *zerolog.Event {
	return l.zl.Fatal()
}

// Panic logs at panic level then panics.
func (l Logger) Panic() *zerolog.Event {
	return l.zl.Panic()
}

// With returns a Context for building a child logger with additional fields.
// The original logger is not modified.
//
// Example:
//
//	childLogger := logger.With().Str("component", "validator").Logger()
func (l Logger) With() zerolog.Context {
	return l.zl.With()
}

// WithLevel returns a new Logger with the specified level.
// The original logger is not modified.
func (l Logger) WithLevel(level zerolog.Level) Logger {
	return Logger{zl: l.zl.Level(level)}
}

// Zerolog returns the underlying zerolog.Logger.
// This allows access to advanced zerolog features not exposed by Logger.
func (l Logger) Zerolog() zerolog.Logger {
	return l.zl
}

// Level returns the current log level.
func (l Logger) Level() zerolog.Level {
	return l.zl.GetLevel()
}

// SetAsGlobal sets this logger as the global zerolog default.
// After calling this, zerolog.Log will use this logger's configuration.
func (l Logger) SetAsGlobal() {
	zerolog.SetGlobalLevel(l.zl.GetLevel())
}

// SetAsStdLogger configures the standard library logger to write to this logger.
// After calling this, log.Print/Printf/Println will write to this logger at info level.
func (l Logger) SetAsStdLogger() {
	stdlog.SetFlags(0)
	stdlog.SetOutput(l.zl)
}

// Output returns a writer that writes to the logger at the specified level.
// This is useful for redirecting output from other libraries.
func (l Logger) Output(level zerolog.Level) io.Writer {
	return l.zl.With().Logger().Level(level)
}
