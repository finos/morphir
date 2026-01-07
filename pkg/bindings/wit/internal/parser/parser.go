package parser

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/Masterminds/semver/v3"
	"github.com/finos/morphir/pkg/bindings/wit/domain"
)

// Parser parses WIT source code into domain types.
type Parser struct {
	lexer   *Lexer
	current Token
	peek    Token
	errors  []error
}

// NewParser creates a new parser for the given input.
func NewParser(input string) *Parser {
	p := &Parser{
		lexer:  NewLexer(input),
		errors: []error{},
	}
	// Prime the parser with two tokens
	p.advance()
	p.advance()
	return p
}

// Parse parses the input and returns a Package.
func (p *Parser) Parse() (domain.Package, error) {
	pkg, err := p.parsePackage()
	if err != nil {
		return domain.Package{}, err
	}

	if len(p.errors) > 0 {
		return pkg, p.errors[0]
	}

	return pkg, nil
}

// parsePackage parses a WIT package.
func (p *Parser) parsePackage() (domain.Package, error) {
	pkg := domain.Package{
		Interfaces: []domain.Interface{},
		Worlds:     []domain.World{},
		Uses:       []domain.Use{},
		Docs:       domain.NewDocumentation(""),
	}

	// Parse optional package declaration
	if p.check(TokenPackage) {
		ns, name, version, err := p.parsePackageDecl()
		if err != nil {
			return pkg, err
		}
		pkg.Namespace = ns
		pkg.Name = name
		pkg.Version = version
	}

	// Parse package items (interfaces, worlds, use statements)
	for !p.check(TokenEOF) {
		if p.check(TokenInterface) {
			iface, err := p.parseInterface()
			if err != nil {
				return pkg, err
			}
			pkg.Interfaces = append(pkg.Interfaces, iface)
		} else if p.check(TokenWorld) {
			world, err := p.parseWorld()
			if err != nil {
				return pkg, err
			}
			pkg.Worlds = append(pkg.Worlds, world)
		} else if p.check(TokenUse) {
			// Top-level use statement - skip for now
			p.skipUntil(TokenSemicolon)
			p.advance() // consume ;
		} else {
			return pkg, p.errorf("unexpected token %s, expected interface, world, or use", p.current.Kind)
		}
	}

	return pkg, nil
}

// parsePackageDecl parses: package namespace:name@version;
func (p *Parser) parsePackageDecl() (domain.Namespace, domain.PackageName, *semver.Version, error) {
	if err := p.expect(TokenPackage); err != nil {
		return domain.Namespace{}, domain.PackageName{}, nil, err
	}

	// Parse namespace:name with possible /path segments
	// Format: (id:)+id(/id)*(@semver)?
	var parts []string

	// First identifier
	if !p.check(TokenIdent) {
		return domain.Namespace{}, domain.PackageName{}, nil, p.errorf("expected identifier, got %s", p.current.Kind)
	}
	parts = append(parts, p.current.Value)
	p.advance()

	// Expect : after namespace
	if err := p.expect(TokenColon); err != nil {
		return domain.Namespace{}, domain.PackageName{}, nil, err
	}

	// Package name
	if !p.check(TokenIdent) {
		return domain.Namespace{}, domain.PackageName{}, nil, p.errorf("expected package name, got %s", p.current.Kind)
	}
	pkgNameStr := p.current.Value
	p.advance()

	// Optional /path segments (we'll ignore these for now as they're for nested packages)
	for p.check(TokenSlash) {
		p.advance()
		if !p.check(TokenIdent) {
			return domain.Namespace{}, domain.PackageName{}, nil, p.errorf("expected identifier after /, got %s", p.current.Kind)
		}
		// For now, just take the last part as the package name
		pkgNameStr = p.current.Value
		p.advance()
	}

	// Optional @version
	var version *semver.Version
	if p.check(TokenAt) {
		p.advance()
		// Parse semver: major.minor.patch
		verStr, err := p.parseSemver()
		if err != nil {
			return domain.Namespace{}, domain.PackageName{}, nil, err
		}
		version, err = semver.NewVersion(verStr)
		if err != nil {
			return domain.Namespace{}, domain.PackageName{}, nil, fmt.Errorf("invalid semver %q: %w", verStr, err)
		}
	}

	if err := p.expect(TokenSemicolon); err != nil {
		return domain.Namespace{}, domain.PackageName{}, nil, err
	}

	namespace, err := domain.NewNamespace(parts[0])
	if err != nil {
		return domain.Namespace{}, domain.PackageName{}, nil, fmt.Errorf("invalid namespace %q: %w", parts[0], err)
	}

	pkgName, err := domain.NewPackageName(pkgNameStr)
	if err != nil {
		return domain.Namespace{}, domain.PackageName{}, nil, fmt.Errorf("invalid package name %q: %w", pkgNameStr, err)
	}

	return namespace, pkgName, version, nil
}

