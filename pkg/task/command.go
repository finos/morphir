package task

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/finos/morphir/pkg/pipeline"
)

// CommandRunner executes external commands with environment and output handling.
type CommandRunner struct {
	// WorkDir is the working directory for command execution.
	// If empty, uses the current directory.
	WorkDir string

	// Timeout is the maximum duration for command execution.
	// If zero, no timeout is applied.
	Timeout time.Duration
}

// CommandOutput holds the result of command execution.
type CommandOutput struct {
	// ExitCode is the command's exit code.
	ExitCode int

	// Stdout is the standard output captured from the command.
	Stdout string

	// Stderr is the standard error captured from the command.
	Stderr string

	// Parsed is the JSON-parsed stdout if it was valid JSON, otherwise nil.
	Parsed any

	// Duration is how long the command took to execute.
	Duration time.Duration
}

// Run executes the given command with the provided environment.
func (r *CommandRunner) Run(cmd []string, env map[string]string) (CommandOutput, error) {
	if len(cmd) == 0 {
		return CommandOutput{ExitCode: -1}, &TaskError{
			Message: "empty command",
		}
	}

	var output CommandOutput
	started := time.Now()

	// Create the command
	ctx := context.Background()
	var cancel context.CancelFunc

	if r.Timeout > 0 {
		ctx, cancel = context.WithTimeout(ctx, r.Timeout)
		defer cancel()
	}

	execCmd := exec.CommandContext(ctx, cmd[0], cmd[1:]...)

	// Set working directory
	if r.WorkDir != "" {
		execCmd.Dir = r.WorkDir
	}

	// Set environment variables
	execCmd.Env = buildEnv(env)

	// Capture stdout and stderr
	var stdout, stderr bytes.Buffer
	execCmd.Stdout = &stdout
	execCmd.Stderr = &stderr

	// Run the command
	err := execCmd.Run()
	output.Duration = time.Since(started)
	output.Stdout = stdout.String()
	output.Stderr = stderr.String()

	// Get exit code
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			output.ExitCode = exitErr.ExitCode()
		} else {
			output.ExitCode = -1
			return output, &TaskError{
				Message: fmt.Sprintf("failed to execute command: %v", err),
				Cause:   err,
			}
		}
	} else {
		output.ExitCode = 0
	}

	// Try to parse stdout as JSON
	if output.Stdout != "" {
		var parsed any
		if err := json.Unmarshal([]byte(output.Stdout), &parsed); err == nil {
			output.Parsed = parsed
		}
	}

	return output, nil
}

// buildEnv creates the environment slice for command execution.
// It starts with the current environment and adds/overrides with the provided map.
func buildEnv(env map[string]string) []string {
	// Start with current environment
	result := os.Environ()

	// Add/override with provided environment
	for k, v := range env {
		// Remove existing entries for this key
		key := k + "="
		for i := len(result) - 1; i >= 0; i-- {
			if strings.HasPrefix(result[i], key) {
				result = append(result[:i], result[i+1:]...)
			}
		}
		// Add the new value
		result = append(result, k+"="+v)
	}

	return result
}

// ValidateMounts checks if the command has valid mount permissions.
// Returns an error if any mount is invalid.
func ValidateMounts(mounts map[string]string, rwRequired []string) error {
	for _, required := range rwRequired {
		perm, ok := mounts[required]
		if !ok {
			return &TaskError{
				Message: fmt.Sprintf("mount %q not specified", required),
			}
		}
		if perm != "rw" {
			return &TaskError{
				Message: fmt.Sprintf("mount %q requires rw permission, got %q", required, perm),
			}
		}
	}
	return nil
}

// ResolveCommand resolves command paths and validates the command is executable.
func ResolveCommand(cmd []string, workDir string) ([]string, error) {
	if len(cmd) == 0 {
		return nil, &TaskError{Message: "empty command"}
	}

	// If command starts with ./ or ../, resolve relative to workDir
	cmdPath := cmd[0]
	if strings.HasPrefix(cmdPath, "./") || strings.HasPrefix(cmdPath, "../") {
		if workDir != "" {
			cmdPath = filepath.Join(workDir, cmdPath)
		}
		cmd[0] = cmdPath
	}

	return cmd, nil
}

// executeCommand is the Executor method that runs external commands.
func (e *Executor) executeCommand(ctx pipeline.Context, task Task) (TaskResult, error) {
	cfg := task.Config

	// Validate command is specified
	if len(cfg.Cmd) == 0 {
		return TaskResult{}, &TaskError{
			TaskName: task.Name,
			Message:  "no command specified",
		}
	}

	// Resolve the command path
	resolvedCmd, err := ResolveCommand(cfg.Cmd, ctx.WorkspaceRoot)
	if err != nil {
		return TaskResult{}, &TaskError{
			TaskName: task.Name,
			Message:  err.Error(),
		}
	}

	// Create runner
	runner := &CommandRunner{
		WorkDir: ctx.WorkspaceRoot,
	}

	// Execute the command
	output, err := runner.Run(resolvedCmd, cfg.Env)
	if err != nil {
		return TaskResult{
			Name: task.Name,
			Err:  err,
		}, err
	}

	// Build result
	result := TaskResult{
		Name:   task.Name,
		Output: output.Parsed,
	}

	// If command failed, add diagnostic and error
	if output.ExitCode != 0 {
		diag := pipeline.Diagnostic{
			Severity: pipeline.SeverityError,
			Code:     fmt.Sprintf("CMD_%d", output.ExitCode),
			Message:  fmt.Sprintf("command exited with code %d", output.ExitCode),
			StepName: task.Name,
		}
		result.Diagnostics = append(result.Diagnostics, diag)

		// Add stderr as additional diagnostic if present
		if output.Stderr != "" {
			stderrDiag := pipeline.Diagnostic{
				Severity: pipeline.SeverityError,
				Code:     "CMD_STDERR",
				Message:  strings.TrimSpace(output.Stderr),
				StepName: task.Name,
			}
			result.Diagnostics = append(result.Diagnostics, stderrDiag)
		}

		result.Err = &TaskError{
			TaskName: task.Name,
			Message:  fmt.Sprintf("command failed with exit code %d", output.ExitCode),
		}
		return result, result.Err
	}

	// If no parsed output, use raw stdout
	if result.Output == nil && output.Stdout != "" {
		result.Output = output.Stdout
	}

	return result, nil
}
