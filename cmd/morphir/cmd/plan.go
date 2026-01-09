package cmd

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sort"
	"strings"
	"syscall"
	"time"

	golangtoolchain "github.com/finos/morphir/pkg/bindings/golang/toolchain"
	wittoolchain "github.com/finos/morphir/pkg/bindings/wit/toolchain"
	"github.com/finos/morphir/pkg/config"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/toolchain"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/spf13/cobra"
)

var (
	planExplainTarget string
	planRun           bool
	planDryRun        bool
	planStopOnError   bool
	planMaxParallel   int
	planTimeout       time.Duration
	planMermaid       bool
	planMermaidPath   string
	planShowInputs    bool
	planShowOutputs   bool
)

var planCmd = &cobra.Command{
	Use:   "plan <workflow>",
	Short: "Show execution plan for a workflow",
	Long: `Compute and display the execution plan for a workflow.

The workflow must be defined in morphir.toml under [workflows.<name>].

Use --run to execute the plan after displaying it.
Use --dry-run to validate the plan without executing tasks.
Use --mermaid to emit a Mermaid diagram visualizing the plan.
Use --mermaid-path to specify a custom output path for the diagram.
Use --show-inputs and --show-outputs to include inputs/outputs in the diagram.`,
	Args: cobra.ExactArgs(1),
	RunE: runPlan,
}

func runPlan(cmd *cobra.Command, args []string) error {
	cfg, err := GetConfig()
	if err != nil {
		return err
	}

	workflowName := args[0]
	workflows := workflowsFromConfig(cfg)
	if len(workflows) == 0 {
		return fmt.Errorf("no workflows defined in config")
	}

	registry, err := registryFromConfig(cfg)
	if err != nil {
		return err
	}

	builder := toolchain.NewPlanBuilder(registry, workflows)
	plan, err := builder.Build(workflowName)
	if err != nil {
		return err
	}

	printPlan(plan)

	if planExplainTarget != "" {
		if err := explainPlan(plan, planExplainTarget); err != nil {
			return err
		}
	}

	// Execute the plan if --run or --dry-run was specified
	var result *toolchain.WorkflowResult
	if planRun || planDryRun {
		result, err = executePlanAndGetResult(plan, registry, cfg)
		if err != nil && !planMermaid {
			return err
		}
	}

	// Generate mermaid diagram if requested
	if planMermaid {
		if err := emitMermaidDiagram(plan, workflowName, cfg, result); err != nil {
			return err
		}
	}

	// Return execution error after mermaid generation
	if err != nil {
		return err
	}

	return nil
}

// executePlanAndGetResult runs the workflow plan and returns the result.
func executePlanAndGetResult(plan toolchain.Plan, registry *toolchain.Registry, cfg config.Config) (*toolchain.WorkflowResult, error) {
	// Set up output directory
	workDir, err := os.Getwd()
	if err != nil {
		return nil, fmt.Errorf("failed to get working directory: %w", err)
	}

	outputDir := cfg.Workspace().OutputDir()
	if outputDir == "" {
		outputDir = ".morphir"
	}

	// Create VFS with OS mount for working directory
	osMount := vfs.NewOSMount("work", vfs.MountRW, workDir, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{osMount})

	// Create output directory path
	outputRoot := vfs.MustVPath("/" + outputDir + "/out")
	outputDirStructure := toolchain.NewOutputDirStructure(outputRoot, overlay)

	// Create pipeline context
	formatVersion := cfg.IR().FormatVersion()
	if formatVersion == 0 {
		formatVersion = 3 // Default IR version
	}
	pipelineCtx := pipeline.NewContext(workDir, formatVersion, pipeline.ModeDefault, overlay)

	// Create executor
	executor := toolchain.NewExecutor(registry, outputDirStructure, pipelineCtx)

	// Create runner
	runner := toolchain.NewWorkflowRunner(executor, outputDirStructure)

	// Set up context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle interrupt signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigChan
		fmt.Println("\nInterrupted, cancelling...")
		cancel()
	}()

	// Configure run options
	opts := toolchain.RunOptions{
		DryRun:      planDryRun,
		StopOnError: planStopOnError,
		MaxParallel: planMaxParallel,
		Timeout:     planTimeout,
		Context:     ctx,
		Progress:    progressCallback,
	}

	fmt.Println()
	if planDryRun {
		fmt.Println("=== Dry Run ===")
	} else {
		fmt.Println("=== Executing Plan ===")
	}

	result := runner.Run(plan, opts)

	fmt.Println()
	fmt.Print(result.Summary())

	if !result.Success {
		if result.Error != nil {
			return &result, result.Error
		}
		return &result, fmt.Errorf("workflow failed: %d task(s) failed", len(result.FailedTasks))
	}

	return &result, nil
}