// parseSemver parses a semantic version: major.minor.patch
func (p *Parser) parseSemver() (string, error) {
	var parts []string

	// Major version
	if !p.check(TokenInteger) && !p.check(TokenIdent) {
		return "", p.errorf("expected version number, got %s", p.current.Kind)
	}
	parts = append(parts, p.current.Value)
	p.advance()

	// .minor
	if p.check(TokenDot) {
		p.advance()
		if !p.check(TokenInteger) && !p.check(TokenIdent) {
			return "", p.errorf("expected minor version, got %s", p.current.Kind)
		}
		parts = append(parts, p.current.Value)
		p.advance()

		// .patch
		if p.check(TokenDot) {
			p.advance()
			if !p.check(TokenInteger) && !p.check(TokenIdent) {
				return "", p.errorf("expected patch version, got %s", p.current.Kind)
			}
			parts = append(parts, p.current.Value)
			p.advance()
		}
	}

	return strings.Join(parts, "."), nil
}

// parseInterface parses: interface name { ... }
func (p *Parser) parseInterface() (domain.Interface, error) {
	iface := domain.Interface{
		Types:     []domain.TypeDef{},
		Functions: []domain.Function{},
		Uses:      []domain.Use{},
		Docs:      domain.NewDocumentation(""),
	}

	if err := p.expect(TokenInterface); err != nil {
		return iface, err
	}

	// Interface name
	if !p.check(TokenIdent) {
		return iface, p.errorf("expected interface name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return iface, fmt.Errorf("invalid interface name %q: %w", p.current.Value, err)
	}
	iface.Name = name
	p.advance()

	if err := p.expect(TokenLBrace); err != nil {
		return iface, err
	}

	// Parse interface items
	for !p.check(TokenRBrace) && !p.check(TokenEOF) {
		item, err := p.parseInterfaceItem()
		if err != nil {
			return iface, err
		}

		switch v := item.(type) {
		case domain.TypeDef:
			iface.Types = append(iface.Types, v)
		case domain.Function:
			iface.Functions = append(iface.Functions, v)
		case domain.Use:
			iface.Uses = append(iface.Uses, v)
		}
	}

	if err := p.expect(TokenRBrace); err != nil {
		return iface, err
	}

	return iface, nil
}

// parseInterfaceItem parses a single item inside an interface.
func (p *Parser) parseInterfaceItem() (any, error) {
	// Handle % prefix for escaped keywords
	if p.check(TokenPercent) {
		p.advance()
	}

	switch {
	case p.check(TokenType):
		return p.parseTypeAlias()
	case p.check(TokenRecord):
		return p.parseRecord()
	case p.check(TokenVariant):
		return p.parseVariant()
	case p.check(TokenEnum):
		return p.parseEnum()
	case p.check(TokenFlags):
		return p.parseFlags()
	case p.check(TokenResource):
		return p.parseResource()
	case p.check(TokenUse):
		return p.parseUse()
	case p.check(TokenIdent):
		// Function: name: func(...)
		return p.parseFunction()
	default:
		return nil, p.errorf("unexpected token %s in interface", p.current.Kind)
	}
}

// parseTypeAlias parses: type name = type;
func (p *Parser) parseTypeAlias() (domain.TypeDef, error) {
	td := domain.TypeDef{
		Docs: domain.NewDocumentation(""),
	}

	if err := p.expect(TokenType); err != nil {
		return td, err
	}

	// Name
	if !p.check(TokenIdent) {
		return td, p.errorf("expected type name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return td, fmt.Errorf("invalid type name %q: %w", p.current.Value, err)
	}
	td.Name = name
	p.advance()

	if err := p.expect(TokenEqual); err != nil {
		return td, err
	}

	// Target type
	targetType, err := p.parseType()
	if err != nil {
		return td, err
	}
	td.Kind = domain.TypeAliasDef{Target: targetType}

	if err := p.expect(TokenSemicolon); err != nil {
		return td, err
	}

	return td, nil
}

// parseRecord parses: record name { field: type, ... }
func (p *Parser) parseRecord() (domain.TypeDef, error) {
	td := domain.TypeDef{
		Docs: domain.NewDocumentation(""),
	}

	if err := p.expect(TokenRecord); err != nil {
		return td, err
	}

	// Name
	if !p.check(TokenIdent) {
		return td, p.errorf("expected record name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return td, fmt.Errorf("invalid record name %q: %w", p.current.Value, err)
	}
	td.Name = name
	p.advance()

	if err := p.expect(TokenLBrace); err != nil {
		return td, err
	}

	// Parse fields
	fields := []domain.Field{}
	for !p.check(TokenRBrace) && !p.check(TokenEOF) {
		field, err := p.parseField()
		if err != nil {
			return td, err
		}
		fields = append(fields, field)
	}

	if err := p.expect(TokenRBrace); err != nil {
		return td, err
	}

	td.Kind = domain.RecordDef{Fields: fields}
	return td, nil
}

// parseField parses: name: type,
func (p *Parser) parseField() (domain.Field, error) {
	field := domain.Field{
		Docs: domain.NewDocumentation(""),
	}

	// Handle % prefix for escaped keywords
	if p.check(TokenPercent) {
		p.advance()
		// After %, the next token is the escaped keyword used as identifier
		nameStr := p.getIdentifierOrKeyword()
		if nameStr == "" {
			return field, p.errorf("expected identifier after %%, got %s", p.current.Kind)
		}
		name, err := domain.NewIdentifier(nameStr)
		if err != nil {
			return field, fmt.Errorf("invalid field name %q: %w", nameStr, err)
		}
		field.Name = name
		p.advance()
	} else {
		// Field name (identifier or keyword used as name)
		nameStr := p.getIdentifierOrKeyword()
		if nameStr == "" {
			return field, p.errorf("expected field name, got %s", p.current.Kind)
		}
		name, err := domain.NewIdentifier(nameStr)
		if err != nil {
			return field, fmt.Errorf("invalid field name %q: %w", nameStr, err)
		}
		field.Name = name
		p.advance()
	}

	if err := p.expect(TokenColon); err != nil {
		return field, err
	}

	// Field type
	fieldType, err := p.parseType()
	if err != nil {
		return field, err
	}
	field.Type = fieldType

	// Expect comma (required in WIT)
	if err := p.expect(TokenComma); err != nil {
		return field, err
	}

	return field, nil
}

// parseVariant parses: variant name { case, case(type), ... }
func (p *Parser) parseVariant() (domain.TypeDef, error) {
	td := domain.TypeDef{
		Docs: domain.NewDocumentation(""),
	}

	if err := p.expect(TokenVariant); err != nil {
		return td, err
	}

	// Name (can be an identifier or a keyword used as name)
	nameStr := p.getIdentifierOrKeyword()
	if nameStr == "" {
		return td, p.errorf("expected variant name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(nameStr)
	if err != nil {
		return td, fmt.Errorf("invalid variant name %q: %w", nameStr, err)
	}
	td.Name = name
	p.advance()

	if err := p.expect(TokenLBrace); err != nil {
		return td, err
	}

	// Parse cases
	cases := []domain.VariantCase{}
	for !p.check(TokenRBrace) && !p.check(TokenEOF) {
		vc, err := p.parseVariantCase()
		if err != nil {
			return td, err
		}
		cases = append(cases, vc)
	}

	if err := p.expect(TokenRBrace); err != nil {
		return td, err
	}

	td.Kind = domain.VariantDef{Cases: cases}
	return td, nil
}

// parseVariantCase parses: name or name(type),
func (p *Parser) parseVariantCase() (domain.VariantCase, error) {
	vc := domain.VariantCase{
		Docs: domain.NewDocumentation(""),
	}

	// Case name
	if !p.check(TokenIdent) {
		return vc, p.errorf("expected variant case name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return vc, fmt.Errorf("invalid variant case name %q: %w", p.current.Value, err)
	}
	vc.Name = name
	p.advance()

	// Optional payload
	if p.check(TokenLParen) {
		p.advance()
		payloadType, err := p.parseType()
		if err != nil {
			return vc, err
		}
		vc.Payload = &payloadType
		if err := p.expect(TokenRParen); err != nil {
			return vc, err
		}
	}

	// Expect comma
	if err := p.expect(TokenComma); err != nil {
		return vc, err
	}

	return vc, nil
}

// parseEnum parses: enum name { case, ... }
func (p *Parser) parseEnum() (domain.TypeDef, error) {
	td := domain.TypeDef{
		Docs: domain.NewDocumentation(""),
	}

	if err := p.expect(TokenEnum); err != nil {
		return td, err
	}

	// Name
	if !p.check(TokenIdent) {
		return td, p.errorf("expected enum name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return td, fmt.Errorf("invalid enum name %q: %w", p.current.Value, err)
	}
	td.Name = name
	p.advance()

	if err := p.expect(TokenLBrace); err != nil {
		return td, err
	}

	// Parse cases
	cases := []domain.Identifier{}
	for !p.check(TokenRBrace) && !p.check(TokenEOF) {
		if !p.check(TokenIdent) {
			return td, p.errorf("expected enum case, got %s", p.current.Kind)
		}
		caseName, err := domain.NewIdentifier(p.current.Value)
		if err != nil {
			return td, fmt.Errorf("invalid enum case %q: %w", p.current.Value, err)
		}
		cases = append(cases, caseName)
		p.advance()

		// Expect comma
		if err := p.expect(TokenComma); err != nil {
			return td, err
		}
	}

	if err := p.expect(TokenRBrace); err != nil {
		return td, err
	}

	td.Kind = domain.EnumDef{Cases: cases}
	return td, nil
}

// parseFlags parses: flags name { flag, ... }
func (p *Parser) parseFlags() (domain.TypeDef, error) {
	td := domain.TypeDef{
		Docs: domain.NewDocumentation(""),
	}

	if err := p.expect(TokenFlags); err != nil {
		return td, err
	}

	// Name
	if !p.check(TokenIdent) {
		return td, p.errorf("expected flags name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return td, fmt.Errorf("invalid flags name %q: %w", p.current.Value, err)
	}
	td.Name = name
	p.advance()

	if err := p.expect(TokenLBrace); err != nil {
		return td, err
	}

	// Parse flags
	flags := []domain.Identifier{}
	for !p.check(TokenRBrace) && !p.check(TokenEOF) {
		if !p.check(TokenIdent) {
			return td, p.errorf("expected flag name, got %s", p.current.Kind)
		}
		flagName, err := domain.NewIdentifier(p.current.Value)
		if err != nil {
			return td, fmt.Errorf("invalid flag name %q: %w", p.current.Value, err)
		}
		flags = append(flags, flagName)
		p.advance()

		// Expect comma
		if err := p.expect(TokenComma); err != nil {
			return td, err
		}
	}

	if err := p.expect(TokenRBrace); err != nil {
		return td, err
	}

	td.Kind = domain.FlagsDef{Flags: flags}
	return td, nil
}

// parseResource parses: resource name { ... }
func (p *Parser) parseResource() (domain.TypeDef, error) {
	td := domain.TypeDef{
		Docs: domain.NewDocumentation(""),
	}

	if err := p.expect(TokenResource); err != nil {
		return td, err
	}

	// Name
	if !p.check(TokenIdent) {
		return td, p.errorf("expected resource name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return td, fmt.Errorf("invalid resource name %q: %w", p.current.Value, err)
	}
	td.Name = name
	p.advance()

	resourceDef := domain.ResourceDef{
		Methods: []domain.ResourceMethod{},
	}

	// Check for empty resource (just ;) or resource with body { ... }
	if p.check(TokenSemicolon) {
		p.advance()
		td.Kind = resourceDef
		return td, nil
	}

	if err := p.expect(TokenLBrace); err != nil {
		return td, err
	}

	// Parse resource methods
	for !p.check(TokenRBrace) && !p.check(TokenEOF) {
		// Handle % prefix for escaped keywords
		if p.check(TokenPercent) {
			p.advance()
		}

		if p.check(TokenConstructor) {
			constructor, err := p.parseConstructor()
			if err != nil {
				return td, err
			}
			resourceDef.Constructor = &constructor
		} else if p.check(TokenIdent) || isBuiltinType(p.current.Kind) {
			method, err := p.parseResourceMethod()
			if err != nil {
				return td, err
			}
			resourceDef.Methods = append(resourceDef.Methods, method)
		} else {
			return td, p.errorf("unexpected token %s in resource", p.current.Kind)
		}
	}

	if err := p.expect(TokenRBrace); err != nil {
		return td, err
	}

	td.Kind = resourceDef
	return td, nil
}

// parseConstructor parses: constructor(params);
func (p *Parser) parseConstructor() (domain.Constructor, error) {
	if err := p.expect(TokenConstructor); err != nil {
		return domain.Constructor{}, err
	}

	params, err := p.parseParamList()
	if err != nil {
		return domain.Constructor{}, err
	}

	if err := p.expect(TokenSemicolon); err != nil {
		return domain.Constructor{}, err
	}

	return domain.Constructor{Params: params}, nil
}

// parseResourceMethod parses: name: [static] func(...) -> ...;
func (p *Parser) parseResourceMethod() (domain.ResourceMethod, error) {
	method := domain.ResourceMethod{}

	// Method name
	methodName, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return method, fmt.Errorf("invalid method name %q: %w", p.current.Value, err)
	}
	method.Name = methodName
	p.advance()

	if err := p.expect(TokenColon); err != nil {
		return method, err
	}

	// Check for static
	if p.check(TokenStatic) {
		method.IsStatic = true
		p.advance()
	}

	// Parse function type
	fn, err := p.parseFuncType()
	if err != nil {
		return method, err
	}
	method.Function = fn

	if err := p.expect(TokenSemicolon); err != nil {
		return method, err
	}

	return method, nil
}

// parseFunction parses: name: func(params) -> result;
func (p *Parser) parseFunction() (domain.Function, error) {
	fn := domain.Function{
		Params:  []domain.Param{},
		Results: []domain.Type{},
		Docs:    domain.NewDocumentation(""),
	}

	// Function name
	if !p.check(TokenIdent) {
		return fn, p.errorf("expected function name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return fn, fmt.Errorf("invalid function name %q: %w", p.current.Value, err)
	}
	fn.Name = name
	p.advance()

	if err := p.expect(TokenColon); err != nil {
		return fn, err
	}

	// Parse function type
	fnType, err := p.parseFuncType()
	if err != nil {
		return fn, err
	}
	fn.Params = fnType.Params
	fn.Results = fnType.Results
	fn.IsAsync = fnType.IsAsync

	if err := p.expect(TokenSemicolon); err != nil {
		return fn, err
	}

	return fn, nil
}

// parseFuncType parses: [async] func(params) [-> result]
func (p *Parser) parseFuncType() (domain.Function, error) {
	fn := domain.Function{
		Params:  []domain.Param{},
		Results: []domain.Type{},
	}

	// Optional async
	if p.check(TokenAsync) {
		fn.IsAsync = true
		p.advance()
	}

	if err := p.expect(TokenFunc); err != nil {
		return fn, err
	}

	// Parameters
	params, err := p.parseParamList()
	if err != nil {
		return fn, err
	}
	fn.Params = params

	// Optional result
	if p.check(TokenArrow) {
		p.advance()
		resultType, err := p.parseType()
		if err != nil {
			return fn, err
		}
		fn.Results = []domain.Type{resultType}
	}

	return fn, nil
}

// parseParamList parses: (param: type, ...)
func (p *Parser) parseParamList() ([]domain.Param, error) {
	params := []domain.Param{}

	if err := p.expect(TokenLParen); err != nil {
		return nil, err
	}

	for !p.check(TokenRParen) && !p.check(TokenEOF) {
		param, err := p.parseParam()
		if err != nil {
			return nil, err
		}
		params = append(params, param)

		// Optional comma
		if p.check(TokenComma) {
			p.advance()
		} else {
			break
		}
	}

	if err := p.expect(TokenRParen); err != nil {
		return nil, err
	}

	return params, nil
}

// parseParam parses: name: type
func (p *Parser) parseParam() (domain.Param, error) {
	param := domain.Param{}

	// Parameter name
	if !p.check(TokenIdent) {
		return param, p.errorf("expected parameter name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return param, fmt.Errorf("invalid parameter name %q: %w", p.current.Value, err)
	}
	param.Name = name
	p.advance()

	if err := p.expect(TokenColon); err != nil {
		return param, err
	}

	// Parameter type
	paramType, err := p.parseType()
	if err != nil {
		return param, err
	}
	param.Type = paramType

	return param, nil
}

// parseWorld parses: world name { ... }
func (p *Parser) parseWorld() (domain.World, error) {
	world := domain.World{
		Imports: []domain.WorldItem{},
		Exports: []domain.WorldItem{},
		Uses:    []domain.Use{},
		Docs:    domain.NewDocumentation(""),
	}

	if err := p.expect(TokenWorld); err != nil {
		return world, err
	}

	// World name
	if !p.check(TokenIdent) {
		return world, p.errorf("expected world name, got %s", p.current.Kind)
	}
	name, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return world, fmt.Errorf("invalid world name %q: %w", p.current.Value, err)
	}
	world.Name = name
	p.advance()

	if err := p.expect(TokenLBrace); err != nil {
		return world, err
	}

	// Parse world items
	for !p.check(TokenRBrace) && !p.check(TokenEOF) {
		if p.check(TokenImport) {
			item, err := p.parseWorldItem("import")
			if err != nil {
				return world, err
			}
			world.Imports = append(world.Imports, item)
		} else if p.check(TokenExport) {
			item, err := p.parseWorldItem("export")
			if err != nil {
				return world, err
			}
			world.Exports = append(world.Exports, item)
		} else if p.check(TokenUse) {
			// Skip use statements in worlds for now
			p.skipUntil(TokenSemicolon)
			p.advance()
		} else {
			return world, p.errorf("unexpected token %s in world, expected import/export", p.current.Kind)
		}
	}

	if err := p.expect(TokenRBrace); err != nil {
		return world, err
	}

	return world, nil
}

// parseWorldItem parses: import/export name; or import/export name: interface { ... }
func (p *Parser) parseWorldItem(keyword string) (domain.WorldItem, error) {
	// Skip the import/export keyword
	p.advance()

	// Get the name
	if !p.check(TokenIdent) {
		return nil, p.errorf("expected identifier after %s, got %s", keyword, p.current.Kind)
	}
	itemName, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return nil, fmt.Errorf("invalid %s name %q: %w", keyword, p.current.Value, err)
	}
	p.advance()

	// Simple import/export (just the name)
	if p.check(TokenSemicolon) {
		p.advance()
		return domain.InterfaceItem{
			Name: itemName,
			Ref:  domain.ExternalInterfaceRef{Path: domain.LocalUsePath{Interface: itemName}},
		}, nil
	}

	// Import/export with interface definition: name: interface { ... }
	if p.check(TokenColon) {
		p.advance()
		// Could be: interface { ... } or an external reference like ns:pkg/iface
		// For now, skip to semicolon
		p.skipUntil(TokenSemicolon)
		p.advance()
		return domain.InterfaceItem{
			Name: itemName,
			Ref:  domain.ExternalInterfaceRef{Path: domain.LocalUsePath{Interface: itemName}},
		}, nil
	}

	return nil, p.errorf("unexpected token after %s name: %s", keyword, p.current.Kind)
}

// parseUse parses: use path.{names};
func (p *Parser) parseUse() (domain.Use, error) {
	// Skip use statements for now
	p.skipUntil(TokenSemicolon)
	p.advance()
	return domain.Use{}, nil
}

// parseType parses a type expression.
func (p *Parser) parseType() (domain.Type, error) {
	switch {
	// Primitive types
	case p.check(TokenU8):
		p.advance()
		return domain.PrimitiveType{Kind: domain.U8}, nil
	case p.check(TokenU16):
		p.advance()
		return domain.PrimitiveType{Kind: domain.U16}, nil
	case p.check(TokenU32):
		p.advance()
		return domain.PrimitiveType{Kind: domain.U32}, nil
	case p.check(TokenU64):
		p.advance()
		return domain.PrimitiveType{Kind: domain.U64}, nil
	case p.check(TokenS8):
		p.advance()
		return domain.PrimitiveType{Kind: domain.S8}, nil
	case p.check(TokenS16):
		p.advance()
		return domain.PrimitiveType{Kind: domain.S16}, nil
	case p.check(TokenS32):
		p.advance()
		return domain.PrimitiveType{Kind: domain.S32}, nil
	case p.check(TokenS64):
		p.advance()
		return domain.PrimitiveType{Kind: domain.S64}, nil
	case p.check(TokenF32):
		p.advance()
		return domain.PrimitiveType{Kind: domain.F32}, nil
	case p.check(TokenF64):
		p.advance()
		return domain.PrimitiveType{Kind: domain.F64}, nil
	case p.check(TokenBool):
		p.advance()
		return domain.PrimitiveType{Kind: domain.Bool}, nil
	case p.check(TokenChar):
		p.advance()
		return domain.PrimitiveType{Kind: domain.Char}, nil
	case p.check(TokenString):
		p.advance()
		return domain.PrimitiveType{Kind: domain.String}, nil

	// Container types
	case p.check(TokenList):
		return p.parseListType()
	case p.check(TokenOption):
		return p.parseOptionType()
	case p.check(TokenResult):
		return p.parseResultType()
	case p.check(TokenTuple):
		return p.parseTupleType()
	case p.check(TokenFuture):
		return p.parseFutureType()
	case p.check(TokenStream):
		return p.parseStreamType()

	// Handle types
	case p.check(TokenOwn):
		return p.parseOwnType()
	case p.check(TokenBorrow):
		return p.parseBorrowType()

	// Underscore (for result<_, error>)
	case p.check(TokenUnderscore):
		p.advance()
		// Return nil to indicate "no type" in result context
		return nil, nil

	// Named type
	case p.check(TokenIdent):
		name, err := domain.NewIdentifier(p.current.Value)
		if err != nil {
			return nil, fmt.Errorf("invalid type name %q: %w", p.current.Value, err)
		}
		p.advance()
		return domain.NamedType{Name: name}, nil

	default:
		return nil, p.errorf("expected type, got %s", p.current.Kind)
	}
}

// parseListType parses: list<type>
func (p *Parser) parseListType() (domain.Type, error) {
	if err := p.expect(TokenList); err != nil {
		return nil, err
	}
	if err := p.expect(TokenLAngle); err != nil {
		return nil, err
	}
	elem, err := p.parseType()
	if err != nil {
		return nil, err
	}
	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}
	return domain.ListType{Element: elem}, nil
}

// parseOptionType parses: option<type>
func (p *Parser) parseOptionType() (domain.Type, error) {
	if err := p.expect(TokenOption); err != nil {
		return nil, err
	}
	if err := p.expect(TokenLAngle); err != nil {
		return nil, err
	}
	inner, err := p.parseType()
	if err != nil {
		return nil, err
	}
	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}
	return domain.OptionType{Inner: inner}, nil
}

// parseResultType parses: result, result<type>, result<type, type>, result<_, type>
func (p *Parser) parseResultType() (domain.Type, error) {
	if err := p.expect(TokenResult); err != nil {
		return nil, err
	}

	// Check for bare result
	if !p.check(TokenLAngle) {
		return domain.ResultType{Ok: nil, Err: nil}, nil
	}

	p.advance() // consume <

	// First type (ok type or _)
	var okType *domain.Type
	if !p.check(TokenUnderscore) {
		ok, err := p.parseType()
		if err != nil {
			return nil, err
		}
		okType = &ok
	} else {
		p.advance() // consume _
	}

	// Check for second type
	var errType *domain.Type
	if p.check(TokenComma) {
		p.advance() // consume ,
		err, parseErr := p.parseType()
		if parseErr != nil {
			return nil, parseErr
		}
		errType = &err
	}

	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}

	return domain.ResultType{Ok: okType, Err: errType}, nil
}

// parseTupleType parses: tuple<type, ...>
func (p *Parser) parseTupleType() (domain.Type, error) {
	if err := p.expect(TokenTuple); err != nil {
		return nil, err
	}
	if err := p.expect(TokenLAngle); err != nil {
		return nil, err
	}

	types := []domain.Type{}
	for !p.check(TokenRAngle) && !p.check(TokenEOF) {
		t, err := p.parseType()
		if err != nil {
			return nil, err
		}
		types = append(types, t)

		if p.check(TokenComma) {
			p.advance()
		} else {
			break
		}
	}

	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}

	return domain.TupleType{Types: types}, nil
}

// parseFutureType parses: future or future<type>
func (p *Parser) parseFutureType() (domain.Type, error) {
	if err := p.expect(TokenFuture); err != nil {
		return nil, err
	}

	// Check for bare future
	if !p.check(TokenLAngle) {
		return domain.FutureType{Inner: nil}, nil
	}

	p.advance() // consume <
	inner, err := p.parseType()
	if err != nil {
		return nil, err
	}
	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}

	return domain.FutureType{Inner: &inner}, nil
}

// parseStreamType parses: stream or stream<type>
func (p *Parser) parseStreamType() (domain.Type, error) {
	if err := p.expect(TokenStream); err != nil {
		return nil, err
	}

	// Check for bare stream
	if !p.check(TokenLAngle) {
		return domain.StreamType{Element: nil}, nil
	}

	p.advance() // consume <
	elem, err := p.parseType()
	if err != nil {
		return nil, err
	}
	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}

	return domain.StreamType{Element: &elem}, nil
}

// parseOwnType parses: own<resource>
func (p *Parser) parseOwnType() (domain.Type, error) {
	if err := p.expect(TokenOwn); err != nil {
		return nil, err
	}
	if err := p.expect(TokenLAngle); err != nil {
		return nil, err
	}

	if !p.check(TokenIdent) {
		return nil, p.errorf("expected resource name, got %s", p.current.Kind)
	}
	resourceName, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return nil, fmt.Errorf("invalid resource name %q: %w", p.current.Value, err)
	}
	p.advance()

	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}

	return domain.HandleType{Resource: resourceName, IsBorrow: false}, nil
}

