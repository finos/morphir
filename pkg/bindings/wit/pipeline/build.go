package pipeline

import (
	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/pipeline"
)

// NewBuildStep creates the WIT "build" step (WIT → IR → WIT).
// This step combines the make and gen steps into a full pipeline,
// with round-trip validation.
func NewBuildStep() pipeline.Step[BuildInput, BuildOutput] {
	return pipeline.NewStep[BuildInput, BuildOutput](
		"wit-build",
		"Full WIT build pipeline (make + gen)",
		func(ctx pipeline.Context, in BuildInput) (BuildOutput, pipeline.StepResult) {
			var result pipeline.StepResult
			var output BuildOutput

			// 1. Run make step (WIT → IR)
			makeStep := NewMakeStep()
			makeInput := MakeInput{
				Source:   in.Source,
				FilePath: in.FilePath,
				Options:  in.MakeOptions,
			}
			makeOut, makeResult := makeStep.Execute(ctx, makeInput)
			output.Make = makeOut

			// Collect diagnostics from make step
			result.Diagnostics = append(result.Diagnostics, makeResult.Diagnostics...)

			// If make failed, return early
			if makeResult.Err != nil {
				result.Err = makeResult.Err
				return output, result
			}

			// 2. Run gen step (IR → WIT)
			genStep := NewGenStep()

			// Convert the module to any type for gen input
			// This is safe because gen doesn't use the type parameters
			anyModule := convertModuleToAny(makeOut.Module)

			genInput := GenInput{
				Module:     anyModule,
				OutputPath: in.OutputPath,
				Options:    in.GenOptions,
			}
			genOut, genResult := genStep.Execute(ctx, genInput)
			output.Gen = genOut

			// Collect diagnostics and artifacts from gen step
			result.Diagnostics = append(result.Diagnostics, genResult.Diagnostics...)
			result.Artifacts = append(result.Artifacts, genResult.Artifacts...)

			// If gen failed, return
			if genResult.Err != nil {
				result.Err = genResult.Err
				return output, result
			}

			// 3. Validate round-trip fidelity
			output.RoundTripValid = ValidateRoundTrip(
				output.Make.SourcePackage,
				output.Gen.Package,
			)

			if !output.RoundTripValid {
				result.Diagnostics = append(result.Diagnostics, RoundTripMismatch("wit-build"))
			}

			return output, result
		},
	)
}

// convertModuleToAny converts a strongly-typed ModuleDefinition to any type parameters.
// This is needed because the gen step accepts ModuleDefinition[any, any] to be
// flexible about the source of the IR.
func convertModuleToAny(module ir.ModuleDefinition[SourceLocation, SourceLocation]) ir.ModuleDefinition[any, any] {
	// Convert types
	var types []ir.ModuleDefinitionType[any]
	for _, t := range module.Types() {
		types = append(types, convertTypeToAny(t))
	}

	// Convert values
	var values []ir.ModuleDefinitionValue[any, any]
	for _, v := range module.Values() {
		values = append(values, convertValueToAny(v))
	}

	return ir.NewModuleDefinition(types, values, module.Doc())
}

// convertTypeToAny converts a ModuleDefinitionType to any type parameter.
func convertTypeToAny(t ir.ModuleDefinitionType[SourceLocation]) ir.ModuleDefinitionType[any] {
	// This is a placeholder - in practice we'd need to properly convert
	// the inner type structures. For now, we'll use type assertion.
	return ir.ModuleDefinitionTypeFromParts[any](
		t.Name(),
		convertTypeACL(t.Definition()),
	)
}

// convertValueToAny converts a ModuleDefinitionValue to any type parameters.
func convertValueToAny(v ir.ModuleDefinitionValue[SourceLocation, SourceLocation]) ir.ModuleDefinitionValue[any, any] {
	return ir.ModuleDefinitionValueFromParts[any, any](
		v.Name(),
		convertValueACL(v.Definition()),
	)
}

