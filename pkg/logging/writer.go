package logging

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/rs/zerolog"
)

// buildWriter creates the appropriate io.Writer based on configuration.
// It returns a writer that may combine multiple outputs (stderr and/or file).
func buildWriter(cfg *config) (io.Writer, error) {
	var writers []io.Writer

	// Build stderr writer based on format
	stderrWriter := buildStderrWriter(cfg)
	writers = append(writers, stderrWriter)

	// Add file writer if configured
	if cfg.filePath != "" {
		fileWriter, err := openLogFile(cfg.filePath, cfg.workspaceRoot)
		if err != nil {
			return nil, fmt.Errorf("failed to open log file: %w", err)
		}
		writers = append(writers, fileWriter)
	}

	// Return single writer or multi-writer
	if len(writers) == 1 {
		return writers[0], nil
	}
	return zerolog.MultiLevelWriter(writers...), nil
}

// buildStderrWriter creates the stderr writer based on format.
func buildStderrWriter(cfg *config) io.Writer {
	if cfg.format == "json" {
		// JSON format writes directly to stderr
		return cfg.stderr
	}

	// Text format uses console writer with colors
	return zerolog.ConsoleWriter{
		Out:        cfg.stderr,
		NoColor:    cfg.noColor,
		TimeFormat: "15:04:05",
	}
}

// openLogFile opens or creates the log file.
// If path is relative and workspaceRoot is set, the file is placed in .morphir/logs/.
// The file is opened in append mode to preserve existing logs.
func openLogFile(path, workspaceRoot string) (io.Writer, error) {
	fullPath := resolveLogPath(path, workspaceRoot)

	// Ensure the directory exists
	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create log directory %s: %w", dir, err)
	}

	// Open file in append mode, create if doesn't exist
	file, err := os.OpenFile(fullPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil, fmt.Errorf("failed to open log file %s: %w", fullPath, err)
	}

	return file, nil
}

// resolveLogPath determines the full path for a log file.
// Relative paths are resolved to {workspaceRoot}/.morphir/logs/{path}.
// Absolute paths are returned as-is.
func resolveLogPath(path, workspaceRoot string) string {
	if filepath.IsAbs(path) {
		return path
	}

	if workspaceRoot != "" {
		// Place relative paths in workspace's .morphir/logs/ directory
		return filepath.Join(workspaceRoot, ".morphir", "logs", path)
	}

	// No workspace root, use path relative to current directory
	return path
}

// LogsDir returns the logs directory for a workspace.
// This is {workspaceRoot}/.morphir/logs/
func LogsDir(workspaceRoot string) string {
	return filepath.Join(workspaceRoot, ".morphir", "logs")
}
