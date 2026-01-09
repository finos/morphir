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

	// Native toolchain execution
	if tc.Type == ToolchainTypeNative {
		return e.executeNativeTask(tc, *taskDef, variant)
	}

	return TaskResult{}, fmt.Errorf("unknown toolchain type: %s", tc.Type)
}

// executeNativeTask executes an in-process native task.
func (e *Executor) executeNativeTask(tc Toolchain, task TaskDef, variant string) (TaskResult, error) {
	startTime := time.Now()

	// Verify task has a handler
	if task.Handler == nil {
		return TaskResult{}, fmt.Errorf("native task %s has no handler", task.Name)
	}

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

	// Build task input
	taskInput := TaskInput{
		Variant:        variant,
		Options:        make(map[string]any),
		InputArtifacts: make(map[string]any),
	}

	// Execute the native handler
	result := task.Handler(e.ctx, taskInput)

	endTime := time.Now()

	// Update metadata
	result.Metadata.ToolchainName = tc.Name
	result.Metadata.TaskName = task.Name
	result.Metadata.StartTime = startTime
	result.Metadata.EndTime = endTime
	result.Metadata.Duration = endTime.Sub(startTime)
	result.Metadata.Success = result.Error == nil

	// Write meta.json
	if err := e.writeMetadata(tc.Name, task.Name, result.Metadata); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to write metadata: %v\n", err)
	}

	// Write diagnostics.jsonl
	if err := e.writeDiagnostics(tc.Name, task.Name, result.Diagnostics); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to write diagnostics: %v\n", err)
	}

	return result, nil
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

	// For package runner backends, prepend package specifier to args
	switch tc.Acquire.Backend {
	case "npx":
		args = e.buildNpxArgs(tc, task, args)
	case "bunx":
		args = e.buildBunxArgs(tc, task, args)
	case "yarn-dlx":
		args = e.buildYarnDlxArgs(tc, task, args)
	case "pnpm-dlx":
		args = e.buildPnpmDlxArgs(tc, task, args)
	case "deno-npm":
		args = e.buildDenoNpmArgs(tc, task, args)
	case "npm-exec":
		args = e.buildNpmExecArgs(tc, task, args)
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
	switch tc.Acquire.Backend {
	case "path", "":
		return e.resolvePathExecutable(tc, task)
	case "npx":
		return e.resolveNpxExecutable(tc)
	case "bunx":
		return e.resolveBunxExecutable(tc)
	case "yarn-dlx":
		return e.resolveYarnDlxExecutable(tc)
	case "pnpm-dlx":
		return e.resolvePnpmDlxExecutable(tc)
	case "deno-npm":
		return e.resolveDenoNpmExecutable(tc)
	case "npm-exec":
		return e.resolveNpmExecExecutable(tc)
	default:
		return "", fmt.Errorf("acquisition backend %s not yet implemented", tc.Acquire.Backend)
	}
}

