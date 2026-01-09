package schema

import (
	"fmt"
	"strings"
)

// ValidLogLevels are the allowed values for logging.level.
var ValidLogLevels = []string{"debug", "info", "warn", "error"}

// ValidLogFormats are the allowed values for logging.format.
var ValidLogFormats = []string{"text", "json"}

// ValidUIThemes are the allowed values for ui.theme.
var ValidUIThemes = []string{"default", "light", "dark"}

// ValidCodegenFormats are the allowed values for codegen.output_format.
var ValidCodegenFormats = []string{"pretty", "compact", "minified"}

// MaxPathLength is the maximum allowed path length.
const MaxPathLength = 4096

// Validate validates a configuration map and returns all issues found.
func Validate(config map[string]any) *Result {
	result := NewResult()

	// Validate each section
	validateMorphirSection(config, result)
	validateWorkspaceSection(config, result)
	validateIRSection(config, result)
	validateCodegenSection(config, result)
	validateCacheSection(config, result)
	validateLoggingSection(config, result)
	validateUISection(config, result)
	validateWorkflowsSection(config, result)

	return result
}

// validateMorphirSection validates the [morphir] section.
func validateMorphirSection(config map[string]any, result *Result) {
	section, ok := config["morphir"].(map[string]any)
	if !ok {
		return // Section is optional
	}

	// Validate version if present
	if version, ok := section["version"].(string); ok {
		if version != "" && !isValidVersionConstraint(version) {
			result.AddWarning("morphir.version",
				fmt.Sprintf("version constraint %q may not be valid", version), version)
		}
	}
}

// validateWorkspaceSection validates the [workspace] section.
func validateWorkspaceSection(config map[string]any, result *Result) {
	section, ok := config["workspace"].(map[string]any)
	if !ok {
		return
	}

	// Validate root path
	if root, ok := section["root"].(string); ok {
		validatePath("workspace.root", root, result)
	}

	// Validate output_dir path
	if outputDir, ok := section["output_dir"].(string); ok {
		validatePath("workspace.output_dir", outputDir, result)
	}
}

// validateIRSection validates the [ir] section.
func validateIRSection(config map[string]any, result *Result) {
	section, ok := config["ir"].(map[string]any)
	if !ok {
		return
	}

	// Validate format_version
	if fv := section["format_version"]; fv != nil {
		version := getInt(fv)
		if version < 1 || version > 10 {
			result.AddWarning("ir.format_version",
				fmt.Sprintf("format version %d may not be supported (expected 1-10)", version), version)
		}
	}
}

// validateCodegenSection validates the [codegen] section.
func validateCodegenSection(config map[string]any, result *Result) {
	section, ok := config["codegen"].(map[string]any)
	if !ok {
		return
	}

	// Validate template_dir path
	if templateDir, ok := section["template_dir"].(string); ok {
		validatePath("codegen.template_dir", templateDir, result)
	}

	// Validate output_format
	if format, ok := section["output_format"].(string); ok {
		if !isOneOf(format, ValidCodegenFormats) {
			result.AddError("codegen.output_format",
				fmt.Sprintf("invalid output format %q, must be one of: %s",
					format, strings.Join(ValidCodegenFormats, ", ")), format)
		}
	}

	// Validate targets
	if targets := section["targets"]; targets != nil {
		validateTargets("codegen.targets", targets, result)
	}
}

// validateCacheSection validates the [cache] section.
func validateCacheSection(config map[string]any, result *Result) {
	section, ok := config["cache"].(map[string]any)
	if !ok {
		return
	}

	// Validate dir path
	if dir, ok := section["dir"].(string); ok {
		validatePath("cache.dir", dir, result)
	}

	// Validate max_size
	if maxSize := section["max_size"]; maxSize != nil {
		size := getInt64(maxSize)
		if size < 0 {
			result.AddError("cache.max_size",
				"max_size cannot be negative", size)
		}
	}
}

// validateLoggingSection validates the [logging] section.
func validateLoggingSection(config map[string]any, result *Result) {
	section, ok := config["logging"].(map[string]any)
	if !ok {
		return
	}

	// Validate level
	if level, ok := section["level"].(string); ok {
		if !isOneOf(level, ValidLogLevels) {
			result.AddError("logging.level",
				fmt.Sprintf("invalid log level %q, must be one of: %s",
					level, strings.Join(ValidLogLevels, ", ")), level)
		}
	}

	// Validate format
	if format, ok := section["format"].(string); ok {
		if !isOneOf(format, ValidLogFormats) {
			result.AddError("logging.format",
				fmt.Sprintf("invalid log format %q, must be one of: %s",
					format, strings.Join(ValidLogFormats, ", ")), format)
		}
	}

	// Validate file path
	if file, ok := section["file"].(string); ok {
		validatePath("logging.file", file, result)
	}
}

// validateUISection validates the [ui] section.
func validateUISection(config map[string]any, result *Result) {
	section, ok := config["ui"].(map[string]any)
	if !ok {
		return
	}

	// Validate theme
	if theme, ok := section["theme"].(string); ok {
		if !isOneOf(theme, ValidUIThemes) {
			result.AddWarning("ui.theme",
				fmt.Sprintf("unknown theme %q, using default (expected one of: %s)",
					theme, strings.Join(ValidUIThemes, ", ")), theme)
		}
	}
}

