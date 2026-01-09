package config

import (
	"reflect"
	"testing"

	"github.com/finos/morphir/pkg/bindings/typemap"
)

func TestAccessorCoverage(t *testing.T) {
	workspace := WorkspaceSection{
		root:          "/workspace",
		outputDir:     "/workspace/out",
		members:       []string{"apps/*"},
		exclude:       []string{"**/vendor"},
		defaultMember: "apps/app",
	}
	codegen := CodegenSection{
		targets:      []string{"go"},
		templateDir:  "/templates",
		outputFormat: "pretty",
	}
	cache := CacheSection{enabled: true, dir: "/cache", maxSize: 1024}
	logging := LoggingSection{level: "debug", format: "json", file: "/logs/morphir.log"}
	ui := UISection{color: true, interactive: false, theme: "retro"}

	taskCommon := taskCommon{
		dependsOn: []string{"prep"},
		pre:       []string{"pre"},
		post:      []string{"post"},
		inputs:    []string{"input"},
		outputs:   []string{"output"},
		env:       map[string]string{"KEY": "VALUE"},
		mounts:    map[string]string{"src": "ro"},
	}
	intrinsic := IntrinsicTask{taskCommon: taskCommon, action: "compile"}
	intrinsic.isTask()
	command := CommandTask{taskCommon: taskCommon, cmd: []string{"go", "build"}}
	command.isTask()

	workflowStage := WorkflowStageConfig{
		name:      "build",
		targets:   []string{"go"},
		parallel:  true,
		condition: "on:ci",
	}
	workflow := WorkflowConfig{
		name:        "pipeline",
		description: "CI workflow",
		extends:     "base",
		stages:      []WorkflowStageConfig{workflowStage},
	}
	workflows := WorkflowsSection{definitions: map[string]WorkflowConfig{"pipeline": workflow}}

	toolchainTask := ToolchainTaskConfig{
		exec:     "morphir-elm",
		args:     []string{"make"},
		inputs:   InputsConfig{files: []string{"src/*.elm"}, artifacts: map[string]string{"ir": "@morphir-elm/make:ir"}},
		outputs:  map[string]OutputConfig{"ir": {path: "morphir-ir.json", typeVal: "morphir-ir"}},
		fulfills: []string{"make"},
		variants: []string{"Scala"},
		env:      map[string]string{"MODE": "ci"},
	}
	toolchain := ToolchainConfig{
		name:       "morphir-elm",
		version:    "2.0.0",
		acquire:    AcquireConfig{backend: "path", packageVal: "morphir-elm", version: "2.x", executable: "morphir-elm"},
		env:        map[string]string{"PATH": "/usr/bin"},
		workingDir: "/work",
		timeout:    "5m",
		tasks:      map[string]ToolchainTaskConfig{"make": toolchainTask},
	}
	toolchains := ToolchainsSection{definitions: map[string]ToolchainConfig{"morphir-elm": toolchain}}

	bindings := BindingsSection{
		wit: typemap.TypeMappingConfig{
			Primitives: []typemap.PrimitiveMappingConfig{
				{ExternalType: "u32", MorphirType: "Int", Bidirectional: true, Priority: 1},
			},
		},
	}

	cfg := Config{
		morphir:    MorphirSection{version: "3.0"},
		project:    ProjectSection{name: "proj", version: "1.0.0", sourceDirectory: "src", exposedModules: []string{"Foo"}, modulePrefix: "Prefix"},
		workspace:  workspace,
		ir:         IRSection{formatVersion: 3, strictMode: true},
		codegen:    codegen,
		cache:      cache,
		logging:    logging,
		ui:         ui,
		tasks:      TasksSection{definitions: map[string]Task{"build": intrinsic}},
		workflows:  workflows,
		bindings:   bindings,
		toolchains: toolchains,
	}

	if cfg.Project().Name() != "proj" {
		t.Fatalf("expected project name, got %q", cfg.Project().Name())
	}
	if cfg.Project().Version() != "1.0.0" {
		t.Fatalf("expected project version, got %q", cfg.Project().Version())
	}
	if cfg.Project().SourceDirectory() != "src" {
		t.Fatalf("expected source directory, got %q", cfg.Project().SourceDirectory())
	}
	if cfg.Project().ModulePrefix() != "Prefix" {
		t.Fatalf("expected module prefix, got %q", cfg.Project().ModulePrefix())
	}
	exposed := cfg.Project().ExposedModules()
	exposed[0] = "Changed"
	if cfg.project.exposedModules[0] == "Changed" {
		t.Fatal("expected exposed modules to return a defensive copy")
	}
	if cfg.Morphir().Version() != "3.0" {
		t.Fatalf("expected morphir version, got %q", cfg.Morphir().Version())
	}
	if cfg.Workspace().Root() != "/workspace" {
		t.Fatalf("expected workspace root, got %q", cfg.Workspace().Root())
	}
	if cfg.Workspace().DefaultMember() != "apps/app" {
		t.Fatalf("expected default member, got %q", cfg.Workspace().DefaultMember())
	}
	if cfg.IR().FormatVersion() != 3 || !cfg.IR().StrictMode() {
		t.Fatal("unexpected IR settings")
	}

	members := cfg.Workspace().Members()
	members[0] = "mutated"
	if workspace.members[0] == "mutated" {
		t.Fatal("expected workspace members to return a defensive copy")
	}
	exclude := cfg.Workspace().Exclude()
	exclude[0] = "changed"
	if workspace.exclude[0] == "changed" {
		t.Fatal("expected workspace exclude to return a defensive copy")
	}

	targets := cfg.Codegen().Targets()
	targets[0] = "changed"
	if codegen.targets[0] == "changed" {
		t.Fatal("expected codegen targets to return a defensive copy")
	}

	if !cfg.Cache().Enabled() || cfg.Cache().Dir() != "/cache" || cfg.Cache().MaxSize() != 1024 {
		t.Fatal("unexpected cache settings")
	}

	if cfg.Logging().Level() != "debug" || cfg.Logging().Format() != "json" || cfg.Logging().File() != "/logs/morphir.log" {
		t.Fatal("unexpected logging settings")
	}

	if cfg.UI().Color() != true || cfg.UI().Interactive() != false || cfg.UI().Theme() != "retro" {
		t.Fatal("unexpected UI settings")
	}

	if !reflect.DeepEqual(intrinsic.DependsOn(), []string{"prep"}) {
		t.Fatal("expected task dependsOn")
	}
	if intrinsic.Action() != "compile" {
		t.Fatalf("expected intrinsic action, got %q", intrinsic.Action())
	}
	if !reflect.DeepEqual(command.Cmd(), []string{"go", "build"}) {
		t.Fatal("expected command args")
	}

	if cfg.Tasks().Len() != 1 {
		t.Fatalf("expected 1 task, got %d", cfg.Tasks().Len())
	}
	taskNames := cfg.Tasks().Names()
	if len(taskNames) != 1 {
		t.Fatalf("expected task names, got %#v", taskNames)
	}
	if _, ok := cfg.Tasks().Get("build"); !ok {
		t.Fatal("expected task to be found")
	}

	if workflows.Len() != 1 {
		t.Fatalf("expected 1 workflow, got %d", workflows.Len())
	}
	names := workflows.Names()
	if len(names) != 1 || names[0] != "pipeline" {
		t.Fatalf("expected workflow names, got %#v", names)
	}
	loaded, ok := workflows.Get("pipeline")
	if !ok {
		t.Fatal("expected workflow to be found")
	}
	if loaded.Name() != "pipeline" || loaded.Description() != "CI workflow" || loaded.Extends() != "base" {
		t.Fatal("unexpected workflow fields")
	}
	stageTargets := loaded.Stages()[0].Targets()
	stageTargets[0] = "changed"
	if workflow.stages[0].targets[0] == "changed" {
		t.Fatal("expected workflow stage targets to return a defensive copy")
	}
	stage := loaded.Stages()[0]
	if stage.Name() != "build" || !stage.Parallel() || stage.Condition() != "on:ci" {
		t.Fatal("unexpected workflow stage fields")
	}

	if bindings.IsEmpty() {
		t.Fatal("expected bindings to be non-empty")
	}
	if bindings.WIT().IsEmpty() {
		t.Fatal("expected WIT mapping to be non-empty")
	}

	tc, ok := toolchains.Get("morphir-elm")
	if !ok || tc.Name() != "morphir-elm" || tc.Version() != "2.0.0" {
		t.Fatal("expected toolchain to be found")
	}
	if tc.Acquire().Executable() != "morphir-elm" || tc.Acquire().Package() != "morphir-elm" {
		t.Fatal("unexpected acquire config")
	}
	if tc.Tasks()["make"].Exec() != "morphir-elm" {
		t.Fatal("unexpected toolchain task exec")
	}
	if tc.WorkingDir() != "/work" || tc.Timeout() != "5m" {
		t.Fatal("unexpected toolchain settings")
	}
	taskCfg := tc.Tasks()["make"]
	if !reflect.DeepEqual(taskCfg.Args(), []string{"make"}) {
		t.Fatal("expected toolchain args")
	}
	if len(taskCfg.Inputs().Files()) != 1 {
		t.Fatal("expected toolchain input files")
	}
	if taskCfg.Inputs().Artifacts()["ir"] == "" {
		t.Fatal("expected toolchain input artifact")
	}
	if taskCfg.Outputs()["ir"].Path() != "morphir-ir.json" {
		t.Fatal("expected toolchain output path")
	}
	if !reflect.DeepEqual(taskCfg.Fulfills(), []string{"make"}) {
		t.Fatal("expected toolchain fulfills")
	}
	if !reflect.DeepEqual(taskCfg.Variants(), []string{"Scala"}) {
		t.Fatal("expected toolchain variants")
	}
	if taskCfg.Env()["MODE"] != "ci" {
		t.Fatal("expected toolchain env")
	}

	if toolchains.Len() != 1 {
		t.Fatalf("expected 1 toolchain, got %d", toolchains.Len())
	}
}
