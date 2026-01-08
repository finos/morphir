package toolchain

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// Executor executes toolchain tasks.
type Executor struct {
	registry  *Registry
	outputDir *OutputDirStructure
	ctx       pipeline.Context
}

// NewExecutor creates a new task executor.
func NewExecutor(registry *Registry, outputDir *OutputDirStructure, ctx pipeline.Context) *Executor {
	return &Executor{
		registry:  registry,
		outputDir: outputDir,
		ctx:       ctx,
	}
}

// ExecuteTask executes a task from a toolchain.
func (e *Executor) ExecuteTask(toolchainName, taskName string, variant string) (TaskResult, error) {
	// Get toolchain
	tc, ok := e.registry.GetToolchain(toolchainName)
	if !ok {
		return TaskResult{}, fmt.Errorf("toolchain not found: %s", toolchainName)
	}

	// Find task
	var taskDef *TaskDef
	for i := range tc.Tasks {
		if tc.Tasks[i].Name == taskName {
			taskDef = &tc.Tasks[i]
			break
		}
	}
	if taskDef == nil {
		return TaskResult{}, fmt.Errorf("task not found: %s in toolchain %s", taskName, toolchainName)
	}

	// Check variant support
	if variant != "" && len(taskDef.Variants) > 0 {
		found := false
		for _, v := range taskDef.Variants {
			if v == variant {
				found = true
				break
			}
		}
		if !found {
			return TaskResult{}, fmt.Errorf("variant %s not supported by task %s", variant, taskName)
		}
	}

	// Execute based on toolchain type
	if tc.Type == ToolchainTypeExternal {
		return e.executeExternalTask(tc, *taskDef, variant)
	}

	return TaskResult{}, fmt.Errorf("native toolchains not yet implemented")
}

// executeExternalTask executes an external process-based task.
func (e *Executor) executeExternalTask(tc Toolchain, task TaskDef, variant string) (TaskResult, error) {
	startTime := time.Now()

	// Create output directory
	taskOutputDir, err := e.outputDir.TaskOutputDir(tc.Name, task.Name)
	if err != nil {
		return TaskResult{}, fmt.Errorf("failed to create output directory path: %w", err)
	}

	writer, err := e.ctx.VFS.Writer()
	if err != nil {
		return TaskResult{}, fmt.Errorf("failed to get VFS writer: %w", err)
	}

	_, err = writer.CreateFolder(taskOutputDir, vfs.WriteOptions{MkdirParents: true, Overwrite: false})
	if err != nil {
		return TaskResult{}, fmt.Errorf("failed to create output directory: %w", err)
	}

	// Resolve executable
	executable, err := e.resolveExecutable(tc, task)
	if err != nil {
		return TaskResult{}, fmt.Errorf("failed to resolve executable: %w", err)
	}

	// Substitute arguments
	args, err := e.substituteArgs(tc, task, variant)
	if err != nil {
		return TaskResult{}, fmt.Errorf("failed to substitute arguments: %w", err)
	}

	// Prepare environment
	env := e.prepareEnv(tc, task)

	// Prepare working directory
	workingDir := e.prepareWorkingDir(tc, task)

	// Execute command
	ctx, cancel := context.WithTimeout(context.Background(), e.getTimeout(tc, task))
	defer cancel()

	cmd := exec.CommandContext(ctx, executable, args...)
	cmd.Dir = workingDir
	cmd.Env = env

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	execErr := cmd.Run()
	endTime := time.Now()

	exitCode := 0
	success := true
	if execErr != nil {
		if exitErr, ok := execErr.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
		}
		success = false
	}

	// Parse diagnostics from stderr
	diagnostics := e.parseDiagnostics(stderr.String())

	// Create metadata
	metadata := TaskMetadata{
		ToolchainName: tc.Name,
		TaskName:      task.Name,
		StartTime:     startTime,
		EndTime:       endTime,
		Duration:      endTime.Sub(startTime),
		ExitCode:      exitCode,
		Success:       success,
	}

	// Write meta.json
	if err := e.writeMetadata(tc.Name, task.Name, metadata); err != nil {
		// Log warning but don't fail the task
		fmt.Fprintf(os.Stderr, "Warning: failed to write metadata: %v\n", err)
	}

	// Write diagnostics.jsonl
	if err := e.writeDiagnostics(tc.Name, task.Name, diagnostics); err != nil {
		// Log warning but don't fail the task
		fmt.Fprintf(os.Stderr, "Warning: failed to write diagnostics: %v\n", err)
	}

	result := TaskResult{
		Metadata:    metadata,
		Outputs:     make(map[string]any),
		Diagnostics: diagnostics,
		Artifacts:   []pipeline.Artifact{},
	}

	if !success {
		result.Error = fmt.Errorf("task failed with exit code %d: %s", exitCode, stderr.String())
	}

	return result, nil
}

