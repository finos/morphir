package domain

import (
	"fmt"
	"strings"

	"github.com/finos/morphir/pkg/models/ir"
)

// ConvertModuleToPackage converts a Morphir IR module to a Go package.
// This is the main entry point for IR to Go domain model conversion.
func ConvertModuleToPackage(module ir.ModuleDefinition[any, any], modulePath string, packageName string) (GoPackage, []string) {
	converter := &irConverter{
		modulePath:  modulePath,
		packageName: packageName,
		warnings:    []string{},
	}
	return converter.convertModule(module)
}

// irConverter handles conversion from Morphir IR to Go domain model.
type irConverter struct {
	modulePath  string
	packageName string
	warnings    []string
}

func (c *irConverter) addWarning(msg string) {
	c.warnings = append(c.warnings, msg)
}

func (c *irConverter) convertModule(module ir.ModuleDefinition[any, any]) (GoPackage, []string) {
	pkg := GoPackage{
		Name:       c.packageName,
		ImportPath: c.modulePath + "/" + c.packageName,
		Types:      []GoType{},
		Functions:  []GoFunction{},
		Imports:    []GoImport{},
	}

	// Add documentation
	if module.Doc() != nil {
		pkg.Documentation = *module.Doc()
	}

	// Convert types
	for _, modType := range module.Types() {
		if goType := c.convertType(modType); goType != nil {
			pkg.Types = append(pkg.Types, goType)
		}
	}

	// Convert values (functions)
	for _, modValue := range module.Values() {
		if fn := c.convertValue(modValue); fn != nil {
			pkg.Functions = append(pkg.Functions, *fn)
		}
	}

	return pkg, c.warnings
}

func (c *irConverter) convertType(modType ir.ModuleDefinitionType[any]) GoType {
	name := nameToString(modType.Name())
	def := modType.Definition()

	// Get documentation
	documented := def.Value()
	doc := documented.Doc()

	// Handle access control - only convert public types
	if def.Access() != ir.AccessPublic {
		return nil
	}

	typeDef := documented.Value()

	// Type switch on the type definition
	switch td := typeDef.(type) {
	case ir.TypeAliasDefinition[any]:
		return c.convertTypeAlias(name, doc, td)
	case ir.CustomTypeDefinition[any]:
		return c.convertCustomType(name, doc, td)
	default:
		c.addWarning(fmt.Sprintf("unsupported type definition for %s", name))
		return nil
	}
}

func (c *irConverter) convertTypeAlias(name string, doc string, alias ir.TypeAliasDefinition[any]) GoType {
	// Convert type expression to Go type string
	typeStr := c.convertTypeExpr(alias.Expression())

	return GoTypeAliasType{
		Name:           toExportedName(name),
		Documentation:  doc,
		UnderlyingType: typeStr,
	}
}

func (c *irConverter) convertCustomType(name string, doc string, custom ir.CustomTypeDefinition[any]) GoType {
	ctorsAC := custom.Constructors()
	ctors := ctorsAC.Value()

	// If single constructor with fields, generate a struct
	if len(ctors) == 1 {
		ctor := ctors[0]
		fields := c.convertConstructorFields(ctor)
		return GoStructType{
			Name:          toExportedName(name),
			Documentation: doc,
			Fields:        fields,
			Methods:       []GoMethod{},
		}
	}

	// Multiple constructors -> generate interface + types (sum type pattern)
	// For MVP, we'll generate a simple interface
	c.addWarning(fmt.Sprintf("sum types not fully supported yet for %s, generating interface", name))
	return GoInterfaceType{
		Name:          toExportedName(name),
		Documentation: doc,
		Methods:       []GoMethodSignature{{Name: "is" + toExportedName(name)}},
	}
}

func (c *irConverter) convertConstructorFields(ctor ir.TypeConstructor[any]) []GoField {
	var fields []GoField

	for _, arg := range ctor.Args() {
		fieldName := nameToString(arg.Name())
		fieldType := c.convertTypeExpr(arg.Type())

		fields = append(fields, GoField{
			Name:          toExportedName(fieldName),
			Type:          fieldType,
			Tag:           fmt.Sprintf("`json:\"%s\"`", fieldName),
			Documentation: "",
		})
	}

	return fields
}

func (c *irConverter) convertTypeExpr(typeExpr ir.Type[any]) string {
	switch t := typeExpr.(type) {
	case ir.TypeReference[any]:
		fqn := t.FullyQualifiedName()
		// Check if this is a Morphir SDK type and map to Go equivalent
		if goType := mapMorphirSDKType(fqn); goType != "" {
			return goType
		}
		// Extract local name from FQName
		localName := fqn.LocalName()
		return toExportedName(nameToString(localName))
	case ir.TypeVariable[any]:
		// Type variables -> interface{} or any for now
		return "any"
	case ir.TypeFunction[any]:
		// Function types -> func type
		return c.convertFunctionType(t)
	case ir.TypeTuple[any]:
		// Tuple types -> struct with numbered fields
		return c.convertTupleType(t)
	case ir.TypeRecord[any]:
		// Record types -> inline struct
		return c.convertRecordType(t)
	case ir.TypeUnit[any]:
		// Unit type -> struct{}
		return "struct{}"
	default:
		c.addWarning(fmt.Sprintf("unsupported type expression: %T", typeExpr))
		return "any"
	}
}