// resolvePathExecutable resolves an executable from the system PATH.
func (e *Executor) resolvePathExecutable(tc Toolchain, task TaskDef) (string, error) {
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

// resolveNpxExecutable resolves npx as the executable for npm package execution.
func (e *Executor) resolveNpxExecutable(tc Toolchain) (string, error) {
	// Verify npx is available
	npxPath, err := exec.LookPath("npx")
	if err != nil {
		return "", fmt.Errorf("npx not found in PATH (required for backend 'npx'): %w", err)
	}

	// Verify package is specified
	if tc.Acquire.Package == "" {
		return "", fmt.Errorf("package must be specified for npx backend")
	}

	return npxPath, nil
}

// buildNpxArgs builds the argument list for npx execution.
// It prepends the package specifier (with optional version) to the task args.
func (e *Executor) buildNpxArgs(tc Toolchain, task TaskDef, taskArgs []string) []string {
	// Build package specifier
	packageSpec := tc.Acquire.Package
	if tc.Acquire.Version != "" {
		packageSpec = packageSpec + "@" + tc.Acquire.Version
	}

	// npx args: ["-y", "package@version", ...taskArgs]
	// -y flag auto-confirms installation prompts
	npxArgs := []string{"-y", packageSpec}

	// Append the task's subcommand args
	npxArgs = append(npxArgs, taskArgs...)

	return npxArgs
}

// resolveBunxExecutable resolves bunx as the executable for Bun package execution.
func (e *Executor) resolveBunxExecutable(tc Toolchain) (string, error) {
	// Verify bunx is available
	bunxPath, err := exec.LookPath("bunx")
	if err != nil {
		return "", fmt.Errorf("bunx not found in PATH (required for backend 'bunx'): %w", err)
	}

	// Verify package is specified
	if tc.Acquire.Package == "" {
		return "", fmt.Errorf("package must be specified for bunx backend")
	}

	return bunxPath, nil
}

// buildBunxArgs builds the argument list for bunx execution.
// It prepends the package specifier (with optional version) to the task args.
func (e *Executor) buildBunxArgs(tc Toolchain, task TaskDef, taskArgs []string) []string {
	// Build package specifier
	packageSpec := tc.Acquire.Package
	if tc.Acquire.Version != "" {
		packageSpec = packageSpec + "@" + tc.Acquire.Version
	}

	// bunx args: ["package@version", ...taskArgs]
	// bunx auto-installs without prompting, no -y flag needed
	bunxArgs := []string{packageSpec}

	// Append the task's subcommand args
	bunxArgs = append(bunxArgs, taskArgs...)

	return bunxArgs
}

// resolveYarnDlxExecutable resolves yarn as the executable for yarn dlx package execution.
func (e *Executor) resolveYarnDlxExecutable(tc Toolchain) (string, error) {
	// Verify yarn is available
	yarnPath, err := exec.LookPath("yarn")
	if err != nil {
		return "", fmt.Errorf("yarn not found in PATH (required for backend 'yarn-dlx'): %w", err)
	}

	// Verify package is specified
	if tc.Acquire.Package == "" {
		return "", fmt.Errorf("package must be specified for yarn-dlx backend")
	}

	return yarnPath, nil
}

// buildYarnDlxArgs builds the argument list for yarn dlx execution.
// It prepends "dlx" and the package specifier (with optional version) to the task args.
func (e *Executor) buildYarnDlxArgs(tc Toolchain, task TaskDef, taskArgs []string) []string {
	// Build package specifier
	packageSpec := tc.Acquire.Package
	if tc.Acquire.Version != "" {
		packageSpec = packageSpec + "@" + tc.Acquire.Version
	}

	// yarn dlx args: ["dlx", "package@version", ...taskArgs]
	// yarn dlx auto-installs without prompting
	yarnArgs := []string{"dlx", packageSpec}

	// Append the task's subcommand args
	yarnArgs = append(yarnArgs, taskArgs...)

	return yarnArgs
}

// resolvePnpmDlxExecutable resolves pnpm as the executable for pnpm dlx package execution.
func (e *Executor) resolvePnpmDlxExecutable(tc Toolchain) (string, error) {
	// Verify pnpm is available
	pnpmPath, err := exec.LookPath("pnpm")
	if err != nil {
		return "", fmt.Errorf("pnpm not found in PATH (required for backend 'pnpm-dlx'): %w", err)
	}

	// Verify package is specified
	if tc.Acquire.Package == "" {
		return "", fmt.Errorf("package must be specified for pnpm-dlx backend")
	}

	return pnpmPath, nil
}

// buildPnpmDlxArgs builds the argument list for pnpm dlx execution.
// It prepends "dlx" and the package specifier (with optional version) to the task args.
func (e *Executor) buildPnpmDlxArgs(tc Toolchain, task TaskDef, taskArgs []string) []string {
	// Build package specifier
	packageSpec := tc.Acquire.Package
	if tc.Acquire.Version != "" {
		packageSpec = packageSpec + "@" + tc.Acquire.Version
	}

	// pnpm dlx args: ["dlx", "package@version", ...taskArgs]
	// pnpm dlx auto-installs without prompting
	pnpmArgs := []string{"dlx", packageSpec}

	// Append the task's subcommand args
	pnpmArgs = append(pnpmArgs, taskArgs...)

	return pnpmArgs
}

// resolveDenoNpmExecutable resolves deno as the executable for deno npm package execution.
func (e *Executor) resolveDenoNpmExecutable(tc Toolchain) (string, error) {
	// Verify deno is available
	denoPath, err := exec.LookPath("deno")
	if err != nil {
		return "", fmt.Errorf("deno not found in PATH (required for backend 'deno-npm'): %w", err)
	}

	// Verify package is specified
	if tc.Acquire.Package == "" {
		return "", fmt.Errorf("package must be specified for deno-npm backend")
	}

	return denoPath, nil
}

// buildDenoNpmArgs builds the argument list for deno npm execution.
// It uses "deno run npm:package@version" to run npm packages.
func (e *Executor) buildDenoNpmArgs(tc Toolchain, task TaskDef, taskArgs []string) []string {
	// Build npm package specifier
	packageSpec := "npm:" + tc.Acquire.Package
	if tc.Acquire.Version != "" {
		packageSpec = packageSpec + "@" + tc.Acquire.Version
	}

	// deno npm args: ["run", "-A", "npm:package@version", ...taskArgs]
	// -A grants all permissions (required for most npm packages)
	denoArgs := []string{"run", "-A", packageSpec}

	// Append the task's subcommand args
	denoArgs = append(denoArgs, taskArgs...)

	return denoArgs
}

// resolveNpmExecExecutable resolves npm as the executable for npm exec package execution.
func (e *Executor) resolveNpmExecExecutable(tc Toolchain) (string, error) {
	// Verify npm is available
	npmPath, err := exec.LookPath("npm")
	if err != nil {
		return "", fmt.Errorf("npm not found in PATH (required for backend 'npm-exec'): %w", err)
	}

	// Verify package is specified
	if tc.Acquire.Package == "" {
		return "", fmt.Errorf("package must be specified for npm-exec backend")
	}

	return npmPath, nil
}

// buildNpmExecArgs builds the argument list for npm exec execution.
// It uses "npm exec -- package@version args..." to run packages.
func (e *Executor) buildNpmExecArgs(tc Toolchain, task TaskDef, taskArgs []string) []string {
	// Build package specifier
	packageSpec := tc.Acquire.Package
	if tc.Acquire.Version != "" {
		packageSpec = packageSpec + "@" + tc.Acquire.Version
	}

	// npm exec args: ["exec", "--yes", "--", "package@version", ...taskArgs]
	// --yes auto-confirms installation prompts (like npx -y)
	// -- separates npm options from the package command
	npmArgs := []string{"exec", "--yes", "--", packageSpec}

	// Append the task's subcommand args
	npmArgs = append(npmArgs, taskArgs...)

	return npmArgs
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
