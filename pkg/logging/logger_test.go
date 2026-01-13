package logging

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNew(t *testing.T) {
	t.Run("default configuration", func(t *testing.T) {
		var buf bytes.Buffer
		logger, err := New(WithStderr(&buf))
		require.NoError(t, err)

		logger.Info().Msg("test message")

		// Text format should contain the message
		assert.Contains(t, buf.String(), "test message")
	})

	t.Run("with debug level", func(t *testing.T) {
		var buf bytes.Buffer
		logger, err := New(
			WithLevel("debug"),
			WithStderr(&buf),
		)
		require.NoError(t, err)

		logger.Debug().Msg("debug message")
		assert.Contains(t, buf.String(), "debug message")
	})

	t.Run("with info level filters debug", func(t *testing.T) {
		var buf bytes.Buffer
		logger, err := New(
			WithLevel("info"),
			WithStderr(&buf),
		)
		require.NoError(t, err)

		logger.Debug().Msg("debug message")
		assert.NotContains(t, buf.String(), "debug message")
	})

	t.Run("invalid level returns error", func(t *testing.T) {
		_, err := New(WithLevel("invalid"))
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unknown log level")
	})

	t.Run("json format", func(t *testing.T) {
		var buf bytes.Buffer
		logger, err := New(
			WithFormat("json"),
			WithStderr(&buf),
		)
		require.NoError(t, err)

		logger.Info().Str("key", "value").Msg("json test")

		// Should be valid JSON
		var result map[string]any
		err = json.Unmarshal(buf.Bytes(), &result)
		require.NoError(t, err)
		assert.Equal(t, "json test", result["message"])
		assert.Equal(t, "value", result["key"])
		assert.Equal(t, "info", result["level"])
	})
}

func TestNoop(t *testing.T) {
	var buf bytes.Buffer
	logger := Noop()

	// Should not panic
	logger.Info().Msg("this should not appear")
	logger.Debug().Str("key", "value").Msg("also not appearing")

	// Buffer should be empty (noop doesn't write anywhere)
	assert.Empty(t, buf.String())
}

func TestLoggerMethods(t *testing.T) {
	var buf bytes.Buffer
	logger, err := New(
		WithLevel("trace"),
		WithFormat("json"),
		WithStderr(&buf),
	)
	require.NoError(t, err)

	tests := []struct {
		name  string
		fn    func()
		level string
	}{
		{"Trace", func() { logger.Trace().Msg("trace") }, "trace"},
		{"Debug", func() { logger.Debug().Msg("debug") }, "debug"},
		{"Info", func() { logger.Info().Msg("info") }, "info"},
		{"Warn", func() { logger.Warn().Msg("warn") }, "warn"},
		{"Error", func() { logger.Error().Msg("error") }, "error"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			buf.Reset()
			tt.fn()

			var result map[string]any
			err := json.Unmarshal(buf.Bytes(), &result)
			require.NoError(t, err)
			assert.Equal(t, tt.level, result["level"])
		})
	}
}

func TestLoggerWith(t *testing.T) {
	var buf bytes.Buffer
	logger, err := New(
		WithFormat("json"),
		WithStderr(&buf),
	)
	require.NoError(t, err)

	// Create child logger with additional context
	childLogger := Logger{zl: logger.With().Str("component", "test").Logger()}
	childLogger.Info().Msg("test message")

	var result map[string]any
	err = json.Unmarshal(buf.Bytes(), &result)
	require.NoError(t, err)
	assert.Equal(t, "test", result["component"])
	assert.Equal(t, "test message", result["message"])
}

func TestLoggerWithLevel(t *testing.T) {
	var buf bytes.Buffer
	logger, err := New(
		WithLevel("info"),
		WithFormat("json"),
		WithStderr(&buf),
	)
	require.NoError(t, err)

	// Original logger should filter debug
	logger.Debug().Msg("should not appear")
	assert.Empty(t, buf.String())

	// New logger with debug level
	debugLogger := logger.WithLevel(zerolog.DebugLevel)
	debugLogger.Debug().Msg("should appear")
	assert.Contains(t, buf.String(), "should appear")
}

func TestLoggerLevel(t *testing.T) {
	logger, err := New(WithLevel("warn"))
	require.NoError(t, err)
	assert.Equal(t, zerolog.WarnLevel, logger.Level())
}

func TestLoggerZerolog(t *testing.T) {
	logger, err := New()
	require.NoError(t, err)

	zl := logger.Zerolog()
	assert.NotNil(t, zl)
}

func TestParseLevel(t *testing.T) {
	tests := []struct {
		input    string
		expected zerolog.Level
		wantErr  bool
	}{
		{"trace", zerolog.TraceLevel, false},
		{"TRACE", zerolog.TraceLevel, false},
		{"debug", zerolog.DebugLevel, false},
		{"DEBUG", zerolog.DebugLevel, false},
		{"info", zerolog.InfoLevel, false},
		{"INFO", zerolog.InfoLevel, false},
		{"", zerolog.InfoLevel, false}, // empty defaults to info
		{"warn", zerolog.WarnLevel, false},
		{"warning", zerolog.WarnLevel, false},
		{"WARN", zerolog.WarnLevel, false},
		{"error", zerolog.ErrorLevel, false},
		{"ERROR", zerolog.ErrorLevel, false},
		{"fatal", zerolog.FatalLevel, false},
		{"panic", zerolog.PanicLevel, false},
		{"disabled", zerolog.Disabled, false},
		{"off", zerolog.Disabled, false},
		{"invalid", zerolog.InfoLevel, true},
		{"  debug  ", zerolog.DebugLevel, false}, // with whitespace
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			level, err := ParseLevel(tt.input)
			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, level)
			}
		})
	}
}

