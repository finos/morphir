package toolchain

import (
	"time"

	"github.com/finos/morphir/pkg/config"
)

// LoadWorkflowsFromConfig converts workflow configurations to toolchain workflows.
// It returns a slice of Workflow structs ready for use with the WorkflowRunner.
func LoadWorkflowsFromConfig(cfg config.Config) []Workflow {
	workflowsSection := cfg.Workflows()
	names := workflowsSection.Names()

	if len(names) == 0 {
		return nil
	}

	workflows := make([]Workflow, 0, len(names))
	for _, name := range names {
		wfCfg, ok := workflowsSection.Get(name)
		if !ok {
			continue
		}
		workflows = append(workflows, WorkflowFromConfig(wfCfg))
	}

	return workflows
}

// WorkflowFromConfig converts a config.WorkflowConfig to a toolchain.Workflow.
func WorkflowFromConfig(cfg config.WorkflowConfig) Workflow {
	stages := cfg.Stages()
	workflowStages := make([]WorkflowStage, 0, len(stages))

	for _, stageCfg := range stages {
		workflowStages = append(workflowStages, WorkflowStageFromConfig(stageCfg))
	}

	return Workflow{
		Name:        cfg.Name(),
		Description: cfg.Description(),
		Extends:     cfg.Extends(),
		Stages:      workflowStages,
	}
}

// WorkflowStageFromConfig converts a config.WorkflowStageConfig to a toolchain.WorkflowStage.
func WorkflowStageFromConfig(cfg config.WorkflowStageConfig) WorkflowStage {
	return WorkflowStage{
		Name:      cfg.Name(),
		Targets:   cfg.Targets(),
		Parallel:  cfg.Parallel(),
		Condition: cfg.Condition(),
	}
}

// LoadToolchainsFromConfig converts toolchain configurations to toolchain structs.
// It returns a slice of Toolchain structs ready for registration.
func LoadToolchainsFromConfig(cfg config.Config) []Toolchain {
	toolchainsSection := cfg.Toolchains()
	names := toolchainsSection.Names()

	if len(names) == 0 {
		return nil
	}

	toolchains := make([]Toolchain, 0, len(names))
	for _, name := range names {
		tcCfg, ok := toolchainsSection.Get(name)
		if !ok {
			continue
		}
		toolchains = append(toolchains, ToolchainFromConfig(tcCfg))
	}

	return toolchains
}

// ToolchainFromConfig converts a config.ToolchainConfig to a toolchain.Toolchain.
func ToolchainFromConfig(cfg config.ToolchainConfig) Toolchain {
	// Parse timeout duration
	var timeout time.Duration
	if cfg.Timeout() != "" {
		if d, err := time.ParseDuration(cfg.Timeout()); err == nil {
			timeout = d
		}
	}

	// Convert tasks
	taskConfigs := cfg.Tasks()
	tasks := make([]TaskDef, 0, len(taskConfigs))
	for taskName, taskCfg := range taskConfigs {
		tasks = append(tasks, TaskDefFromConfig(taskName, taskCfg))
	}

	// Convert acquire config
	acquireCfg := cfg.Acquire()
	acquire := AcquireConfig{
		Backend:    acquireCfg.Backend(),
		Package:    acquireCfg.Package(),
		Version:    acquireCfg.Version(),
		Executable: acquireCfg.Executable(),
	}

	return Toolchain{
		Name:        cfg.Name(),
		Version:     cfg.Version(),
		Description: "", // Not in config
		Acquire:     acquire,
		Env:         cfg.Env(),
		WorkingDir:  cfg.WorkingDir(),
		Timeout:     timeout,
		Tasks:       tasks,
		Type:        ToolchainTypeExternal, // Assume external for config-loaded toolchains
	}
}

// TaskDefFromConfig converts a config.ToolchainTaskConfig to a toolchain.TaskDef.
func TaskDefFromConfig(name string, cfg config.ToolchainTaskConfig) TaskDef {
	// Convert inputs
	inputsCfg := cfg.Inputs()
	inputs := InputSpec{
		Files:     inputsCfg.Files(),
		Artifacts: inputsCfg.Artifacts(),
	}

	// Convert outputs
	outputsCfg := cfg.Outputs()
	outputs := make(map[string]OutputSpec, len(outputsCfg))
	for outputName, outputCfg := range outputsCfg {
		outputs[outputName] = OutputSpec{
			Path: outputCfg.Path(),
			Type: outputCfg.Type(),
		}
	}

	return TaskDef{
		Name:        name,
		Description: "", // Not in config
		Exec:        cfg.Exec(),
		Args:        cfg.Args(),
		Handler:     nil, // Config-loaded tasks are external, no native handler
		Inputs:      inputs,
		Outputs:     outputs,
		Fulfills:    cfg.Fulfills(),
		Variants:    cfg.Variants(),
		Env:         cfg.Env(),
		WorkingDir:  "", // Not in config at task level
		Timeout:     0,  // Not in config at task level
	}
}

// RegisterToolchainsFromConfig registers toolchains from config into the registry.
func RegisterToolchainsFromConfig(registry *Registry, cfg config.Config) {
	toolchains := LoadToolchainsFromConfig(cfg)
	for _, tc := range toolchains {
		registry.Register(tc)
	}
}

// GetWorkflow retrieves a workflow by name from config.
// Returns the workflow and true if found, otherwise zero value and false.
func GetWorkflow(cfg config.Config, name string) (Workflow, bool) {
	workflowsSection := cfg.Workflows()
	wfCfg, ok := workflowsSection.Get(name)
	if !ok {
		return Workflow{}, false
	}
	return WorkflowFromConfig(wfCfg), true
}

// GetToolchain retrieves a toolchain by name from config.
// Returns the toolchain and true if found, otherwise zero value and false.
func GetToolchain(cfg config.Config, name string) (Toolchain, bool) {
	toolchainsSection := cfg.Toolchains()
	tcCfg, ok := toolchainsSection.Get(name)
	if !ok {
		return Toolchain{}, false
	}
	return ToolchainFromConfig(tcCfg), true
}
