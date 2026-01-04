// Package config provides a layered configuration system for Morphir tooling.
//
// # Overview
//
// The config package implements a hierarchical configuration system that loads
// settings from multiple sources with a clear priority order. Higher-priority
// sources override lower-priority ones, allowing users to customize behavior
// at different levels (system, user, project).
//
// # Configuration Sources
//
// Sources are loaded in the following order (lowest to highest priority):
//
//  1. Built-in defaults - Sensible defaults compiled into the application
//  2. System config - /etc/morphir/morphir.toml (Unix) or %PROGRAMDATA%\morphir\morphir.toml (Windows)
//  3. Global user config - ~/.config/morphir/morphir.toml (follows XDG spec)
//  4. Project config - morphir.toml or .morphir/morphir.toml in workspace root
//  5. User override - .morphir/morphir.user.toml (gitignored, user-specific)
//  6. Environment variables - MORPHIR_* prefix (highest priority)
//
// # Basic Usage
//
// Load configuration with defaults:
//
//	cfg, err := config.Load()
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Println("Log level:", cfg.Logging().Level())
//
// Load with options:
//
//	cfg, err := config.Load(
//	    config.WithWorkDir("/path/to/project"),
//	    config.WithoutEnv(),  // Ignore environment variables
//	)
//
// Get detailed information about loaded sources:
//
//	result, err := config.LoadWithDetails()
//	if err != nil {
//	    log.Fatal(err)
//	}
//	for _, src := range result.Sources() {
//	    if src.Loaded() {
//	        fmt.Printf("Loaded: %s from %s\n", src.Name(), src.Path())
//	    }
//	}
//	cfg := result.Config()
//
// # Configuration Sections
//
// The configuration is organized into logical sections:
//
//	[morphir]
//	version = "^3.0.0"           # Morphir IR version constraint
//
//	[workspace]
//	root = "."                   # Workspace root directory
//	output_dir = ".morphir"      # Output directory for artifacts
//
//	[ir]
//	format_version = 3           # IR format version (1-10)
//	strict_mode = false          # Enable strict IR validation
//
//	[codegen]
//	targets = ["go", "typescript"]  # Code generation targets
//	template_dir = ""            # Custom template directory
//	output_format = "pretty"     # Output format: pretty, compact, minified
//
//	[cache]
//	enabled = true               # Enable caching
//	dir = ""                     # Cache directory (empty = default)
//	max_size = 0                 # Max cache size in bytes (0 = unlimited)
//
//	[logging]
//	level = "info"               # Log level: debug, info, warn, error
//	format = "text"              # Log format: text, json
//	file = ""                    # Log file path (empty = stderr)
//
//	[ui]
//	color = true                 # Enable colored output
//	interactive = true           # Enable interactive mode
//	theme = "default"            # UI theme: default, light, dark
//
// # Environment Variables
//
// All configuration values can be overridden via environment variables using
// the MORPHIR_ prefix. Nested keys use underscores:
//
//	MORPHIR_LOGGING_LEVEL=debug      # Sets logging.level
//	MORPHIR_IR_FORMAT_VERSION=3      # Sets ir.format_version
//	MORPHIR_CACHE_ENABLED=false      # Sets cache.enabled
//
// # Validation
//
// Use ValidateMap to check a configuration map for errors and warnings:
//
//	result := config.ValidateMap(configMap)
//	if result.HasErrors() {
//	    for _, err := range result.Errors() {
//	        fmt.Printf("Error: %s: %s\n", err.Field(), err.Message())
//	    }
//	}
//	for _, warn := range result.Warnings() {
//	    fmt.Printf("Warning: %s: %s\n", warn.Field(), warn.Message())
//	}
//
// # Immutability
//
// All types in this package are immutable. Config values are accessed through
// getter methods, and slice accessors return defensive copies. This design
// ensures thread-safety and prevents accidental modification.
//
// # Functional Options Pattern
//
// Load functions use the functional options pattern for configuration:
//
//	cfg, err := config.Load(
//	    config.WithWorkDir("/path/to/project"),
//	    config.WithEnvPrefix("MYAPP"),
//	    config.WithoutSystem(),
//	    config.WithoutGlobal(),
//	)
//
// Available options:
//   - WithWorkDir(dir) - Set the working directory for discovery
//   - WithConfigPath(path) - Load from a specific config file
//   - WithEnvPrefix(prefix) - Set environment variable prefix
//   - WithoutSystem() - Skip system configuration
//   - WithoutGlobal() - Skip global user configuration
//   - WithoutProject() - Skip project configuration
//   - WithoutUser() - Skip user override configuration
//   - WithoutEnv() - Skip environment variables
package config