// resolveExecutable resolves the executable path based on acquisition config.
func (e *Executor) resolveExecutable(tc Toolchain, task TaskDef) (string, error) {
	// For now, only support "path" backend
	if tc.Acquire.Backend != "path" {
		return "", fmt.Errorf("acquisition backend %s not yet implemented", tc.Acquire.Backend)
	}

	// Use task.Exec if provided, otherwise use tc.Acquire.Executable
	executable := task.Exec
	if executable == "" {
		executable = tc.Acquire.Executable
	}

	if executable == "" {
		return "", fmt.Errorf("no executable specified for task %s", task.Name)
	}

	// Check if executable exists in PATH
	_, err := exec.LookPath(executable)
	if err != nil {
		return "", fmt.Errorf("executable %s not found in PATH: %w", executable, err)
	}

	return executable, nil
}

// substituteArgs substitutes variables in task arguments.
func (e *Executor) substituteArgs(tc Toolchain, task TaskDef, variant string) ([]string, error) {
	args := make([]string, len(task.Args))
	copy(args, task.Args)

	// Build substitution map
	subs := make(map[string]string)

	// Add variant substitution
	if variant != "" {
		subs["{variant}"] = variant
	}

	// Add output substitutions
	for outputName, outputSpec := range task.Outputs {
		outputPath, err := e.outputDir.OutputPath(tc.Name, task.Name, outputSpec.Path)
		if err != nil {
			return nil, fmt.Errorf("failed to create output path: %w", err)
		}
		subs[fmt.Sprintf("{outputs.%s}", outputName)] = outputPath.String()
	}

	// Perform substitutions
	for i := range args {
		for pattern, value := range subs {
			args[i] = strings.ReplaceAll(args[i], pattern, value)
		}
	}

	return args, nil
}

// prepareEnv prepares the environment variables for task execution.
func (e *Executor) prepareEnv(tc Toolchain, task TaskDef) []string {
	env := os.Environ()

	// Add toolchain env vars
	for k, v := range tc.Env {
		env = append(env, fmt.Sprintf("%s=%s", k, v))
	}

	// Add task-specific env vars (override toolchain vars)
	for k, v := range task.Env {
		env = append(env, fmt.Sprintf("%s=%s", k, v))
	}

	return env
}

// prepareWorkingDir prepares the working directory for task execution.
func (e *Executor) prepareWorkingDir(tc Toolchain, task TaskDef) string {
	// Use task-specific working dir if provided
	if task.WorkingDir != "" {
		return task.WorkingDir
	}

	// Fall back to toolchain working dir
	if tc.WorkingDir != "" {
		return tc.WorkingDir
	}

	// Default to workspace root
	return e.ctx.WorkspaceRoot
}

// getTimeout returns the timeout for task execution.
func (e *Executor) getTimeout(tc Toolchain, task TaskDef) time.Duration {
	// Use task-specific timeout if provided
	if task.Timeout > 0 {
		return task.Timeout
	}

	// Fall back to toolchain timeout
	if tc.Timeout > 0 {
		return tc.Timeout
	}

	// Default to 5 minutes
	return 5 * time.Minute
}

