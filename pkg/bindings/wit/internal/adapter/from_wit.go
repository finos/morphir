package adapter

import (
	"fmt"

	"github.com/Masterminds/semver/v3"
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"go.bytecodealliance.org/wit"
)

// FromWIT converts a bytecodealliance wit.Resolve to Morphir domain packages.
// Returns all packages found in the resolve and any warnings encountered.
func FromWIT(resolve *wit.Resolve) ([]domain.Package, []string, error) {
	if resolve == nil {
		return nil, nil, fmt.Errorf("resolve cannot be nil")
	}

	ctx := NewAdapterContext(resolve)
	packages := make([]domain.Package, 0, len(resolve.Packages))

	for _, witPkg := range resolve.Packages {
		if witPkg == nil {
			continue
		}

		pkg, err := adaptPackage(ctx, witPkg)
		if err != nil {
			return nil, ctx.Warnings, err
		}
		packages = append(packages, pkg)
	}

	return packages, ctx.Warnings, nil
}

// adaptPackage converts a wit.Package to domain.Package.
func adaptPackage(ctx *AdapterContext, witPkg *wit.Package) (domain.Package, error) {
	if witPkg.Name.Namespace == "" {
		return domain.Package{}, newValidationError("package", "package namespace is empty")
	}

	// Parse package identifier - wit.Ident has Namespace, Package fields
	namespace, err := domain.NewNamespace(witPkg.Name.Namespace)
	if err != nil {
		return domain.Package{}, newAdapterError("package namespace", witPkg.Name.String(), err)
	}

	pkgName, err := domain.NewPackageName(witPkg.Name.Package)
	if err != nil {
		return domain.Package{}, newAdapterError("package name", witPkg.Name.String(), err)
	}

	var version *semver.Version
	if witPkg.Name.Version != nil {
		version, err = semver.NewVersion(witPkg.Name.Version.String())
		if err != nil {
			return domain.Package{}, newAdapterError("package version", witPkg.Name.String(), err)
		}
	}

	// Adapt interfaces using ordered.Map.All()
	interfaces := make([]domain.Interface, 0, witPkg.Interfaces.Len())
	for ifaceName, witIface := range witPkg.Interfaces.All() {
		if witIface == nil {
			continue
		}
		iface, err := adaptInterface(ctx, ifaceName, witIface)
		if err != nil {
			return domain.Package{}, err
		}
		interfaces = append(interfaces, iface)
	}

	// Adapt worlds using ordered.Map.All()
	worlds := make([]domain.World, 0, witPkg.Worlds.Len())
	for worldName, witWorld := range witPkg.Worlds.All() {
		if witWorld == nil {
			continue
		}
		world, err := adaptWorld(ctx, worldName, witWorld)
		if err != nil {
			return domain.Package{}, err
		}
		worlds = append(worlds, world)
	}

	// TODO: Adapt top-level uses
	uses := make([]domain.Use, 0)

	// TODO: Extract documentation
	docs := domain.NewDocumentation("")

	return domain.Package{
		Namespace:  namespace,
		Name:       pkgName,
		Version:    version,
		Interfaces: interfaces,
		Worlds:     worlds,
		Uses:       uses,
		Docs:       docs,
	}, nil
}

// adaptInterface converts a wit.Interface to domain.Interface.
func adaptInterface(ctx *AdapterContext, name string, witIface *wit.Interface) (domain.Interface, error) {
	ifaceName, err := domain.NewIdentifier(name)
	if err != nil {
		return domain.Interface{}, newAdapterError("interface name", name, err)
	}

	// TODO: Adapt types
	types := make([]domain.TypeDef, 0)

	// TODO: Adapt functions
	functions := make([]domain.Function, 0)

	// TODO: Adapt uses
	uses := make([]domain.Use, 0)

	// TODO: Extract documentation
	docs := domain.NewDocumentation("")

	return domain.Interface{
		Name:      ifaceName,
		Types:     types,
		Functions: functions,
		Uses:      uses,
		Docs:      docs,
	}, nil
}

// adaptWorld converts a wit.World to domain.World.
func adaptWorld(ctx *AdapterContext, name string, witWorld *wit.World) (domain.World, error) {
	worldName, err := domain.NewIdentifier(name)
	if err != nil {
		return domain.World{}, newAdapterError("world name", name, err)
	}

	// TODO: Adapt imports
	imports := make([]domain.WorldItem, 0)

	// TODO: Adapt exports
	exports := make([]domain.WorldItem, 0)

	// TODO: Adapt uses
	uses := make([]domain.Use, 0)

	// TODO: Extract documentation
	docs := domain.NewDocumentation("")

	return domain.World{
		Name:    worldName,
		Imports: imports,
		Exports: exports,
		Uses:    uses,
		Docs:    docs,
	}, nil
}