// parseBorrowType parses: borrow<resource>
func (p *Parser) parseBorrowType() (domain.Type, error) {
	if err := p.expect(TokenBorrow); err != nil {
		return nil, err
	}
	if err := p.expect(TokenLAngle); err != nil {
		return nil, err
	}

	if !p.check(TokenIdent) {
		return nil, p.errorf("expected resource name, got %s", p.current.Kind)
	}
	resourceName, err := domain.NewIdentifier(p.current.Value)
	if err != nil {
		return nil, fmt.Errorf("invalid resource name %q: %w", p.current.Value, err)
	}
	p.advance()

	if err := p.expect(TokenRAngle); err != nil {
		return nil, err
	}

	return domain.HandleType{Resource: resourceName, IsBorrow: true}, nil
}

// Helper methods

// check returns true if the current token is of the given kind.
func (p *Parser) check(kind TokenKind) bool {
	return p.current.Kind == kind
}

// advance moves to the next token.
func (p *Parser) advance() {
	p.current = p.peek
	p.peek = p.lexer.NextToken()
}

// expect consumes a token of the given kind, or returns an error.
func (p *Parser) expect(kind TokenKind) error {
	if p.current.Kind != kind {
		return p.errorf("expected %s, got %s", kind, p.current.Kind)
	}
	p.advance()
	return nil
}