// parseDiagnostics parses diagnostics from stderr output.
// For now, just creates a single diagnostic from stderr if non-empty.
// Future: parse JSONL format.
func (e *Executor) parseDiagnostics(stderr string) []pipeline.Diagnostic {
	if stderr == "" {
		return nil
	}

	// Try to parse as JSONL first
	lines := strings.Split(strings.TrimSpace(stderr), "\n")
	diagnostics := make([]pipeline.Diagnostic, 0, len(lines))

	for _, line := range lines {
		if line == "" {
			continue
		}

		// Try to parse as JSON diagnostic
		var diag struct {
			Level   string `json:"level"`
			Code    string `json:"code"`
			Message string `json:"message"`
			File    string `json:"file"`
			Line    int    `json:"line"`
			Column  int    `json:"col"`
		}

		if err := json.Unmarshal([]byte(line), &diag); err == nil {
			// Valid JSON diagnostic
			severity := pipeline.SeverityInfo
			switch diag.Level {
			case "error":
				severity = pipeline.SeverityError
			case "warn", "warning":
				severity = pipeline.SeverityWarn
			}

			d := pipeline.Diagnostic{
				Severity: severity,
				Code:     diag.Code,
				Message:  diag.Message,
			}

			if diag.File != "" {
				filePath, err := vfs.ParseVPath(diag.File)
				if err == nil {
					d.Location = &pipeline.Location{
						Path:   filePath,
						Line:   diag.Line,
						Column: diag.Column,
					}
				}
			}

			diagnostics = append(diagnostics, d)
		} else {
			// Plain text line - create info diagnostic
			diagnostics = append(diagnostics, pipeline.Diagnostic{
				Severity: pipeline.SeverityInfo,
				Message:  line,
			})
		}
	}

	return diagnostics
}

// writeMetadata writes task metadata to meta.json.
func (e *Executor) writeMetadata(toolchainName, taskName string, metadata TaskMetadata) error {
	metaPath, err := e.outputDir.MetaPath(toolchainName, taskName)
	if err != nil {
		return fmt.Errorf("failed to create metadata path: %w", err)
	}

	data, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal metadata: %w", err)
	}

	writer, err := e.ctx.VFS.Writer()
	if err != nil {
		return fmt.Errorf("failed to get VFS writer: %w", err)
	}

	_, err = writer.CreateFile(metaPath, data, vfs.WriteOptions{MkdirParents: true, Overwrite: true})
	if err != nil {
		return fmt.Errorf("failed to write metadata file: %w", err)
	}

	return nil
}

// writeDiagnostics writes diagnostics to diagnostics.jsonl.
func (e *Executor) writeDiagnostics(toolchainName, taskName string, diagnostics []pipeline.Diagnostic) error {
	if len(diagnostics) == 0 {
		return nil
	}

	diagPath, err := e.outputDir.DiagnosticsPath(toolchainName, taskName)
	if err != nil {
		return fmt.Errorf("failed to create diagnostics path: %w", err)
	}

	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)

	for _, diag := range diagnostics {
		diagData := map[string]any{
			"severity": string(diag.Severity),
			"message":  diag.Message,
		}
		if diag.Code != "" {
			diagData["code"] = diag.Code
		}
		if diag.Location != nil {
			diagData["file"] = diag.Location.Path.String()
			diagData["line"] = diag.Location.Line
			diagData["column"] = diag.Location.Column
		}

		if err := encoder.Encode(diagData); err != nil {
			return fmt.Errorf("failed to encode diagnostic: %w", err)
		}
	}

	writer, err := e.ctx.VFS.Writer()
	if err != nil {
		return fmt.Errorf("failed to get VFS writer: %w", err)
	}

	_, err = writer.CreateFile(diagPath, buf.Bytes(), vfs.WriteOptions{MkdirParents: true, Overwrite: true})
	if err != nil {
		return fmt.Errorf("failed to write diagnostics file: %w", err)
	}

	return nil
}
