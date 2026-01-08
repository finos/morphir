package domain

import (
	"bytes"
	"fmt"
	"go/format"
	"sort"
	"strings"
)

// EmitPackage generates Go source code from a GoPackage.
// Returns the generated source code as a string.
func EmitPackage(pkg GoPackage) (string, error) {
	var buf bytes.Buffer

	// Package declaration
	buf.WriteString("package ")
	buf.WriteString(pkg.Name)
	buf.WriteString("\n\n")

	// Package documentation
	if pkg.Documentation != "" {
		buf.WriteString("// ")
		buf.WriteString(strings.ReplaceAll(pkg.Documentation, "\n", "\n// "))
		buf.WriteString("\n\n")
	}

	// Imports
	if len(pkg.Imports) > 0 {
		buf.WriteString("import (\n")
		for _, imp := range pkg.Imports {
			if imp.Alias != "" {
				buf.WriteString("\t")
				buf.WriteString(imp.Alias)
				buf.WriteString(" ")
			} else {
				buf.WriteString("\t")
			}
			buf.WriteString("\"")
			buf.WriteString(imp.Path)
			buf.WriteString("\"\n")
		}
		buf.WriteString(")\n\n")
	}

	// Types
	for _, goType := range pkg.Types {
		typeCode := emitType(goType)
		buf.WriteString(typeCode)
		buf.WriteString("\n\n")
	}

	// Functions
	for _, fn := range pkg.Functions {
		fnCode := emitFunction(fn)
		buf.WriteString(fnCode)
		buf.WriteString("\n\n")
	}

	// Format the generated code with gofmt
	formatted, err := format.Source(buf.Bytes())
	if err != nil {
		// If formatting fails, return unformatted code with error
		return buf.String(), fmt.Errorf("failed to format Go code: %w", err)
	}

	return string(formatted), nil
}

func emitType(goType GoType) string {
	switch t := goType.(type) {
	case GoStructType:
		return emitStructType(t)
	case GoInterfaceType:
		return emitInterfaceType(t)
	case GoTypeAliasType:
		return emitTypeAlias(t)
	default:
		return fmt.Sprintf("// Unknown type: %T\n", goType)
	}
}

func emitStructType(s GoStructType) string {
	var buf bytes.Buffer

	// Documentation
	if s.Documentation != "" {
		buf.WriteString("// ")
		buf.WriteString(s.Name)
		buf.WriteString(" ")
		buf.WriteString(strings.ReplaceAll(s.Documentation, "\n", "\n// "))
		buf.WriteString("\n")
	}

	// Type declaration
	buf.WriteString("type ")
	buf.WriteString(s.Name)
	buf.WriteString(" struct {\n")

	// Fields
	for _, field := range s.Fields {
		if field.Documentation != "" {
			buf.WriteString("\t// ")
			buf.WriteString(strings.ReplaceAll(field.Documentation, "\n", "\n\t// "))
			buf.WriteString("\n")
		}
		buf.WriteString("\t")
		buf.WriteString(field.Name)
		buf.WriteString(" ")
		buf.WriteString(field.Type)
		if field.Tag != "" {
			buf.WriteString(" ")
			buf.WriteString(field.Tag)
		}
		buf.WriteString("\n")
	}

	buf.WriteString("}")

	// Methods
	for _, method := range s.Methods {
		buf.WriteString("\n\n")
		buf.WriteString(emitMethod(method))
	}

	return buf.String()
}

func emitInterfaceType(i GoInterfaceType) string {
	var buf bytes.Buffer

	// Documentation
	if i.Documentation != "" {
		buf.WriteString("// ")
		buf.WriteString(i.Name)
		buf.WriteString(" ")
		buf.WriteString(strings.ReplaceAll(i.Documentation, "\n", "\n// "))
		buf.WriteString("\n")
	}

	// Type declaration
	buf.WriteString("type ")
	buf.WriteString(i.Name)
	buf.WriteString(" interface {\n")

	// Methods
	for _, method := range i.Methods {
		if method.Documentation != "" {
			buf.WriteString("\t// ")
			buf.WriteString(strings.ReplaceAll(method.Documentation, "\n", "\n\t// "))
			buf.WriteString("\n")
		}
		buf.WriteString("\t")
		buf.WriteString(method.Name)
		buf.WriteString("(")
		buf.WriteString(formatParameters(method.Parameters))
		buf.WriteString(")")
		if len(method.Results) > 0 {
			buf.WriteString(" ")
			buf.WriteString(formatResults(method.Results))
		}
		buf.WriteString("\n")
	}

	buf.WriteString("}")
	return buf.String()
}