// adaptType converts a wit.TypeDefKind to domain.Type.
// wit.TypeDefKind is the common interface for all WIT type constructs.
func adaptType(ctx *AdapterContext, kind wit.TypeDefKind) (domain.Type, error) {
	if kind == nil {
		return nil, newValidationError("type", "type cannot be nil")
	}

	// Check if this is a wit.Type (primitive type) using type assertion
	if witType, ok := kind.(wit.Type); ok {
		// WIT types use the TypeName() method to identify themselves
		typeName := witType.TypeName()

		switch typeName {
		// Primitive types
		case "bool":
			return domain.PrimitiveType{Kind: domain.Bool}, nil
		case "u8":
			return domain.PrimitiveType{Kind: domain.U8}, nil
		case "u16":
			return domain.PrimitiveType{Kind: domain.U16}, nil
		case "u32":
			return domain.PrimitiveType{Kind: domain.U32}, nil
		case "u64":
			return domain.PrimitiveType{Kind: domain.U64}, nil
		case "s8":
			return domain.PrimitiveType{Kind: domain.S8}, nil
		case "s16":
			return domain.PrimitiveType{Kind: domain.S16}, nil
		case "s32":
			return domain.PrimitiveType{Kind: domain.S32}, nil
		case "s64":
			return domain.PrimitiveType{Kind: domain.S64}, nil
		case "f32":
			return domain.PrimitiveType{Kind: domain.F32}, nil
		case "f64":
			return domain.PrimitiveType{Kind: domain.F64}, nil
		case "char":
			return domain.PrimitiveType{Kind: domain.Char}, nil
		case "string":
			return domain.PrimitiveType{Kind: domain.String}, nil
		}
	}

	// For composite types, delegate to adaptTypeDefKind
	return adaptTypeDefKind(ctx, kind)
}

// adaptTypeDefKind adapts a wit.TypeDefKind (the underlying type in a TypeDef).
func adaptTypeDefKind(ctx *AdapterContext, kind wit.TypeDefKind) (domain.Type, error) {
	if kind == nil {
		return nil, newValidationError("typedef kind", "kind cannot be nil")
	}

	// Use WITKind() to discriminate between different TypeDefKind variants
	witKind := kind.WITKind()

	switch witKind {
	// Primitive types (when encountered as TypeDefKind)
	case "bool", "u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "f32", "f64", "char", "string":
		// Check if it's also a wit.Type and extract TypeName
		if witType, ok := kind.(wit.Type); ok {
			typeName := witType.TypeName()
			switch typeName {
			case "bool":
				return domain.PrimitiveType{Kind: domain.Bool}, nil
			case "u8":
				return domain.PrimitiveType{Kind: domain.U8}, nil
			case "u16":
				return domain.PrimitiveType{Kind: domain.U16}, nil
			case "u32":
				return domain.PrimitiveType{Kind: domain.U32}, nil
			case "u64":
				return domain.PrimitiveType{Kind: domain.U64}, nil
			case "s8":
				return domain.PrimitiveType{Kind: domain.S8}, nil
			case "s16":
				return domain.PrimitiveType{Kind: domain.S16}, nil
			case "s32":
				return domain.PrimitiveType{Kind: domain.S32}, nil
			case "s64":
				return domain.PrimitiveType{Kind: domain.S64}, nil
			case "f32":
				return domain.PrimitiveType{Kind: domain.F32}, nil
			case "f64":
				return domain.PrimitiveType{Kind: domain.F64}, nil
			case "char":
				return domain.PrimitiveType{Kind: domain.Char}, nil
			case "string":
				return domain.PrimitiveType{Kind: domain.String}, nil
			}
		}

	case "list":
		// Cast to *wit.List using type assertion on the underlying interface
		if list, ok := kind.(*wit.List); ok {
			elem, err := adaptType(ctx, list.Type)
			if err != nil {
				return nil, newAdapterError("list element type", witKind, err)
			}
			return domain.ListType{Element: elem}, nil
		}

	case "option":
		if option, ok := kind.(*wit.Option); ok {
			inner, err := adaptType(ctx, option.Type)
			if err != nil {
				return nil, newAdapterError("option inner type", witKind, err)
			}
			return domain.OptionType{Inner: inner}, nil
		}

	case "result":
		if result, ok := kind.(*wit.Result); ok {
			var ok *domain.Type
			var errType *domain.Type

			if result.OK != nil {
				okType, err := adaptType(ctx, result.OK)
				if err != nil {
					return nil, newAdapterError("result ok type", witKind, err)
				}
				ok = &okType
			}

			if result.Err != nil {
				eType, err := adaptType(ctx, result.Err)
				if err != nil {
					return nil, newAdapterError("result err type", witKind, err)
				}
				errType = &eType
			}

			return domain.ResultType{Ok: ok, Err: errType}, nil
		}

	case "tuple":
		if tuple, ok := kind.(*wit.Tuple); ok {
			types := make([]domain.Type, 0, len(tuple.Types))
			for i, witElem := range tuple.Types {
				elem, err := adaptType(ctx, witElem)
				if err != nil {
					return nil, newAdapterError(fmt.Sprintf("tuple element %d", i), witKind, err)
				}
				types = append(types, elem)
			}
			return domain.TupleType{Types: types}, nil
		}

	case "type":
		// This is a TypeDef wrapping another type
		if typedef, ok := kind.(*wit.TypeDef); ok {
			// TypeDef represents a named type definition
			if typedef.Name == nil {
				ctx.AddWarning("encountered TypeDef without name, treating as inline definition")
				// Recursively adapt the underlying kind
				return adaptTypeDefKind(ctx, typedef.Kind)
			}

			name, err := domain.NewIdentifier(*typedef.Name)
			if err != nil {
				return nil, newAdapterError("type name", *typedef.Name, err)
			}
			return domain.NamedType{Name: name}, nil
		}

	// TODO: Handle record, variant, enum, flags, resource, handle when needed
	}

	// If we get here, it's an unsupported or unknown type kind
	ctx.AddWarning("encountered unsupported TypeDefKind: %s (%T)", witKind, kind)
	return nil, fmt.Errorf("unsupported TypeDefKind: %s (%T)", witKind, kind)
}