// skipUntil advances until reaching a token of the given kind.
func (p *Parser) skipUntil(kind TokenKind) {
	for !p.check(kind) && !p.check(TokenEOF) {
		p.advance()
	}
}

// errorf creates a parse error with position information.
func (p *Parser) errorf(format string, args ...any) error {
	msg := fmt.Sprintf(format, args...)
	return fmt.Errorf("parse error at %s: %s", p.current.Pos, msg)
}

// isBuiltinType returns true if the token is a built-in type keyword.
func isBuiltinType(kind TokenKind) bool {
	switch kind {
	case TokenU8, TokenU16, TokenU32, TokenU64,
		TokenS8, TokenS16, TokenS32, TokenS64,
		TokenF32, TokenF64, TokenBool, TokenChar, TokenString,
		TokenList, TokenOption, TokenResult, TokenTuple,
		TokenFuture, TokenStream, TokenOwn, TokenBorrow:
		return true
	default:
		return false
	}
}

// isKeywordOrIdent returns true if the token can be used as an identifier.
func isKeywordOrIdent(kind TokenKind) bool {
	switch kind {
	case TokenIdent:
		return true
	// Keywords that can be used as names
	case TokenPackage, TokenInterface, TokenWorld, TokenFunc, TokenType,
		TokenRecord, TokenVariant, TokenEnum, TokenFlags, TokenResource,
		TokenUse, TokenAs, TokenImport, TokenExport, TokenInclude,
		TokenWith, TokenConstructor, TokenStatic, TokenAsync,
		TokenOwn, TokenBorrow:
		return true
	// Built-in types that can be used as names
	case TokenU8, TokenU16, TokenU32, TokenU64,
		TokenS8, TokenS16, TokenS32, TokenS64,
		TokenF32, TokenF64, TokenBool, TokenChar, TokenString,
		TokenList, TokenOption, TokenResult, TokenTuple,
		TokenFuture, TokenStream:
		return true
	default:
		return false
	}
}

// getIdentifierOrKeyword returns the current token's value if it's an identifier or keyword,
// or empty string otherwise. Does not advance the parser.
func (p *Parser) getIdentifierOrKeyword() string {
	if isKeywordOrIdent(p.current.Kind) {
		return p.current.Value
	}
	return ""
}

// Unused but kept for potential future use
var _ = strconv.Atoi