// emitMermaidDiagram generates and writes a Mermaid diagram of the plan.
func emitMermaidDiagram(plan toolchain.Plan, workflowName string, cfg config.Config, result *toolchain.WorkflowResult) error {
	// Determine output path
	outputPath := planMermaidPath
	if outputPath == "" {
		// Use default location
		outputDir := cfg.Workspace().OutputDir()
		if outputDir == "" {
			outputDir = ".morphir"
		}
		outputPath = fmt.Sprintf("%s/out/plan/%s/plan.mmd", outputDir, workflowName)
	}

	// Build mermaid options
	opts := toolchain.MermaidOptions{
		ShowInputs:  planShowInputs,
		ShowOutputs: planShowOutputs,
	}

	// Include task results for styling if available
	if result != nil {
		opts.TaskResults = result.TaskResults
	}

	// Generate diagram
	diagram := toolchain.PlanToMermaidWithOptions(plan, opts)

	// Ensure directory exists
	if idx := strings.LastIndex(outputPath, "/"); idx > 0 {
		dir := outputPath[:idx]
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("failed to create output directory: %w", err)
		}
	}

	// Write file
	if err := os.WriteFile(outputPath, []byte(diagram), 0644); err != nil {
		return fmt.Errorf("failed to write mermaid diagram: %w", err)
	}

	fmt.Printf("\nMermaid diagram written to: %s\n", outputPath)
	return nil
}

// progressCallback reports execution progress to the console.
func progressCallback(event toolchain.ProgressEvent) {
	switch event.Type {
	case toolchain.ProgressStageStarted:
		fmt.Printf("\n[Stage] %s\n", event.Stage.Name)
	case toolchain.ProgressTaskStarted:
		fmt.Printf("  → %s/%s", event.Task.Toolchain, event.Task.Task)
		if event.Task.Variant != "" {
			fmt.Printf(" (%s)", event.Task.Variant)
		}
		fmt.Println()
	case toolchain.ProgressTaskCompleted:
		if event.TaskResult != nil {
			if event.TaskResult.Metadata.Success {
				fmt.Printf("    ✓ completed in %s\n", event.TaskResult.Metadata.Duration)
			} else {
				fmt.Printf("    ✗ failed: %v\n", event.TaskResult.Error)
			}
		}
	case toolchain.ProgressStageSkipped:
		fmt.Printf("\n[Stage] %s (skipped: %s)\n", event.Stage.Name, event.Message)
	case toolchain.ProgressError:
		fmt.Printf("  ⚠ error: %v\n", event.Error)
	}
}

func init() {
	planCmd.Flags().StringVar(&planExplainTarget, "explain", "", "Explain why a target runs (e.g., gen:scala)")
	planCmd.Flags().BoolVar(&planRun, "run", false, "Execute the plan after displaying it")
	planCmd.Flags().BoolVar(&planDryRun, "dry-run", false, "Validate plan without executing tasks")
	planCmd.Flags().BoolVar(&planStopOnError, "stop-on-error", true, "Stop execution on first error")
	planCmd.Flags().IntVar(&planMaxParallel, "max-parallel", 0, "Max parallel tasks (0 = unlimited)")
	planCmd.Flags().DurationVar(&planTimeout, "timeout", 0, "Overall workflow timeout (0 = no timeout)")

	// Mermaid diagram flags
	planCmd.Flags().BoolVar(&planMermaid, "mermaid", false, "Emit Mermaid diagram of the plan")
	planCmd.Flags().StringVar(&planMermaidPath, "mermaid-path", "", "Path for Mermaid diagram output (default: .morphir/out/plan/<workflow>/plan.mmd)")
	planCmd.Flags().BoolVar(&planShowInputs, "show-inputs", false, "Include task inputs in Mermaid diagram")
	planCmd.Flags().BoolVar(&planShowOutputs, "show-outputs", false, "Include task outputs in Mermaid diagram")
}

