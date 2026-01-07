package emitter

import (
	"fmt"
	"strings"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
)

// EmitPackage converts a domain.Package to WIT text format.
func EmitPackage(pkg domain.Package) string {
	var b strings.Builder

	// Package declaration
	b.WriteString("package ")
	b.WriteString(pkg.Ident())
	b.WriteString(";\n")

	// Interfaces
	for _, iface := range pkg.Interfaces {
		b.WriteString("\n")
		b.WriteString(emitInterface(iface, 0))
	}

	// Worlds
	for _, world := range pkg.Worlds {
		b.WriteString("\n")
		b.WriteString(emitWorld(world, 0))
	}

	return b.String()
}

// emitInterface converts a domain.Interface to WIT text.
func emitInterface(iface domain.Interface, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	// Documentation
	if !iface.Docs.IsEmpty() {
		b.WriteString(emitDocs(iface.Docs, indent))
	}

	b.WriteString(prefix)
	b.WriteString("interface ")
	b.WriteString(iface.Name.String())
	b.WriteString(" {\n")

	// Type definitions
	for _, td := range iface.Types {
		b.WriteString(emitTypeDef(td, indent+1))
		b.WriteString("\n")
	}

	// Functions
	for _, fn := range iface.Functions {
		b.WriteString(emitFunction(fn, indent+1))
		b.WriteString("\n")
	}

	b.WriteString(prefix)
	b.WriteString("}\n")

	return b.String()
}

// emitWorld converts a domain.World to WIT text.
func emitWorld(world domain.World, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	// Documentation
	if !world.Docs.IsEmpty() {
		b.WriteString(emitDocs(world.Docs, indent))
	}

	b.WriteString(prefix)
	b.WriteString("world ")
	b.WriteString(world.Name.String())
	b.WriteString(" {\n")

	// Imports
	for _, item := range world.Imports {
		b.WriteString(emitWorldItem("import", item, indent+1))
	}

	// Exports
	for _, item := range world.Exports {
		b.WriteString(emitWorldItem("export", item, indent+1))
	}

	b.WriteString(prefix)
	b.WriteString("}\n")

	return b.String()
}

// emitWorldItem converts a domain.WorldItem to WIT text.
func emitWorldItem(keyword string, item domain.WorldItem, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	switch v := item.(type) {
	case domain.InterfaceItem:
		b.WriteString(prefix)
		b.WriteString(keyword)
		b.WriteString(" ")
		b.WriteString(v.Name.String())
		// Handle inline vs external interface
		switch ref := v.Ref.(type) {
		case domain.InlineInterface:
			b.WriteString(": interface {\n")
			for _, td := range ref.Interface.Types {
				b.WriteString(emitTypeDef(td, indent+1))
				b.WriteString("\n")
			}
			for _, fn := range ref.Interface.Functions {
				b.WriteString(emitFunction(fn, indent+1))
				b.WriteString("\n")
			}
			b.WriteString(prefix)
			b.WriteString("}")
		case domain.ExternalInterfaceRef:
			b.WriteString(": ")
			b.WriteString(emitUsePath(ref.Path))
		}
		b.WriteString(";\n")
	case domain.FunctionItem:
		b.WriteString(prefix)
		b.WriteString(keyword)
		b.WriteString(" ")
		b.WriteString(emitFunctionSignature(v.Func))
		b.WriteString(";\n")
	}

	return b.String()
}

