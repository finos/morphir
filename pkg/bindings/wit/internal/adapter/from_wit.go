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