func registryFromConfig(cfg config.Config) (*toolchain.Registry, error) {
	registry := toolchain.NewRegistry()

	wittoolchain.Register(registry)
	golangtoolchain.Register(registry)

	toolchains := cfg.Toolchains()
	names := toolchains.Names()
	sort.Strings(names)

	for _, name := range names {
		tcCfg, ok := toolchains.Get(name)
		if !ok {
			continue
		}

		tasks := tcCfg.Tasks()
		tc := toolchain.Toolchain{
			Name:        name,
			Version:     tcCfg.Version(),
			Description: "",
			Acquire: toolchain.AcquireConfig{
				Backend:    tcCfg.Acquire().Backend(),
				Package:    tcCfg.Acquire().Package(),
				Version:    tcCfg.Acquire().Version(),
				Executable: tcCfg.Acquire().Executable(),
			},
			Env:        tcCfg.Env(),
			WorkingDir: tcCfg.WorkingDir(),
			Type:       toolchain.ToolchainTypeExternal,
		}

		if timeoutStr := tcCfg.Timeout(); timeoutStr != "" {
			if duration, err := time.ParseDuration(timeoutStr); err == nil {
				tc.Timeout = duration
			}
		}

		taskDefs := make([]toolchain.TaskDef, 0)
		taskNames := make([]string, 0)
		for taskName := range tasks {
			taskNames = append(taskNames, taskName)
		}
		sort.Strings(taskNames)

		for _, taskName := range taskNames {
			taskCfg := tasks[taskName]
			taskDef := toolchain.TaskDef{
				Name:        taskName,
				Exec:        taskCfg.Exec(),
				Args:        taskCfg.Args(),
				Inputs:      toolchain.InputSpec{Files: taskCfg.Inputs().Files(), Artifacts: taskCfg.Inputs().Artifacts()},
				Outputs:     outputSpecsFromConfig(taskCfg.Outputs()),
				Fulfills:    taskCfg.Fulfills(),
				Variants:    taskCfg.Variants(),
				Env:         taskCfg.Env(),
				WorkingDir:  "",
				Timeout:     0,
				Description: "",
			}
			taskDefs = append(taskDefs, taskDef)

			registerTargetFromTask(registry, taskDef)
		}

		tc.Tasks = taskDefs
		registry.Register(tc)
	}

	return registry, nil
}

func registerTargetFromTask(registry *toolchain.Registry, task toolchain.TaskDef) {
	for _, name := range task.Fulfills {
		if _, ok := registry.GetTarget(name); ok {
			continue
		}

		produces := make([]string, 0, len(task.Outputs))
		for _, output := range task.Outputs {
			if output.Type == "" {
				continue
			}
			produces = append(produces, output.Type)
		}
		if len(produces) == 0 {
			produces = nil
		}

		registry.RegisterTarget(toolchain.Target{
			Name:     name,
			Produces: uniqueStrings(produces),
			Variants: task.Variants,
		})
	}
}

func outputSpecsFromConfig(outputs map[string]config.OutputConfig) map[string]toolchain.OutputSpec {
	if len(outputs) == 0 {
		return nil
	}
	result := make(map[string]toolchain.OutputSpec, len(outputs))
	for name, output := range outputs {
		result[name] = toolchain.OutputSpec{
			Path: output.Path(),
			Type: output.Type(),
		}
	}
	return result
}

func workflowsFromConfig(cfg config.Config) map[string]toolchain.Workflow {
	workflows := cfg.Workflows()
	names := workflows.Names()
	if len(names) == 0 {
		return nil
	}

	result := make(map[string]toolchain.Workflow, len(names))
	for _, name := range names {
		workflowCfg, ok := workflows.Get(name)
		if !ok {
			continue
		}
		stages := workflowStagesFromConfig(workflowCfg.Stages())
		result[name] = toolchain.Workflow{
			Name:        workflowCfg.Name(),
			Description: workflowCfg.Description(),
			Extends:     workflowCfg.Extends(),
			Stages:      stages,
		}
	}
	return result
}

func workflowStagesFromConfig(stages []config.WorkflowStageConfig) []toolchain.WorkflowStage {
	if len(stages) == 0 {
		return nil
	}
	result := make([]toolchain.WorkflowStage, 0, len(stages))
	for _, stage := range stages {
		result = append(result, toolchain.WorkflowStage{
			Name:      stage.Name(),
			Targets:   stage.Targets(),
			Parallel:  stage.Parallel(),
			Condition: stage.Condition(),
		})
	}
	return result
}

func printPlan(plan toolchain.Plan) {
	fmt.Printf("Execution Plan for workflow %q:\n", plan.Workflow.Name)
	for _, stage := range plan.Stages {
		header := fmt.Sprintf("Stage: %s", stage.Name)
		if stage.Parallel {
			header += " (parallel)"
		}
		if stage.Condition != "" {
			header += fmt.Sprintf(" [if %s]", stage.Condition)
		}
		fmt.Println(header)

		for _, task := range stage.Tasks {
			fmt.Printf("  - %s\n", formatTaskLabel(task))
			if inputs := formatInputs(task.Inputs); inputs != "" {
				fmt.Printf("    inputs: %s\n", inputs)
			}
			if outputs := formatOutputs(task.Outputs); outputs != "" {
				fmt.Printf("    outputs: %s\n", outputs)
			}
		}
	}
}