// emitTypeDef converts a domain.TypeDef to WIT text.
func emitTypeDef(td domain.TypeDef, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	// Documentation
	if !td.Docs.IsEmpty() {
		b.WriteString(emitDocs(td.Docs, indent))
	}

	switch kind := td.Kind.(type) {
	case domain.RecordDef:
		b.WriteString(prefix)
		b.WriteString("record ")
		b.WriteString(td.Name.String())
		b.WriteString(" {\n")
		for _, field := range kind.Fields {
			b.WriteString(emitField(field, indent+1))
		}
		b.WriteString(prefix)
		b.WriteString("}")

	case domain.VariantDef:
		b.WriteString(prefix)
		b.WriteString("variant ")
		b.WriteString(td.Name.String())
		b.WriteString(" {\n")
		for _, c := range kind.Cases {
			b.WriteString(emitVariantCase(c, indent+1))
		}
		b.WriteString(prefix)
		b.WriteString("}")

	case domain.EnumDef:
		b.WriteString(prefix)
		b.WriteString("enum ")
		b.WriteString(td.Name.String())
		b.WriteString(" {\n")
		for _, c := range kind.Cases {
			b.WriteString(strings.Repeat("    ", indent+1))
			b.WriteString(c.String())
			b.WriteString(",\n")
		}
		b.WriteString(prefix)
		b.WriteString("}")

	case domain.FlagsDef:
		b.WriteString(prefix)
		b.WriteString("flags ")
		b.WriteString(td.Name.String())
		b.WriteString(" {\n")
		for _, f := range kind.Flags {
			b.WriteString(strings.Repeat("    ", indent+1))
			b.WriteString(f.String())
			b.WriteString(",\n")
		}
		b.WriteString(prefix)
		b.WriteString("}")

	case domain.ResourceDef:
		b.WriteString(prefix)
		b.WriteString("resource ")
		b.WriteString(td.Name.String())
		if kind.Constructor != nil || len(kind.Methods) > 0 {
			b.WriteString(" {\n")
			if kind.Constructor != nil {
				b.WriteString(emitConstructor(*kind.Constructor, indent+1))
			}
			for _, m := range kind.Methods {
				b.WriteString(emitResourceMethod(m, indent+1))
			}
			b.WriteString(prefix)
			b.WriteString("}")
		}

	case domain.TypeAliasDef:
		b.WriteString(prefix)
		b.WriteString("type ")
		b.WriteString(td.Name.String())
		b.WriteString(" = ")
		b.WriteString(emitType(kind.Target))
		b.WriteString(";")
	}

	return b.String()
}

// emitField converts a domain.Field to WIT text.
func emitField(field domain.Field, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	if !field.Docs.IsEmpty() {
		b.WriteString(emitDocs(field.Docs, indent))
	}

	b.WriteString(prefix)
	b.WriteString(field.Name.String())
	b.WriteString(": ")
	b.WriteString(emitType(field.Type))
	b.WriteString(",\n")

	return b.String()
}

// emitVariantCase converts a domain.VariantCase to WIT text.
func emitVariantCase(c domain.VariantCase, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	if !c.Docs.IsEmpty() {
		b.WriteString(emitDocs(c.Docs, indent))
	}

	b.WriteString(prefix)
	b.WriteString(c.Name.String())
	if c.Payload != nil {
		b.WriteString("(")
		b.WriteString(emitType(*c.Payload))
		b.WriteString(")")
	}
	b.WriteString(",\n")

	return b.String()
}

// emitConstructor converts a domain.Constructor to WIT text.
func emitConstructor(c domain.Constructor, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	b.WriteString(prefix)
	b.WriteString("constructor(")
	b.WriteString(emitParams(c.Params))
	b.WriteString(");\n")

	return b.String()
}

// emitResourceMethod converts a domain.ResourceMethod to WIT text.
func emitResourceMethod(m domain.ResourceMethod, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	b.WriteString(prefix)
	if m.IsStatic {
		b.WriteString(m.Name.String())
		b.WriteString(": static ")
	} else {
		b.WriteString(m.Name.String())
		b.WriteString(": ")
	}
	b.WriteString("func(")
	b.WriteString(emitParams(m.Function.Params))
	b.WriteString(")")
	if len(m.Function.Results) > 0 {
		b.WriteString(" -> ")
		b.WriteString(emitResults(m.Function.Results))
	}
	b.WriteString(";\n")

	return b.String()
}

// emitFunction converts a domain.Function to WIT text.
func emitFunction(fn domain.Function, indent int) string {
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)

	if !fn.Docs.IsEmpty() {
		b.WriteString(emitDocs(fn.Docs, indent))
	}

	b.WriteString(prefix)
	b.WriteString(emitFunctionSignature(fn))
	b.WriteString(";")

	return b.String()
}

// emitFunctionSignature converts a function to its signature (name: func(...) -> ...).
func emitFunctionSignature(fn domain.Function) string {
	var b strings.Builder

	b.WriteString(fn.Name.String())
	b.WriteString(": func(")
	b.WriteString(emitParams(fn.Params))
	b.WriteString(")")

	if len(fn.Results) > 0 {
		b.WriteString(" -> ")
		b.WriteString(emitResults(fn.Results))
	}

	return b.String()
}