// mapMorphirSDKType maps Morphir SDK types to Go equivalents.
// Returns empty string if not a known SDK type.
func mapMorphirSDKType(fqn ir.FQName) string {
	// Get package path and local name
	packagePath := fqn.PackagePath()
	modulePath := fqn.ModulePath()
	localName := fqn.LocalName()

	// Convert paths to strings using TitleCase with dot separator
	nameToString := func(n ir.Name) string { return n.ToTitleCase() }
	packageStr := packagePath.ToString(nameToString, ".")
	moduleStr := modulePath.ToString(nameToString, ".")
	nameStr := localName.ToTitleCase()

	// Handle Morphir.SDK types
	if packageStr == "Morphir.SDK" || strings.HasPrefix(packageStr, "morphir") {
		switch moduleStr {
		case "Basics", "basics":
			return mapBasicsType(nameStr)
		case "String", "string":
			if nameStr == "String" {
				return "string"
			}
		case "Int", "int":
			if nameStr == "Int" {
				return "int"
			}
		case "Float", "float":
			if nameStr == "Float" {
				return "float64"
			}
		case "Bool", "bool":
			if nameStr == "Bool" {
				return "bool"
			}
		case "Char", "char":
			if nameStr == "Char" {
				return "rune"
			}
		case "List", "list":
			if nameStr == "List" {
				return "[]any" // Generic list - ideally would preserve element type
			}
		case "Dict", "dict":
			if nameStr == "Dict" {
				return "map[any]any" // Generic dict - ideally would preserve key/value types
			}
		case "Maybe", "maybe":
			if nameStr == "Maybe" {
				return "*any" // Pointer type for optional values
			}
		case "Result", "result":
			if nameStr == "Result" {
				return "any" // Result types need special handling
			}
		}
	}

	// Handle common SDK type patterns by local name alone (for simple cases)
	switch nameStr {
	case "String":
		return "string"
	case "Int", "Int32", "Int64":
		return "int"
	case "Float", "Float64":
		return "float64"
	case "Bool":
		return "bool"
	case "Char":
		return "rune"
	}

	return ""
}

// mapBasicsType maps Morphir.SDK.Basics types to Go equivalents.
func mapBasicsType(name string) string {
	switch name {
	case "Bool":
		return "bool"
	case "Int":
		return "int"
	case "Float":
		return "float64"
	case "String":
		return "string"
	case "Char":
		return "rune"
	case "Never":
		return "any" // Never type - should never be instantiated
	case "Order":
		return "int" // -1, 0, 1 for LT, EQ, GT
	default:
		return ""
	}
}

// convertFunctionType converts a function type to Go syntax.
func (c *irConverter) convertFunctionType(ft ir.TypeFunction[any]) string {
	argType := c.convertTypeExpr(ft.Argument())
	returnType := c.convertTypeExpr(ft.Result())
	return fmt.Sprintf("func(%s) %s", argType, returnType)
}

// convertTupleType converts a tuple type to a Go struct with numbered fields.
func (c *irConverter) convertTupleType(tt ir.TypeTuple[any]) string {
	elements := tt.Elements()
	if len(elements) == 0 {
		return "struct{}"
	}

	var fields []string
	for i, elem := range elements {
		elemType := c.convertTypeExpr(elem)
		fields = append(fields, fmt.Sprintf("V%d %s", i+1, elemType))
	}

	return fmt.Sprintf("struct { %s }", strings.Join(fields, "; "))
}

// convertRecordType converts a record type to a Go struct.
func (c *irConverter) convertRecordType(rt ir.TypeRecord[any]) string {
	fields := rt.Fields()
	if len(fields) == 0 {
		return "struct{}"
	}

	var fieldStrs []string
	for _, field := range fields {
		fieldName := toExportedName(nameToString(field.Name()))
		fieldType := c.convertTypeExpr(field.Type())
		fieldStrs = append(fieldStrs, fmt.Sprintf("%s %s", fieldName, fieldType))
	}

	return fmt.Sprintf("struct { %s }", strings.Join(fieldStrs, "; "))
}

func (c *irConverter) convertValue(modValue ir.ModuleDefinitionValue[any, any]) *GoFunction {
	name := nameToString(modValue.Name())
	def := modValue.Definition()

	// Only convert public values
	if def.Access() != ir.AccessPublic {
		return nil
	}

	// Get documentation
	documented := def.Value()
	doc := documented.Doc()

	// For MVP, generate stub functions
	// Full implementation would convert the function body
	c.addWarning(fmt.Sprintf("function body not yet implemented for %s", name))

	return &GoFunction{
		Name:          toExportedName(name),
		Parameters:    []GoParameter{}, // TODO: extract from value definition
		Results:       []GoParameter{{Type: "any"}},
		Body:          "panic(\"not implemented\")",
		Documentation: doc,
	}
}

// nameToString converts a Morphir Name to a string.
func nameToString(name ir.Name) string {
	return name.ToTitleCase()
}

// toExportedName ensures a name is exported (starts with uppercase).
func toExportedName(name string) string {
	if len(name) == 0 {
		return name
	}
	// Capitalize first letter
	return strings.ToUpper(name[:1]) + name[1:]
}