// validateWorkflowsSection validates the [workflows] section.
func validateWorkflowsSection(config map[string]any, result *Result) {
	rawSection, ok := config["workflows"]
	if rawSection == nil || !ok {
		return
	}

	section, ok := rawSection.(map[string]any)
	if !ok {
		result.AddError("workflows", "expected workflows to be a table", rawSection)
		return
	}

	for name, workflowValue := range section {
		workflowMap, ok := workflowValue.(map[string]any)
		if !ok {
			result.AddError(fmt.Sprintf("workflows.%s", name),
				"expected workflow definition to be a table", workflowValue)
			continue
		}

		if desc, ok := workflowMap["description"]; ok {
			if _, ok := desc.(string); !ok {
				result.AddError(fmt.Sprintf("workflows.%s.description", name),
					fmt.Sprintf("expected string, got %T", desc), desc)
			}
		}

		if extends, ok := workflowMap["extends"]; ok {
			if _, ok := extends.(string); !ok {
				result.AddError(fmt.Sprintf("workflows.%s.extends", name),
					fmt.Sprintf("expected string, got %T", extends), extends)
			}
		}

		if stages, ok := workflowMap["stages"]; ok {
			switch list := stages.(type) {
			case []any:
				for i, stage := range list {
					stageMap, ok := stage.(map[string]any)
					if !ok {
						result.AddError(fmt.Sprintf("workflows.%s.stages[%d]", name, i),
							fmt.Sprintf("expected table, got %T", stage), stage)
						continue
					}

					if stageName, ok := stageMap["name"]; ok {
						if s, ok := stageName.(string); ok {
							if s == "" {
								result.AddWarning(fmt.Sprintf("workflows.%s.stages[%d].name", name, i),
									"stage name should not be empty", stageName)
							}
						} else {
							result.AddError(fmt.Sprintf("workflows.%s.stages[%d].name", name, i),
								fmt.Sprintf("expected string, got %T", stageName), stageName)
						}
					} else {
						result.AddWarning(fmt.Sprintf("workflows.%s.stages[%d].name", name, i),
							"stage name is missing", nil)
					}

					if targets, ok := stageMap["targets"]; ok {
						validateTargets(fmt.Sprintf("workflows.%s.stages[%d].targets", name, i), targets, result)
					} else {
						result.AddWarning(fmt.Sprintf("workflows.%s.stages[%d].targets", name, i),
							"targets list is missing", nil)
					}

					if parallel, ok := stageMap["parallel"]; ok {
						if _, ok := parallel.(bool); !ok {
							result.AddError(fmt.Sprintf("workflows.%s.stages[%d].parallel", name, i),
								fmt.Sprintf("expected bool, got %T", parallel), parallel)
						}
					}

					if condition, ok := stageMap["condition"]; ok {
						if _, ok := condition.(string); !ok {
							result.AddError(fmt.Sprintf("workflows.%s.stages[%d].condition", name, i),
								fmt.Sprintf("expected string, got %T", condition), condition)
						}
					}
				}
			default:
				result.AddError(fmt.Sprintf("workflows.%s.stages", name),
					fmt.Sprintf("expected array of tables, got %T", stages), stages)
			}
		}
	}
}

// validatePath checks if a path is valid.
func validatePath(field, path string, result *Result) {
	if path == "" {
		return // Empty paths are allowed
	}

	// Check for null bytes
	if strings.ContainsRune(path, '\x00') {
		result.AddError(field, "path contains null bytes", path)
		return
	}

	// Check path length
	if len(path) > MaxPathLength {
		result.AddError(field,
			fmt.Sprintf("path exceeds maximum length of %d characters", MaxPathLength), path)
	}
}

// validateTargets checks if targets is a valid slice of strings.
func validateTargets(field string, targets any, result *Result) {
	switch v := targets.(type) {
	case []string:
		for i, target := range v {
			if target == "" {
				result.AddWarning(fmt.Sprintf("%s[%d]", field, i),
					"empty target string", target)
			}
		}
	case []any:
		for i, target := range v {
			if s, ok := target.(string); ok {
				if s == "" {
					result.AddWarning(fmt.Sprintf("%s[%d]", field, i),
						"empty target string", target)
				}
			} else {
				result.AddError(fmt.Sprintf("%s[%d]", field, i),
					fmt.Sprintf("expected string, got %T", target), target)
			}
		}
	default:
		result.AddError(field,
			fmt.Sprintf("expected array of strings, got %T", targets), targets)
	}
}

// isOneOf checks if a value is in the allowed list.
func isOneOf(value string, allowed []string) bool {
	for _, a := range allowed {
		if value == a {
			return true
		}
	}
	return false
}

// isValidVersionConstraint checks if a version constraint is valid.
// This is a simple check - real semver validation would be more complex.
func isValidVersionConstraint(version string) bool {
	// Allow common version patterns
	if version == "" {
		return true
	}
	// Simple check: should contain digits and possibly dots, comparators
	for _, c := range version {
		if !isVersionChar(c) {
			return false
		}
	}
	return true
}

// isVersionChar checks if a character is valid in a version string.
func isVersionChar(c rune) bool {
	return (c >= '0' && c <= '9') ||
		c == '.' ||
		c == '-' ||
		c == '+' ||
		c == '>' ||
		c == '<' ||
		c == '=' ||
		c == '^' ||
		c == '~' ||
		c == '*' ||
		c == ' ' ||
		c == ',' ||
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z')
}

// getInt converts various numeric types to int.
func getInt(v any) int {
	switch val := v.(type) {
	case int:
		return val
	case int64:
		return int(val)
	case float64:
		return int(val)
	}
	return 0
}

// getInt64 converts various numeric types to int64.
func getInt64(v any) int64 {
	switch val := v.(type) {
	case int64:
		return val
	case int:
		return int64(val)
	case float64:
		return int64(val)
	}
	return 0
}