// emitParams converts a slice of domain.Param to WIT text.
func emitParams(params []domain.Param) string {
	parts := make([]string, len(params))
	for i, p := range params {
		if p.Name.String() != "" {
			parts[i] = p.Name.String() + ": " + emitType(p.Type)
		} else {
			parts[i] = emitType(p.Type)
		}
	}
	return strings.Join(parts, ", ")
}

// emitResults converts a slice of result types to WIT text.
func emitResults(results []domain.Type) string {
	if len(results) == 1 {
		return emitType(results[0])
	}
	// Multiple results need named tuple syntax
	parts := make([]string, len(results))
	for i, r := range results {
		parts[i] = emitType(r)
	}
	return "(" + strings.Join(parts, ", ") + ")"
}

// emitType converts a domain.Type to WIT text.
func emitType(t domain.Type) string {
	switch v := t.(type) {
	case domain.PrimitiveType:
		return emitPrimitiveType(v.Kind)
	case domain.NamedType:
		return v.Name.String()
	case domain.ListType:
		return "list<" + emitType(v.Element) + ">"
	case domain.OptionType:
		return "option<" + emitType(v.Inner) + ">"
	case domain.ResultType:
		return emitResultType(v)
	case domain.TupleType:
		return emitTupleType(v)
	case domain.HandleType:
		if v.IsBorrow {
			return "borrow<" + v.Resource.String() + ">"
		}
		return "own<" + v.Resource.String() + ">"
	case domain.FutureType:
		if v.Inner == nil {
			return "future"
		}
		return "future<" + emitType(*v.Inner) + ">"
	case domain.StreamType:
		if v.Element == nil {
			return "stream"
		}
		return "stream<" + emitType(*v.Element) + ">"
	default:
		return fmt.Sprintf("/* unknown type: %T */", t)
	}
}

// emitPrimitiveType converts a domain.PrimitiveKind to WIT text.
func emitPrimitiveType(kind domain.PrimitiveKind) string {
	switch kind {
	case domain.U8:
		return "u8"
	case domain.U16:
		return "u16"
	case domain.U32:
		return "u32"
	case domain.U64:
		return "u64"
	case domain.S8:
		return "s8"
	case domain.S16:
		return "s16"
	case domain.S32:
		return "s32"
	case domain.S64:
		return "s64"
	case domain.F32:
		return "f32"
	case domain.F64:
		return "f64"
	case domain.Bool:
		return "bool"
	case domain.Char:
		return "char"
	case domain.String:
		return "string"
	default:
		return "/* unknown primitive */"
	}
}

// emitResultType converts a domain.ResultType to WIT text.
func emitResultType(r domain.ResultType) string {
	if r.Ok == nil && r.Err == nil {
		return "result"
	}
	if r.Ok == nil {
		return "result<_, " + emitType(*r.Err) + ">"
	}
	if r.Err == nil {
		return "result<" + emitType(*r.Ok) + ">"
	}
	return "result<" + emitType(*r.Ok) + ", " + emitType(*r.Err) + ">"
}

// emitTupleType converts a domain.TupleType to WIT text.
func emitTupleType(t domain.TupleType) string {
	parts := make([]string, len(t.Types))
	for i, elem := range t.Types {
		parts[i] = emitType(elem)
	}
	return "tuple<" + strings.Join(parts, ", ") + ">"
}

// emitDocs converts documentation to WIT comments.
func emitDocs(docs domain.Documentation, indent int) string {
	if docs.IsEmpty() {
		return ""
	}
	var b strings.Builder
	prefix := strings.Repeat("    ", indent)
	for _, line := range docs.Lines() {
		b.WriteString(prefix)
		b.WriteString("/// ")
		b.WriteString(line)
		b.WriteString("\n")
	}
	return b.String()
}

// emitUsePath converts a UsePath to WIT text.
func emitUsePath(path domain.UsePath) string {
	switch p := path.(type) {
	case domain.LocalUsePath:
		return p.Interface.String()
	case domain.ExternalUsePath:
		var b strings.Builder
		b.WriteString(p.Namespace.String())
		b.WriteString(":")
		b.WriteString(p.Package.String())
		if p.Interface != nil {
			b.WriteString("/")
			b.WriteString(p.Interface.String())
		}
		if p.Version != nil {
			b.WriteString("@")
			b.WriteString(p.Version.String())
		}
		return b.String()
	default:
		return "/* unknown use path */"
	}
}