func emitTypeAlias(t GoTypeAliasType) string {
	var buf bytes.Buffer

	// Documentation
	if t.Documentation != "" {
		buf.WriteString("// ")
		buf.WriteString(t.Name)
		buf.WriteString(" ")
		buf.WriteString(strings.ReplaceAll(t.Documentation, "\n", "\n// "))
		buf.WriteString("\n")
	}

	// Type alias
	buf.WriteString("type ")
	buf.WriteString(t.Name)
	buf.WriteString(" = ")
	buf.WriteString(t.UnderlyingType)

	return buf.String()
}

func emitMethod(m GoMethod) string {
	var buf bytes.Buffer

	// Documentation
	if m.Signature.Documentation != "" {
		buf.WriteString("// ")
		buf.WriteString(m.Signature.Name)
		buf.WriteString(" ")
		buf.WriteString(strings.ReplaceAll(m.Signature.Documentation, "\n", "\n// "))
		buf.WriteString("\n")
	}

	// Method signature
	buf.WriteString("func (")
	buf.WriteString(m.Receiver.Name)
	buf.WriteString(" ")
	if m.Receiver.IsPointer {
		buf.WriteString("*")
	}
	buf.WriteString(m.Receiver.Type)
	buf.WriteString(") ")
	buf.WriteString(m.Signature.Name)
	buf.WriteString("(")
	buf.WriteString(formatParameters(m.Signature.Parameters))
	buf.WriteString(")")
	if len(m.Signature.Results) > 0 {
		buf.WriteString(" ")
		buf.WriteString(formatResults(m.Signature.Results))
	}
	buf.WriteString(" {\n")

	// Body
	buf.WriteString("\t")
	buf.WriteString(strings.ReplaceAll(m.Body, "\n", "\n\t"))
	buf.WriteString("\n}")

	return buf.String()
}

func emitFunction(fn GoFunction) string {
	var buf bytes.Buffer

	// Documentation
	if fn.Documentation != "" {
		buf.WriteString("// ")
		buf.WriteString(fn.Name)
		buf.WriteString(" ")
		buf.WriteString(strings.ReplaceAll(fn.Documentation, "\n", "\n// "))
		buf.WriteString("\n")
	}

	// Function signature
	buf.WriteString("func ")
	buf.WriteString(fn.Name)
	buf.WriteString("(")
	buf.WriteString(formatParameters(fn.Parameters))
	buf.WriteString(")")
	if len(fn.Results) > 0 {
		buf.WriteString(" ")
		buf.WriteString(formatResults(fn.Results))
	}
	buf.WriteString(" {\n")

	// Body
	buf.WriteString("\t")
	buf.WriteString(strings.ReplaceAll(fn.Body, "\n", "\n\t"))
	buf.WriteString("\n}")

	return buf.String()
}

func formatParameters(params []GoParameter) string {
	if len(params) == 0 {
		return ""
	}
	var parts []string
	for _, p := range params {
		if p.Name != "" {
			parts = append(parts, p.Name+" "+p.Type)
		} else {
			parts = append(parts, p.Type)
		}
	}
	return strings.Join(parts, ", ")
}

func formatResults(results []GoParameter) string {
	if len(results) == 0 {
		return ""
	}
	if len(results) == 1 {
		return results[0].Type
	}
	return "(" + formatParameters(results) + ")"
}

// EmitGoMod generates a go.mod file content.
func EmitGoMod(module GoModule) string {
	var buf bytes.Buffer

	buf.WriteString("module ")
	buf.WriteString(module.ModulePath)
	buf.WriteString("\n\n")

	buf.WriteString("go ")
	buf.WriteString(module.GoVersion)
	buf.WriteString("\n")

	if len(module.Dependencies) > 0 {
		buf.WriteString("\nrequire (\n")

		// Sort dependencies for deterministic output
		var deps []string
		for path := range module.Dependencies {
			deps = append(deps, path)
		}
		sort.Strings(deps)

		for _, path := range deps {
			version := module.Dependencies[path]
			buf.WriteString("\t")
			buf.WriteString(path)
			buf.WriteString(" ")
			buf.WriteString(version)
			buf.WriteString("\n")
		}
		buf.WriteString(")\n")
	}

	return buf.String()
}

// EmitGoWork generates a go.work file content.
func EmitGoWork(workspace GoWorkspace) string {
	var buf bytes.Buffer

	buf.WriteString("go ")
	buf.WriteString(workspace.GoVersion)
	buf.WriteString("\n\n")

	if len(workspace.Modules) > 0 {
		buf.WriteString("use (\n")
		for _, module := range workspace.Modules {
			// Extract relative path from module path
			// For now, use simple heuristic
			buf.WriteString("\t./")
			// This is simplified - proper implementation would calculate relative path
			buf.WriteString(module.ModulePath)
			buf.WriteString("\n")
		}
		buf.WriteString(")\n")
	}

	return buf.String()
}