func TestLevelString(t *testing.T) {
	tests := []struct {
		level    zerolog.Level
		expected string
	}{
		{zerolog.TraceLevel, "trace"},
		{zerolog.DebugLevel, "debug"},
		{zerolog.InfoLevel, "info"},
		{zerolog.WarnLevel, "warn"},
		{zerolog.ErrorLevel, "error"},
		{zerolog.FatalLevel, "fatal"},
		{zerolog.PanicLevel, "panic"},
		{zerolog.Disabled, "disabled"},
		{zerolog.Level(99), "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			assert.Equal(t, tt.expected, LevelString(tt.level))
		})
	}
}

func TestValidLevels(t *testing.T) {
	levels := ValidLevels()
	assert.Contains(t, levels, "trace")
	assert.Contains(t, levels, "debug")
	assert.Contains(t, levels, "info")
	assert.Contains(t, levels, "warn")
	assert.Contains(t, levels, "error")
	assert.Contains(t, levels, "fatal")
	assert.Contains(t, levels, "disabled")
}

func TestResolveLogPath(t *testing.T) {
	tests := []struct {
		name          string
		path          string
		workspaceRoot string
		expected      string
	}{
		{
			name:          "absolute path unchanged",
			path:          "/var/log/morphir.log",
			workspaceRoot: "/home/user/project",
			expected:      "/var/log/morphir.log",
		},
		{
			name:          "relative with workspace",
			path:          "morphir.log",
			workspaceRoot: "/home/user/project",
			expected:      "/home/user/project/.morphir/logs/morphir.log",
		},
		{
			name:          "relative without workspace",
			path:          "morphir.log",
			workspaceRoot: "",
			expected:      "morphir.log",
		},
		{
			name:          "nested relative path",
			path:          "debug/verbose.log",
			workspaceRoot: "/workspace",
			expected:      "/workspace/.morphir/logs/debug/verbose.log",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := resolveLogPath(tt.path, tt.workspaceRoot)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestLogsDir(t *testing.T) {
	assert.Equal(t, "/workspace/.morphir/logs", LogsDir("/workspace"))
	assert.Equal(t, "/home/user/project/.morphir/logs", LogsDir("/home/user/project"))
}

func TestFileLogging(t *testing.T) {
	// Create a temp directory for testing
	tmpDir := t.TempDir()

	t.Run("creates log file and directory", func(t *testing.T) {
		var stderrBuf bytes.Buffer
		logger, err := New(
			WithLevel("info"),
			WithFormat("json"),
			WithStderr(&stderrBuf),
			WithFile("test.log", tmpDir),
		)
		require.NoError(t, err)

		logger.Info().Str("key", "value").Msg("file test")

		// Check file was created
		logPath := filepath.Join(tmpDir, ".morphir", "logs", "test.log")
		assert.FileExists(t, logPath)

		// Check file content
		content, err := os.ReadFile(logPath)
		require.NoError(t, err)
		assert.Contains(t, string(content), "file test")
		assert.Contains(t, string(content), `"key":"value"`)

		// Check stderr also got the message
		assert.Contains(t, stderrBuf.String(), "file test")
	})

	t.Run("appends to existing file", func(t *testing.T) {
		logPath := filepath.Join(tmpDir, ".morphir", "logs", "append.log")

		// Create first logger
		logger1, err := New(
			WithFormat("json"),
			WithFile("append.log", tmpDir),
			WithStderr(&bytes.Buffer{}),
		)
		require.NoError(t, err)
		logger1.Info().Msg("first message")

		// Create second logger
		logger2, err := New(
			WithFormat("json"),
			WithFile("append.log", tmpDir),
			WithStderr(&bytes.Buffer{}),
		)
		require.NoError(t, err)
		logger2.Info().Msg("second message")

		// Check both messages are in the file
		content, err := os.ReadFile(logPath)
		require.NoError(t, err)
		assert.Contains(t, string(content), "first message")
		assert.Contains(t, string(content), "second message")
	})
}

func TestTextFormat(t *testing.T) {
	var buf bytes.Buffer
	logger, err := New(
		WithFormat("text"),
		WithStderr(&buf),
		WithNoColor(),
	)
	require.NoError(t, err)

	logger.Info().Str("path", "/test").Msg("text format test")

	output := buf.String()
	// Text format should contain level and message
	assert.Contains(t, output, "INF")
	assert.Contains(t, output, "text format test")
	assert.Contains(t, output, "path=/test")
}

func TestNoColorOption(t *testing.T) {
	var buf bytes.Buffer
	logger, err := New(
		WithFormat("text"),
		WithNoColor(),
		WithStderr(&buf),
	)
	require.NoError(t, err)

	logger.Info().Msg("no color test")

	output := buf.String()
	// Should not contain ANSI escape codes
	assert.False(t, strings.Contains(output, "\x1b["))
}