func explainPlan(plan toolchain.Plan, targetSpec string) error {
	targetName, variant, err := parseTargetSpec(targetSpec)
	if err != nil {
		return err
	}

	task, err := findTaskByTarget(plan, targetName, variant)
	if err != nil {
		return err
	}

	chain := dependencyChain(plan, task)
	fmt.Printf("\nDependency chain for %q:\n", targetSpec)
	for _, item := range chain {
		fmt.Printf("  - %s\n", formatTaskLabel(item))
	}
	return nil
}

func findTaskByTarget(plan toolchain.Plan, targetName, variant string) (*toolchain.PlanTask, error) {
	var matches []*toolchain.PlanTask
	for _, task := range plan.Tasks {
		if task.Target != targetName {
			continue
		}
		if variant == "" || strings.EqualFold(task.Variant, variant) {
			matches = append(matches, task)
		}
	}
	if len(matches) == 0 {
		return nil, fmt.Errorf("no task in plan matches target %q", targetName)
	}
	if len(matches) > 1 {
		return nil, fmt.Errorf("multiple tasks match target %q; include a variant to disambiguate", targetName)
	}
	return matches[0], nil
}

func dependencyChain(plan toolchain.Plan, task *toolchain.PlanTask) []*toolchain.PlanTask {
	visited := make(map[toolchain.TaskKey]struct{})
	var order []*toolchain.PlanTask

	var visit func(key toolchain.TaskKey)
	visit = func(key toolchain.TaskKey) {
		if _, ok := visited[key]; ok {
			return
		}
		visited[key] = struct{}{}
		node, ok := plan.Tasks[key]
		if !ok {
			return
		}
		for _, dep := range node.DependsOn {
			visit(dep)
		}
		order = append(order, node)
	}

	visit(task.Key)
	sort.SliceStable(order, func(i, j int) bool {
		if order[i].StageIndex != order[j].StageIndex {
			return order[i].StageIndex < order[j].StageIndex
		}
		return order[i].Key.String() < order[j].Key.String()
	})
	return order
}

func formatTaskLabel(task *toolchain.PlanTask) string {
	label := fmt.Sprintf("%s/%s", task.Toolchain, task.Task)
	if task.Variant != "" {
		label += fmt.Sprintf(" (variant: %s)", task.Variant)
	}
	return label
}

func formatInputs(inputs toolchain.InputSpec) string {
	parts := make([]string, 0, len(inputs.Files)+len(inputs.Artifacts))
	if len(inputs.Files) > 0 {
		parts = append(parts, inputs.Files...)
	}
	if len(inputs.Artifacts) > 0 {
		keys := make([]string, 0, len(inputs.Artifacts))
		for key := range inputs.Artifacts {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			parts = append(parts, inputs.Artifacts[key])
		}
	}
	if len(parts) == 0 {
		return ""
	}
	return strings.Join(parts, ", ")
}

func formatOutputs(outputs map[string]toolchain.OutputSpec) string {
	if len(outputs) == 0 {
		return ""
	}
	keys := make([]string, 0, len(outputs))
	for key := range outputs {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	formatted := make([]string, 0, len(keys))
	for _, key := range keys {
		output := outputs[key]
		if output.Type != "" {
			formatted = append(formatted, fmt.Sprintf("%s (%s)", key, output.Type))
		} else {
			formatted = append(formatted, key)
		}
	}
	return strings.Join(formatted, ", ")
}

func parseTargetSpec(spec string) (string, string, error) {
	if strings.TrimSpace(spec) == "" {
		return "", "", fmt.Errorf("empty target specification")
	}
	parts := strings.SplitN(spec, ":", 2)
	if len(parts) == 1 {
		return parts[0], "", nil
	}
	if parts[0] == "" {
		return "", "", fmt.Errorf("invalid target specification %q: missing target name", spec)
	}
	if parts[1] == "" {
		return "", "", fmt.Errorf("invalid target specification %q: missing variant", spec)
	}
	return parts[0], parts[1], nil
}

func uniqueStrings(values []string) []string {
	if len(values) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	if len(result) == 0 {
		return nil
	}
	sort.Strings(result)
	return result
}