// convertTypeACL converts AccessControlled type to any.
func convertTypeACL(acl ir.AccessControlled[ir.Documented[ir.TypeDefinition[SourceLocation]]]) ir.AccessControlled[ir.Documented[ir.TypeDefinition[any]]] {
	documented := acl.Value()
	typeDef := documented.Value()

	// Convert the type definition
	var anyTypeDef ir.TypeDefinition[any]
	switch td := typeDef.(type) {
	case ir.TypeAliasDefinition[SourceLocation]:
		anyTypeDef = ir.NewTypeAliasDefinition[any](nil, convertTypeExprToAny(td.Expression()))
	case ir.CustomTypeDefinition[SourceLocation]:
		ctors := td.Constructors()
		if len(ctors.Value()) > 0 {
			anyTypeDef = ir.NewCustomTypeDefinition[any](nil, ir.NewAccessControlled(
				ctors.Access(),
				convertConstructorsToAny(ctors.Value()),
			))
		}
	default:
		// Fall back to nil for unknown types
		anyTypeDef = nil
	}

	anyDocumented := ir.NewDocumented(documented.Doc(), anyTypeDef)
	return ir.NewAccessControlled(acl.Access(), anyDocumented)
}

// convertValueACL converts AccessControlled value to any.
func convertValueACL(acl ir.AccessControlled[ir.Documented[ir.ValueDefinition[SourceLocation, SourceLocation]]]) ir.AccessControlled[ir.Documented[ir.ValueDefinition[any, any]]] {
	documented := acl.Value()
	valueDef := documented.Value()

	// Convert inputs
	var inputs []ir.ValueDefinitionInput[any, any]
	for _, input := range valueDef.InputTypes() {
		inputs = append(inputs, ir.ValueDefinitionInputFromParts[any, any](
			input.Name(),
			nil,
			convertTypeExprToAny(input.Type()),
		))
	}

	// Convert output
	outputType := convertTypeExprToAny(valueDef.OutputType())

	anyValueDef := ir.NewValueDefinition[any, any](inputs, outputType, nil)
	anyDocumented := ir.NewDocumented(documented.Doc(), anyValueDef)
	return ir.NewAccessControlled(acl.Access(), anyDocumented)
}

// convertConstructorsToAny converts TypeConstructors to any type parameter.
func convertConstructorsToAny(ctors ir.TypeConstructors[SourceLocation]) ir.TypeConstructors[any] {
	var result ir.TypeConstructors[any]
	for _, ctor := range ctors {
		var args ir.TypeConstructorArgs[any]
		for _, arg := range ctor.Args() {
			args = append(args, ir.TypeConstructorArgFromParts[any](
				arg.Name(),
				convertTypeExprToAny(arg.Type()),
			))
		}
		result = append(result, ir.TypeConstructorFromParts[any](ctor.Name(), args))
	}
	return result
}

// convertTypeExprToAny converts a Type expression to any type parameter.
func convertTypeExprToAny(t ir.Type[SourceLocation]) ir.Type[any] {
	if t == nil {
		return nil
	}

	switch ty := t.(type) {
	case ir.TypeReference[SourceLocation]:
		var params []ir.Type[any]
		for _, p := range ty.TypeParams() {
			params = append(params, convertTypeExprToAny(p))
		}
		return ir.NewTypeReference[any](nil, ty.FullyQualifiedName(), params)

	case ir.TypeVariable[SourceLocation]:
		return ir.NewTypeVariable[any](nil, ty.Name())

	case ir.TypeRecord[SourceLocation]:
		var fields []ir.Field[any]
		for _, f := range ty.Fields() {
			fields = append(fields, ir.FieldFromParts[any](f.Name(), convertTypeExprToAny(f.Type())))
		}
		return ir.NewTypeRecord[any](nil, fields)

	case ir.TypeTuple[SourceLocation]:
		var elements []ir.Type[any]
		for _, elem := range ty.Elements() {
			elements = append(elements, convertTypeExprToAny(elem))
		}
		return ir.NewTypeTuple[any](nil, elements)

	case ir.TypeUnit[SourceLocation]:
		return ir.NewTypeUnit[any](nil)

	default:
		return nil
	}
}
