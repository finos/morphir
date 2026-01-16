---
title: WASM Component Model
sidebar_label: WASM Components
sidebar_position: 3
status: draft
tracking:
  beads: [morphir-010]
---

# WASM Component Model

This document defines WIT (WebAssembly Interface Types) interfaces for implementing Morphir backends and extensions as portable, sandboxed WASM components.

## Design Principles

- **Strongly Typed IR**: Full IR types modeled in WIT, not JSON strings
- **Attributes as Document**: Since WIT lacks generics, attributes use our `document-value` AST type
- **Full Pipeline**: Support both frontend (source → IR) and backend (IR → target) flows
- **Multi-Granularity**: Support operations at distribution, module, and definition levels
- **Capability-Based**: Components declare which interfaces they implement
- **Sandboxed**: Components have no implicit access to filesystem or network

## Benefits

| Benefit | Description |
|---------|-------------|
| Language-agnostic | Backends can be written in Rust, Go, C, AssemblyScript, etc. |
| Sandboxed | Secure execution with explicit capability grants |
| Portable | Run anywhere WASM runs (CLI, browser, edge) |
| Hot-reloadable | Swap components without restarting the daemon |
| Type-safe | Full IR types at component boundary |

## WIT Package Structure

```
wit/
├── morphir-ir/
│   ├── document.wit       # Document AST (for attributes)
│   ├── naming.wit         # Name, Path, FQName
│   ├── types.wit          # Type expressions
│   ├── values.wit         # Value expressions, literals, patterns
│   ├── modules.wit        # Module specs and defs
│   ├── packages.wit       # Package specs and defs
│   └── distributions.wit  # Distribution types
├── morphir-extension/
│   ├── info.wit           # Required info interface (all extensions)
│   └── capabilities.wit   # Capability query interface
├── morphir-frontend/
│   ├── compiler.wit       # Source → IR compilation (basic)
│   ├── streaming.wit      # Streaming compilation capability
│   ├── incremental.wit    # Incremental compilation capability
│   └── fragment.wit       # Fragment/REPL compilation capability
├── morphir-backend/
│   ├── generator.wit      # IR → target code generation (basic)
│   ├── streaming.wit      # Streaming generation capability
│   ├── incremental.wit    # Incremental generation capability
│   ├── validator.wit      # Validation interface
│   └── transform.wit      # IR → IR transformation interface
├── morphir-vfs/
│   ├── reader.wit         # VFS read access
│   ├── writer.wit         # VFS write access
│   └── workspace.wit      # Workspace management
└── morphir-component/
    └── worlds.wit         # World definitions
```

## Document Type (`document.wit`)

```wit
package morphir:ir@0.4.0;

/// Document AST for schema-less data and attributes
interface document {
    /// Recursive document value (JSON-like AST)
    variant document-value {
        /// null
        doc-null,
        /// Boolean
        doc-bool(bool),
        /// Integer
        doc-int(s64),
        /// Float
        doc-float(float64),
        /// String
        doc-string(string),
        /// Array
        doc-array(list<document-value>),
        /// Object (list of key-value pairs)
        doc-object(list<tuple<string, document-value>>),
    }

    /// Empty document (convenience)
    empty: func() -> document-value;

    /// Create object from pairs
    object: func(pairs: list<tuple<string, document-value>>) -> document-value;

    /// Get field from object
    get: func(doc: document-value, key: string) -> option<document-value>;

    /// Merge two documents (second wins on conflict)
    merge: func(base: document-value, overlay: document-value) -> document-value;
}
```

## Naming Types (`naming.wit`)

```wit
package morphir:ir@0.4.0;

use document.{document-value};

/// Core naming types
interface naming {
    /// Type-level attributes (optional metadata, no type info needed)
    /// Types don't carry type annotations on themselves
    variant type-attributes {
        /// No attributes
        none,
        /// Custom metadata only
        meta(document-value),
    }

    /// A single name segment in kebab-case
    /// Examples: "user", "order-id", "get-user-by-email"
    type name = string;

    /// A path is a list of names representing hierarchy
    /// Serialized as slash-separated: "main/domain/users"
    type path = string;

    /// Module path within a package
    type module-path = string;

    /// Package path (organization/project)
    type package-path = string;

    /// Qualified name: module path + local name
    /// Format: "module/path#local-name"
    record qname {
        module-path: module-path,
        local-name: name,
    }

    /// Fully qualified name: package + module + local name
    /// Format: "package:module#name"
    record fqname {
        package-path: package-path,
        module-path: module-path,
        local-name: name,
    }

    /// Type variable name
    type type-variable = string;

    /// Parse FQName from canonical string
    /// "my-org/project:domain/users#user" -> FQName
    fqname-from-string: func(s: string) -> option<fqname>;

    /// Render FQName to canonical string
    fqname-to-string: func(fqn: fqname) -> string;
}
```

## Type Expressions (`types.wit`)

```wit
package morphir:ir@0.4.0;

use document.{document-value};
use naming.{type-attributes, name, fqname, type-variable};

/// Type system definitions
interface types {
    /// Record field
    record field {
        field-name: name,
        field-type: ir-type,
    }

    /// Constructor for custom types
    record constructor {
        ctor-name: name,
        args: list<tuple<name, ir-type>>,
    }

    /// Type expression (uses type-attributes: none or metadata)
    variant ir-type {
        /// Type variable: `a`, `comparable`
        variable(tuple<type-attributes, type-variable>),

        /// Reference to named type: `String`, `List a`
        reference(tuple<type-attributes, fqname, list<ir-type>>),

        /// Tuple: `(Int, String)`
        %tuple(tuple<type-attributes, list<ir-type>>),

        /// Record: `{ name: String, age: Int }`
        record(tuple<type-attributes, list<field>>),

        /// Extensible record: `{ a | name: String }`
        extensible-record(tuple<type-attributes, type-variable, list<field>>),

        /// Function: `Int -> String`
        %function(tuple<type-attributes, ir-type, ir-type>),

        /// Unit type: `()`
        unit(type-attributes),
    }

    /// Value-level attributes (expressions carry their type)
    variant value-attributes {
        /// Just the inferred/checked type
        typed(ir-type),
        /// Type plus custom metadata
        typed-with-meta(tuple<ir-type, document-value>),
    }

    /// Access control
    enum access {
        public,
        private,
    }

    /// Access-controlled wrapper
    record access-controlled-constructors {
        access: access,
        constructors: list<constructor>,
    }

    /// Type specification (public interface)
    variant type-specification {
        /// Type alias visible to consumers
        type-alias-specification(tuple<list<type-variable>, ir-type>),

        /// Opaque type (no structure visible)
        opaque-type-specification(list<type-variable>),

        /// Custom type with public constructors
        custom-type-specification(tuple<list<type-variable>, list<constructor>>),

        /// Derived type with conversion functions
        derived-type-specification(tuple<list<type-variable>, derived-type-details>),
    }

    /// Details for derived types
    record derived-type-details {
        base-type: ir-type,
        from-base-type: fqname,
        to-base-type: fqname,
    }

    /// Hole reason for incomplete types
    variant hole-reason {
        unresolved-reference(fqname),
        deleted-during-refactor(string),
        type-mismatch(tuple<string, string>),
    }

    /// Incompleteness marker
    variant incompleteness {
        hole(hole-reason),
        draft(option<string>),
    }

    /// Type definition (implementation)
    variant type-definition {
        /// Custom type (sum type)
        custom-type-definition(tuple<list<type-variable>, access-controlled-constructors>),

        /// Type alias
        type-alias-definition(tuple<list<type-variable>, ir-type>),

        /// Incomplete type (v4)
        incomplete-type-definition(tuple<list<type-variable>, incompleteness, option<ir-type>>),
    }
}
```

## Literals (`values.wit` - Part 1)

```wit
package morphir:ir@0.4.0;

/// Literal values
interface literals {
    /// Document value for schema-less data
    variant document-value {
        doc-null,
        doc-bool(bool),
        doc-int(s64),
        doc-float(float64),
        doc-string(string),
        doc-array(list<document-value>),
        doc-object(list<tuple<string, document-value>>),
    }

    /// Literal constant values
    variant literal {
        /// Boolean: true, false
        bool-literal(bool),

        /// Single character
        char-literal(string),

        /// Text string
        string-literal(string),

        /// Integer (includes negatives)
        integer-literal(s64),

        /// Floating-point
        float-literal(float64),

        /// Arbitrary-precision decimal (stored as string)
        decimal-literal(string),

        /// Document literal (schema-less JSON-like)
        document-literal(document-value),
    }
}
```

## Patterns (`values.wit` - Part 2)

```wit
package morphir:ir@0.4.0;

use naming.{attributes, name, fqname};
use literals.{literal};

/// Pattern matching
interface patterns {
    use naming.{type-attributes};

    /// Pattern for destructuring and matching
    /// Patterns use type-attributes (no type info, just optional metadata)
    variant pattern {
        /// Wildcard: `_`
        wildcard-pattern(type-attributes),

        /// As pattern: `x` or `(a, b) as pair`
        as-pattern(tuple<type-attributes, pattern, name>),

        /// Tuple pattern: `(a, b, c)`
        tuple-pattern(tuple<type-attributes, list<pattern>>),

        /// Constructor pattern: `Just x`
        constructor-pattern(tuple<type-attributes, fqname, list<pattern>>),

        /// Empty list: `[]`
        empty-list-pattern(type-attributes),

        /// Head :: tail: `x :: xs`
        head-tail-pattern(tuple<type-attributes, pattern, pattern>),

        /// Literal match: `42`, `"hello"`
        literal-pattern(tuple<type-attributes, literal>),

        /// Unit: `()`
        unit-pattern(type-attributes),
    }
}
```

## Value Expressions (`values.wit` - Part 3)

```wit
package morphir:ir@0.4.0;

use naming.{name, fqname};
use types.{ir-type, value-attributes, hole-reason, incompleteness};
use literals.{literal};
use patterns.{pattern};

/// Value expressions
interface values {
    /// Native operation hint
    variant native-hint {
        arithmetic,
        comparison,
        string-op,
        collection-op,
        platform-specific(string),
    }

    /// Native operation info
    record native-info {
        hint: native-hint,
        description: option<string>,
    }

    /// Value expression
    /// Values use value-attributes (carry their type, optionally with metadata)
    variant value {
        // === Literals & Data Construction ===

        /// Literal constant
        %literal(tuple<value-attributes, literal>),

        /// Constructor reference: `Just`
        %constructor(tuple<value-attributes, fqname>),

        /// Tuple: `(1, "hello")`
        %tuple(tuple<value-attributes, list<value>>),

        /// List: `[1, 2, 3]`
        %list(tuple<value-attributes, list<value>>),

        /// Record: `{ name = "Alice" }`
        %record(tuple<value-attributes, list<tuple<name, value>>>),

        /// Unit: `()`
        %unit(value-attributes),

        // === References ===

        /// Variable: `x`
        variable(tuple<value-attributes, name>),

        /// Reference to defined value: `List.map`
        reference(tuple<value-attributes, fqname>),

        // === Field Access ===

        /// Field access: `record.field`
        field(tuple<value-attributes, value, name>),

        /// Field function: `.field`
        field-function(tuple<value-attributes, name>),

        // === Function Application ===

        /// Apply: `f x`
        apply(tuple<value-attributes, value, value>),

        /// Lambda: `\x -> x + 1`
        lambda(tuple<value-attributes, pattern, value>),

        // === Let Bindings ===

        /// Let: `let x = 1 in x + 1`
        let-definition(tuple<value-attributes, name, value-definition-body, value>),

        /// Recursive let: `let f = ... g ...; g = ... f ... in ...`
        let-recursion(tuple<value-attributes, list<tuple<name, value-definition-body>>, value>),

        /// Destructure: `let (a, b) = pair in a + b`
        destructure(tuple<value-attributes, pattern, value, value>),

        // === Control Flow ===

        /// If-then-else
        if-then-else(tuple<value-attributes, value, value, value>),

        /// Pattern match: `case x of ...`
        pattern-match(tuple<value-attributes, value, list<tuple<pattern, value>>>),

        // === Record Update ===

        /// Update: `{ record | field = new }`
        update-record(tuple<value-attributes, value, list<tuple<name, value>>>),

        // === Special (v4) ===

        /// Incomplete/broken reference
        hole(tuple<value-attributes, hole-reason, option<ir-type>>),

        /// Native operation
        native(tuple<value-attributes, fqname, native-info>),

        /// External FFI
        external(tuple<value-attributes, string, string>),
    }

    /// Value definition body
    variant value-definition-body {
        /// Expression body
        expression-body(tuple<list<tuple<name, ir-type>>, ir-type, value>),

        /// Native body
        native-body(tuple<list<tuple<name, ir-type>>, ir-type, native-info>),

        /// External body
        external-body(tuple<list<tuple<name, ir-type>>, ir-type, string, string>),

        /// Incomplete body (v4)
        incomplete-body(tuple<list<tuple<name, ir-type>>, option<ir-type>, incompleteness, option<value>>),
    }

    /// Value specification (signature only)
    record value-specification {
        inputs: list<tuple<name, ir-type>>,
        output: ir-type,
    }

    /// Access-controlled value definition
    record value-definition {
        access: types.access,
        body: value-definition-body,
    }
}
```

## Modules (`modules.wit`)

```wit
package morphir:ir@0.4.0;

use naming.{name, module-path};
use types.{type-specification, type-definition, access};
use values.{value-specification, value-definition};

/// Module definitions
interface modules {
    /// Documentation (opaque string or list of strings)
    variant documentation {
        single-line(string),
        multi-line(list<string>),
    }

    /// Documented wrapper
    record documented-type-spec {
        doc: option<documentation>,
        value: type-specification,
    }

    /// Module specification (public interface)
    record module-specification {
        types: list<tuple<name, documented-type-spec>>,
        values: list<tuple<name, value-specification>>,
    }

    /// Documented type definition with access
    record access-controlled-documented-type-def {
        access: access,
        doc: option<documentation>,
        definition: type-definition,
    }

    /// Documented value definition with access
    record access-controlled-documented-value-def {
        access: access,
        doc: option<documentation>,
        definition: value-definition,
    }

    /// Module definition (implementation)
    record module-definition {
        types: list<tuple<name, access-controlled-documented-type-def>>,
        values: list<tuple<name, access-controlled-documented-value-def>>,
    }

    /// Access-controlled module definition
    record access-controlled-module-definition {
        access: access,
        definition: module-definition,
    }
}
```

## Packages (`packages.wit`)

```wit
package morphir:ir@0.4.0;

use naming.{module-path};
use modules.{module-specification, access-controlled-module-definition};

/// Package definitions
interface packages {
    /// Package specification (public interface)
    record package-specification {
        modules: list<tuple<module-path, module-specification>>,
    }

    /// Package definition (implementation)
    record package-definition {
        modules: list<tuple<module-path, access-controlled-module-definition>>,
    }
}
```

## Distributions (`distributions.wit`)

```wit
package morphir:ir@0.4.0;

use naming.{name, fqname, package-path};
use modules.{documentation};
use packages.{package-specification, package-definition};

/// Distribution types
interface distributions {
    /// Semantic version
    record semver {
        major: u32,
        minor: u32,
        patch: u32,
        pre-release: option<string>,
        build-metadata: option<string>,
    }

    /// Package info
    record package-info {
        name: package-path,
        version: semver,
    }

    /// Entry point kind
    enum entry-point-kind {
        main,
        command,
        handler,
        job,
        policy,
    }

    /// Entry point
    record entry-point {
        target: fqname,
        kind: entry-point-kind,
        doc: option<documentation>,
    }

    /// Library distribution
    record library-distribution {
        package: package-info,
        definition: package-definition,
        dependencies: list<tuple<package-path, package-specification>>,
    }

    /// Specs distribution
    record specs-distribution {
        package: package-info,
        specification: package-specification,
        dependencies: list<tuple<package-path, package-specification>>,
    }

    /// Application distribution
    record application-distribution {
        package: package-info,
        definition: package-definition,
        dependencies: list<tuple<package-path, package-definition>>,
        entry-points: list<tuple<name, entry-point>>,
    }

    /// Distribution variant
    variant distribution {
        library(library-distribution),
        specs(specs-distribution),
        application(application-distribution),
    }
}
```

## Extension Info Interface (`info.wit`)

Every extension must implement this interface - it's the only required interface:

```wit
package morphir:extension@0.4.0;

/// Required interface - all extensions must implement this
interface info {
    /// Extension type classification
    enum extension-type {
        /// Frontend/compiler (source → IR)
        frontend,
        /// Backend/code generator (IR → target)
        codegen,
        /// Validator/analyzer
        validator,
        /// IR transformer (IR → IR)
        transformer,
        /// General purpose
        general,
    }

    /// Extension metadata
    record extension-info {
        /// Unique identifier (e.g., "spark-codegen")
        id: string,
        /// Human-readable name
        name: string,
        /// Version (semver)
        version: string,
        /// Description
        description: string,
        /// Author/maintainer
        author: option<string>,
        /// Homepage/repository URL
        homepage: option<string>,
        /// License identifier (SPDX)
        license: option<string>,
        /// Extension types (can fulfill multiple roles)
        types: list<extension-type>,
    }

    /// Return extension metadata
    get-info: func() -> extension-info;

    /// Health check - return true if extension is ready
    ping: func() -> bool;
}

/// Capability discovery interface
interface capabilities {
    use info.{extension-type};

    /// Capability identifier (e.g., "codegen/generate-streaming")
    type capability-id = string;

    /// Capability info
    record capability-info {
        /// Capability identifier
        id: capability-id,
        /// Human-readable description
        description: string,
        /// Whether this capability is available
        available: bool,
    }

    /// Options schema for configurable extensions
    record option-schema {
        /// Option name
        name: string,
        /// Option type
        option-type: option-type,
        /// Default value (as JSON string)
        default-value: option<string>,
        /// Description
        description: string,
        /// Whether this option is required
        required: bool,
    }

    /// Option type
    enum option-type {
        %string,
        integer,
        float,
        boolean,
        array,
        object,
    }

    /// Query all capabilities this extension provides
    list-capabilities: func() -> list<capability-info>;

    /// Check if a specific capability is available
    has-capability: func(id: capability-id) -> bool;

    /// Get targets this extension supports (for codegen)
    get-targets: func() -> list<string>;

    /// Get languages this extension supports (for frontend)
    get-languages: func() -> list<string>;

    /// Get configurable options schema
    get-options-schema: func() -> list<option-schema>;
}
```

## Frontend Compiler Interface (`compiler.wit`)

```wit
package morphir:frontend@0.4.0;

use morphir:ir@0.4.0.{
    naming.{name, module-path, package-path, fqname},
    types.{type-definition},
    values.{value-definition},
    modules.{module-definition},
    packages.{package-definition},
    distributions.{distribution, semver},
};

/// Frontend compiler interface (source → IR)
interface compiler {
    /// Source language
    enum source-language {
        elm,
        morphir-dsl,
        custom,
    }

    /// Compilation granularity capability
    flags compiler-capabilities {
        /// Can compile entire workspace
        workspace,
        /// Can compile single project
        project,
        /// Can compile single module
        module,
        /// Can compile individual files
        file,
        /// Can compile code fragments
        fragment,
    }

    /// Compiler metadata
    record compiler-info {
        name: string,
        description: string,
        version: string,
        source-language: source-language,
        custom-language: option<string>,
        capabilities: compiler-capabilities,
    }

    /// Source file
    record source-file {
        /// File path (relative to project root)
        path: string,
        /// File content
        content: string,
    }

    /// Project configuration
    record project-config {
        /// Project name
        name: package-path,
        /// Project version
        version: semver,
        /// Source directory
        source-dir: string,
        /// Dependencies
        dependencies: list<tuple<package-path, semver>>,
        /// Custom configuration as document
        custom: option<morphir:ir@0.4.0.document.document-value>,
    }

    /// Workspace configuration
    record workspace-config {
        /// Workspace root path
        root: string,
        /// Projects in workspace
        projects: list<project-config>,
    }

    /// Fragment context (for incremental/editor compilation)
    record fragment-context {
        /// Module this fragment belongs to
        module-path: module-path,
        /// Imports available in scope
        imports: list<fqname>,
        /// Local bindings in scope
        locals: list<tuple<name, morphir:ir@0.4.0.types.ir-type>>,
    }

    /// Diagnostic severity
    enum severity {
        error,
        warning,
        info,
        hint,
    }

    /// Source location
    record source-location {
        file: string,
        start-line: u32,
        start-col: u32,
        end-line: u32,
        end-col: u32,
    }

    /// Compiler diagnostic
    record diagnostic {
        severity: severity,
        code: string,
        message: string,
        location: option<source-location>,
        hints: list<string>,
    }

    /// Compilation result for workspace
    variant workspace-result {
        ok(list<distribution>),
        partial(tuple<list<distribution>, list<diagnostic>>),
        failed(list<diagnostic>),
    }

    /// Compilation result for project
    variant project-result {
        ok(distribution),
        partial(tuple<distribution, list<diagnostic>>),
        failed(list<diagnostic>),
    }

    /// Compilation result for files
    variant files-result {
        ok(package-definition),
        partial(tuple<package-definition, list<diagnostic>>),
        failed(list<diagnostic>),
    }

    /// Compilation result for module
    variant module-result {
        ok(module-definition),
        partial(tuple<module-definition, list<diagnostic>>),
        failed(list<diagnostic>),
    }

    /// Compilation result for fragment
    variant fragment-result {
        /// Compiled to type definition
        type-def(type-definition),
        /// Compiled to value definition
        value-def(value-definition),
        /// Compiled to expression (for REPL)
        expression(morphir:ir@0.4.0.values.value),
        /// Failed
        failed(list<diagnostic>),
    }

    /// Get compiler metadata
    info: func() -> compiler-info;

    /// Compile entire workspace to IR
    compile-workspace: func(
        config: workspace-config,
        files: list<source-file>,
    ) -> workspace-result;

    /// Compile single project to IR
    compile-project: func(
        config: project-config,
        files: list<source-file>,
    ) -> project-result;

    /// Compile list of files to IR (incremental)
    compile-files: func(
        config: project-config,
        files: list<source-file>,
        /// Existing IR to merge with (for incremental)
        existing: option<package-definition>,
    ) -> files-result;

    /// Compile a single module to IR
    compile-module: func(
        config: project-config,
        /// Module path within the project
        module-path: module-path,
        /// Source files for this module
        files: list<source-file>,
        /// Existing module to merge with (for incremental)
        existing: option<module-definition>,
    ) -> module-result;

    /// Compile a code fragment (for editor/REPL)
    compile-fragment: func(
        source: string,
        context: fragment-context,
    ) -> fragment-result;

    /// Parse without full compilation (for syntax checking)
    parse-file: func(
        file: source-file,
    ) -> result<_, list<diagnostic>>;

    /// Get completions at position (for editor integration)
    completions: func(
        file: source-file,
        line: u32,
        column: u32,
        context: fragment-context,
    ) -> list<completion-item>;

    /// Completion item
    record completion-item {
        label: string,
        kind: completion-kind,
        detail: option<string>,
        insert-text: option<string>,
    }

    /// Completion kind
    enum completion-kind {
        %function,
        variable,
        %type,
        %constructor,
        module,
        keyword,
    }
}
```

## Generator Interface (`generator.wit`)

```wit
package morphir:backend@0.4.0;

use morphir:ir@0.4.0.{
    naming.{fqname, module-path},
    types.{type-definition},
    values.{value-definition},
    modules.{module-definition},
    packages.{package-specification},
    distributions.{distribution},
};

/// Code generation interface
interface generator {
    /// Target language
    enum target-language {
        typescript,
        scala,
        java,
        go,
        python,
        rust,
        elm,
        custom,
    }

    /// Granularity level
    enum granularity {
        distribution,
        module,
        definition,
    }

    /// Generator metadata
    record generator-info {
        name: string,
        description: string,
        version: string,
        target: target-language,
        custom-target: option<string>,
        supported-granularities: list<granularity>,
    }

    /// Generation options
    record generation-options {
        output-dir: string,
        indent: option<string>,
        source-maps: bool,
        custom: option<string>,
    }

    /// Generated artifact
    record artifact {
        path: string,
        content: string,
        source-map: option<string>,
    }

    /// Diagnostic severity
    enum severity {
        error,
        warning,
        info,
        hint,
    }

    /// Source location
    record source-location {
        uri: string,
        start-line: u32,
        start-col: u32,
        end-line: u32,
        end-col: u32,
    }

    /// Diagnostic message
    record diagnostic {
        severity: severity,
        code: string,
        message: string,
        location: option<source-location>,
    }

    /// Generation result
    variant generation-result {
        /// Success
        ok(list<artifact>),
        /// Partial success with warnings
        degraded(tuple<list<artifact>, list<diagnostic>>),
        /// Failure
        failed(list<diagnostic>),
    }

    /// Get generator metadata
    info: func() -> generator-info;

    /// Generate code for entire distribution
    generate-distribution: func(
        dist: distribution,
        options: generation-options,
    ) -> generation-result;

    /// Generate code for a single module
    generate-module: func(
        path: module-path,
        module: module-definition,
        deps: package-specification,
        options: generation-options,
    ) -> generation-result;

    /// Generate code for a single type
    generate-type: func(
        fqn: fqname,
        def: type-definition,
        deps: package-specification,
        options: generation-options,
    ) -> generation-result;

    /// Generate code for a single value
    generate-value: func(
        fqn: fqname,
        def: value-definition,
        deps: package-specification,
        options: generation-options,
    ) -> generation-result;
}
```

## Validator Interface (`validator.wit`)

```wit
package morphir:backend@0.4.0;

use morphir:ir@0.4.0.{
    naming.{fqname, module-path},
    types.{type-definition},
    values.{value-definition},
    modules.{module-definition},
    packages.{package-specification},
    distributions.{distribution},
};
use generator.{severity, diagnostic, granularity};

/// Validation interface
interface validator {
    /// Validator metadata
    record validator-info {
        name: string,
        description: string,
        version: string,
        categories: list<string>,
        supported-granularities: list<granularity>,
    }

    /// Validation options
    record validation-options {
        min-severity: option<severity>,
        enabled-rules: list<string>,
        disabled-rules: list<string>,
        custom: option<string>,
    }

    /// Validation result
    record validation-result {
        diagnostics: list<diagnostic>,
        passed: bool,
        error-count: u32,
        warning-count: u32,
    }

    /// Get validator metadata
    info: func() -> validator-info;

    /// Validate entire distribution
    validate-distribution: func(
        dist: distribution,
        options: validation-options,
    ) -> validation-result;

    /// Validate a single module
    validate-module: func(
        path: module-path,
        module: module-definition,
        deps: package-specification,
        options: validation-options,
    ) -> validation-result;

    /// Validate a single type
    validate-type: func(
        fqn: fqname,
        def: type-definition,
        deps: package-specification,
        options: validation-options,
    ) -> validation-result;

    /// Validate a single value
    validate-value: func(
        fqn: fqname,
        def: value-definition,
        deps: package-specification,
        options: validation-options,
    ) -> validation-result;
}
```

## Frontend Streaming Interface (`frontend/streaming.wit`)

Optional capability for streaming compilation results:

```wit
package morphir:frontend@0.4.0;

use compiler.{source-file, project-config, diagnostic};
use morphir:ir@0.4.0.modules.{module-definition};
use morphir:ir@0.4.0.naming.{module-path};

/// Streaming compilation interface (optional capability)
interface streaming {
    /// Streaming module result
    record module-compile-result {
        /// Module path
        path: module-path,
        /// Compiled module (if successful)
        module: option<module-definition>,
        /// Diagnostics for this module
        diagnostics: list<diagnostic>,
    }

    /// Compile project with streaming results
    /// Returns a stream handle for polling results
    compile-streaming: func(
        config: project-config,
        files: list<source-file>,
    ) -> stream-handle;

    /// Stream handle for polling results
    type stream-handle = u64;

    /// Poll for next result (non-blocking)
    /// Returns none when stream is complete
    poll-result: func(handle: stream-handle) -> option<module-compile-result>;

    /// Check if stream is complete
    is-complete: func(handle: stream-handle) -> bool;

    /// Cancel streaming compilation
    cancel: func(handle: stream-handle);
}
```

## Frontend Incremental Interface (`frontend/incremental.wit`)

Optional capability for incremental compilation:

```wit
package morphir:frontend@0.4.0;

use compiler.{source-file, project-config, diagnostic};
use morphir:ir@0.4.0.packages.{package-definition};
use morphir:ir@0.4.0.naming.{module-path};

/// Incremental compilation interface (optional capability)
interface incremental {
    /// File change event
    variant file-change {
        /// File was created
        created(source-file),
        /// File was modified
        modified(source-file),
        /// File was deleted
        deleted(string),
        /// File was renamed
        renamed(tuple<string, string>),
    }

    /// Incremental compilation result
    record incremental-result {
        /// Updated package definition
        package: package-definition,
        /// Modules that were recompiled
        recompiled-modules: list<module-path>,
        /// Modules that were invalidated (dependents)
        invalidated-modules: list<module-path>,
        /// Diagnostics from recompilation
        diagnostics: list<diagnostic>,
    }

    /// Apply incremental changes to existing IR
    compile-incremental: func(
        config: project-config,
        /// Existing compiled IR
        existing: package-definition,
        /// File changes since last compilation
        changes: list<file-change>,
    ) -> incremental-result;

    /// Get dependency graph for invalidation analysis
    get-module-dependencies: func(
        existing: package-definition,
    ) -> list<tuple<module-path, list<module-path>>>;
}
```

## Backend Streaming Interface (`backend/streaming.wit`)

Optional capability for streaming code generation:

```wit
package morphir:backend@0.4.0;

use generator.{generation-options, artifact, diagnostic};
use morphir:ir@0.4.0.distributions.{distribution};
use morphir:ir@0.4.0.naming.{module-path};

/// Streaming generation interface (optional capability)
interface streaming {
    /// Module generation result
    record module-generation-result {
        /// Module path that was generated
        module-path: module-path,
        /// Generated artifacts for this module
        artifacts: list<artifact>,
        /// Diagnostics for this module
        diagnostics: list<diagnostic>,
    }

    /// Generate with streaming results
    generate-streaming: func(
        dist: distribution,
        options: generation-options,
    ) -> stream-handle;

    /// Stream handle for polling results
    type stream-handle = u64;

    /// Poll for next result (non-blocking)
    poll-result: func(handle: stream-handle) -> option<module-generation-result>;

    /// Check if stream is complete
    is-complete: func(handle: stream-handle) -> bool;

    /// Cancel streaming generation
    cancel: func(handle: stream-handle);
}
```

## Backend Incremental Interface (`backend/incremental.wit`)

Optional capability for incremental code generation:

```wit
package morphir:backend@0.4.0;

use generator.{generation-options, artifact, diagnostic};
use morphir:ir@0.4.0.distributions.{distribution};
use morphir:ir@0.4.0.naming.{module-path};

/// Incremental generation interface (optional capability)
interface incremental {
    /// Module change notification
    record module-change {
        /// Module path that changed
        path: module-path,
        /// Type of change
        change-type: change-type,
    }

    /// Change type
    enum change-type {
        /// Module was added
        added,
        /// Module was modified
        modified,
        /// Module was removed
        removed,
    }

    /// Incremental generation result
    record incremental-generation-result {
        /// Generated/updated artifacts
        artifacts: list<artifact>,
        /// Artifacts to delete (paths)
        deleted-artifacts: list<string>,
        /// Diagnostics
        diagnostics: list<diagnostic>,
    }

    /// Generate incrementally for changed modules only
    generate-incremental: func(
        dist: distribution,
        changed-modules: list<module-change>,
        options: generation-options,
    ) -> incremental-generation-result;
}
```

## Transform Interface (`backend/transform.wit`)

Standalone interface for IR-to-IR transformations:

```wit
package morphir:backend@0.4.0;

use generator.{diagnostic};
use morphir:ir@0.4.0.{
    naming.{fqname, module-path},
    types.{type-definition},
    values.{value-definition},
    modules.{module-definition},
    packages.{package-definition},
    distributions.{distribution},
    document.{document-value},
};

/// IR transformation interface
interface transform {
    /// Transformation metadata
    record transform-info {
        /// Transform name
        name: string,
        /// Description
        description: string,
        /// Version
        version: string,
        /// Whether transform preserves semantics
        semantic-preserving: bool,
    }

    /// Transformation options
    record transform-options {
        /// Dry run (report changes without applying)
        dry-run: bool,
        /// Custom options (JSON-like)
        custom: option<document-value>,
    }

    /// Transformation result
    record transform-result {
        /// Whether transformation succeeded
        success: bool,
        /// Number of definitions modified
        definitions-modified: u32,
        /// Diagnostics (warnings, info)
        diagnostics: list<diagnostic>,
    }

    /// Get transform metadata
    info: func() -> transform-info;

    /// Transform entire distribution
    transform-distribution: func(
        dist: distribution,
        options: transform-options,
    ) -> tuple<distribution, transform-result>;

    /// Transform a single module
    transform-module: func(
        path: module-path,
        module: module-definition,
        options: transform-options,
    ) -> tuple<module-definition, transform-result>;

    /// Transform a single type definition
    transform-type: func(
        fqn: fqname,
        def: type-definition,
        options: transform-options,
    ) -> tuple<type-definition, transform-result>;

    /// Transform a single value definition
    transform-value: func(
        fqn: fqname,
        def: value-definition,
        options: transform-options,
    ) -> tuple<value-definition, transform-result>;
}
```

## VFS Interfaces (`reader.wit` / `writer.wit`)

```wit
package morphir:vfs@0.4.0;

use morphir:ir@0.4.0.{
    naming.{fqname, module-path, package-path},
    types.{type-definition},
    values.{value-definition},
    modules.{module-definition},
    distributions.{distribution},
};
use morphir:backend@0.4.0.generator.{diagnostic};

/// VFS read-only access
interface reader {
    /// Read error
    variant read-error {
        not-found(string),
        permission-denied(string),
        parse-error(string),
    }

    /// Read a type definition
    read-type: func(fqn: fqname) -> result<type-definition, read-error>;

    /// Read a value definition
    read-value: func(fqn: fqname) -> result<value-definition, read-error>;

    /// Read a module definition
    read-module: func(path: module-path) -> result<module-definition, read-error>;

    /// Read entire distribution
    read-distribution: func() -> result<distribution, read-error>;

    /// List modules in a package
    list-modules: func(pkg: package-path) -> result<list<module-path>, read-error>;

    /// List types in a module
    list-types: func(path: module-path) -> result<list<fqname>, read-error>;

    /// List values in a module
    list-values: func(path: module-path) -> result<list<fqname>, read-error>;
}

/// VFS write access
interface writer {
    /// Write error
    variant write-error {
        permission-denied(string),
        validation-failed(list<diagnostic>),
        conflict(string),
    }

    /// Transaction handle
    type transaction = u64;

    /// Begin transaction
    begin-transaction: func() -> transaction;

    /// Commit transaction
    commit: func(tx: transaction) -> result<_, write-error>;

    /// Rollback transaction
    rollback: func(tx: transaction) -> result<_, write-error>;

    /// Write a type definition
    write-type: func(
        tx: transaction,
        fqn: fqname,
        def: type-definition,
    ) -> result<_, write-error>;

    /// Write a value definition
    write-value: func(
        tx: transaction,
        fqn: fqname,
        def: value-definition,
    ) -> result<_, write-error>;

    /// Delete a type
    delete-type: func(tx: transaction, fqn: fqname) -> result<_, write-error>;

    /// Delete a value
    delete-value: func(tx: transaction, fqn: fqname) -> result<_, write-error>;

    /// Rename a type
    rename-type: func(
        tx: transaction,
        old-fqn: fqname,
        new-fqn: fqname,
    ) -> result<_, write-error>;

    /// Rename a value
    rename-value: func(
        tx: transaction,
        old-fqn: fqname,
        new-fqn: fqname,
    ) -> result<_, write-error>;
}

/// Workspace management
interface workspace {
    use morphir:ir@0.4.0.{
        naming.{package-path},
        distributions.{semver, distribution},
        document.{document-value},
    };

    // ============================================================
    // Types
    // ============================================================

    /// Workspace state
    enum workspace-state {
        /// Workspace is closed
        closed,
        /// Workspace is open and ready
        open,
        /// Workspace is being initialized
        initializing,
        /// Workspace has errors
        error,
    }

    /// Project state within workspace
    enum project-state {
        /// Project not yet loaded
        unloaded,
        /// Project is loading
        loading,
        /// Project is loaded and ready
        ready,
        /// Project has compilation errors
        error,
        /// Project is stale (needs recompilation)
        stale,
    }

    /// Workspace info
    record workspace-info {
        /// Workspace root path
        root: string,
        /// Workspace name (derived from root or config)
        name: string,
        /// Current state
        state: workspace-state,
        /// Projects in workspace
        projects: list<project-info>,
        /// Workspace-level configuration
        config: option<document-value>,
    }

    /// Project info
    record project-info {
        /// Project name (package path)
        name: package-path,
        /// Project version
        version: semver,
        /// Project root path (relative to workspace)
        path: string,
        /// Current state
        state: project-state,
        /// Source directory
        source-dir: string,
        /// Dependencies
        dependencies: list<dependency-info>,
    }

    /// Dependency info
    record dependency-info {
        /// Dependency name
        name: package-path,
        /// Required version
        version: semver,
        /// Whether dependency is resolved
        resolved: bool,
    }

    /// Workspace error
    variant workspace-error {
        /// Workspace not found
        not-found(string),
        /// Workspace already exists
        already-exists(string),
        /// Workspace is not open
        not-open,
        /// Project not found
        project-not-found(string),
        /// Project already exists
        project-already-exists(string),
        /// Invalid configuration
        invalid-config(string),
        /// IO error
        io-error(string),
    }

    /// Watch event type
    enum watch-event-type {
        /// File created
        created,
        /// File modified
        modified,
        /// File deleted
        deleted,
        /// File renamed
        renamed,
    }

    /// Watch event
    record watch-event {
        /// Event type
        event-type: watch-event-type,
        /// Affected path
        path: string,
        /// New path (for rename events)
        new-path: option<string>,
        /// Affected project (if determinable)
        project: option<package-path>,
    }

    // ============================================================
    // Workspace Lifecycle
    // ============================================================

    /// Create a new workspace
    create-workspace: func(
        /// Workspace root path
        root: string,
        /// Initial configuration
        config: option<document-value>,
    ) -> result<workspace-info, workspace-error>;

    /// Open an existing workspace
    open-workspace: func(
        /// Workspace root path
        root: string,
    ) -> result<workspace-info, workspace-error>;

    /// Close the current workspace
    close-workspace: func() -> result<_, workspace-error>;

    /// Get current workspace info
    get-workspace-info: func() -> result<workspace-info, workspace-error>;

    /// Update workspace configuration
    update-workspace-config: func(
        config: document-value,
    ) -> result<_, workspace-error>;

    // ============================================================
    // Project Management
    // ============================================================

    /// Add a project to the workspace
    add-project: func(
        /// Project name
        name: package-path,
        /// Project path (relative to workspace root)
        path: string,
        /// Initial version
        version: semver,
        /// Source directory
        source-dir: string,
    ) -> result<project-info, workspace-error>;

    /// Remove a project from the workspace
    remove-project: func(
        name: package-path,
    ) -> result<_, workspace-error>;

    /// Get project info
    get-project-info: func(
        name: package-path,
    ) -> result<project-info, workspace-error>;

    /// List all projects
    list-projects: func() -> result<list<project-info>, workspace-error>;

    /// Load a project (parse and compile)
    load-project: func(
        name: package-path,
    ) -> result<distribution, workspace-error>;

    /// Unload a project (free resources)
    unload-project: func(
        name: package-path,
    ) -> result<_, workspace-error>;

    /// Reload a project (recompile)
    reload-project: func(
        name: package-path,
    ) -> result<distribution, workspace-error>;

    // ============================================================
    // Dependency Management
    // ============================================================

    /// Add a dependency to a project
    add-dependency: func(
        project: package-path,
        dependency: package-path,
        version: semver,
    ) -> result<_, workspace-error>;

    /// Remove a dependency from a project
    remove-dependency: func(
        project: package-path,
        dependency: package-path,
    ) -> result<_, workspace-error>;

    /// Resolve all dependencies for a project
    resolve-dependencies: func(
        project: package-path,
    ) -> result<list<dependency-info>, workspace-error>;

    /// Resolve all dependencies for entire workspace
    resolve-all-dependencies: func() -> result<list<tuple<package-path, list<dependency-info>>>, workspace-error>;

    // ============================================================
    // File Watching
    // ============================================================

    /// Start watching workspace for changes
    start-watching: func() -> result<_, workspace-error>;

    /// Stop watching workspace
    stop-watching: func() -> result<_, workspace-error>;

    /// Poll for watch events (non-blocking)
    poll-events: func() -> list<watch-event>;

    // ============================================================
    // Workspace Operations
    // ============================================================

    /// Build all projects in workspace
    build-all: func() -> result<list<tuple<package-path, distribution>>, workspace-error>;

    /// Clean build artifacts
    clean: func(
        /// Specific project, or all if none
        project: option<package-path>,
    ) -> result<_, workspace-error>;

    /// Get workspace-wide diagnostics
    get-diagnostics: func() -> list<tuple<package-path, list<morphir:frontend@0.4.0.compiler.diagnostic>>>;
}
```

## World Definitions (`worlds.wit`)

```wit
package morphir:component@0.4.0;

use morphir:extension@0.4.0.{info, capabilities};
use morphir:frontend@0.4.0.{compiler};
use morphir:frontend@0.4.0 as frontend;
use morphir:backend@0.4.0.{generator, validator, transform};
use morphir:backend@0.4.0 as backend;
use morphir:vfs@0.4.0.{reader, writer, workspace};

// ============================================================
// MINIMAL EXTENSION (Info Only)
// ============================================================

/// Minimal extension - just provides info and health check
/// All extensions should start here before adding capabilities
world info-component {
    export info;
}

/// Extension with capability discovery
world discoverable-component {
    export info;
    export capabilities;
}

// ============================================================
// FRONTEND COMPONENTS (Source → IR)
// ============================================================

/// Minimal frontend compiler component (basic compilation only)
world minimal-compiler-component {
    export info;
    export compiler;
}

/// Frontend compiler component with capability discovery
world compiler-component {
    export info;
    export capabilities;
    export compiler;
}

/// Frontend with VFS access (for reading dependencies)
world compiler-with-vfs-component {
    import reader;
    export info;
    export compiler;
}

/// Frontend with streaming support
world streaming-compiler-component {
    export info;
    export capabilities;
    export compiler;
    export frontend:streaming;
}

/// Frontend with incremental support
world incremental-compiler-component {
    import reader;
    export info;
    export capabilities;
    export compiler;
    export frontend:incremental;
}

/// Full-featured frontend (all capabilities)
world full-compiler-component {
    import reader;
    export info;
    export capabilities;
    export compiler;
    export frontend:streaming;
    export frontend:incremental;
}

// ============================================================
// BACKEND COMPONENTS (IR → Target)
// ============================================================

/// Minimal code generator component
world minimal-generator-component {
    export info;
    export generator;
}

/// Code generator component with capability discovery
world generator-component {
    export info;
    export capabilities;
    export generator;
}

/// Generator with streaming support
world streaming-generator-component {
    export info;
    export capabilities;
    export generator;
    export backend:streaming;
}

/// Generator with incremental support
world incremental-generator-component {
    export info;
    export capabilities;
    export generator;
    export backend:incremental;
}

/// Full-featured generator (all capabilities)
world full-generator-component {
    export info;
    export capabilities;
    export generator;
    export backend:streaming;
    export backend:incremental;
}

/// Validator component
world validator-component {
    export info;
    export validator;
}

/// Full backend (generator + validator)
world backend-component {
    export info;
    export capabilities;
    export generator;
    export validator;
}

// ============================================================
// TRANSFORMER COMPONENTS (IR → IR)
// ============================================================

/// Standalone transformer (pure IR transformation)
world transform-component {
    export info;
    export transform;
}

/// Transformer with VFS access
world transformer-component {
    import reader;
    import writer;
    export info;
    export capabilities;
    export transform;
}

// ============================================================
// WORKSPACE COMPONENTS
// ============================================================

/// Workspace management component (daemon-side)
world workspace-manager-component {
    export info;
    export workspace;
}

/// Workspace-aware compiler
world workspace-compiler-component {
    import workspace;
    import reader;
    export info;
    export capabilities;
    export compiler;
}

// ============================================================
// FULL PIPELINE COMPONENTS
// ============================================================

/// Full toolchain component (frontend + backend)
world toolchain-component {
    import reader;
    export info;
    export capabilities;
    export compiler;
    export generator;
    export validator;
}

/// Toolchain with workspace support
world workspace-toolchain-component {
    import workspace;
    import reader;
    import writer;
    export info;
    export capabilities;
    export compiler;
    export generator;
    export validator;
}

/// Full plugin with all capabilities
world plugin-component {
    import reader;
    import writer;
    import workspace;
    export info;
    export capabilities;
    export compiler;
    export generator;
    export validator;
    export transform;
    export frontend:streaming;
    export frontend:incremental;
    export backend:streaming;
    export backend:incremental;
}
```

## Component Manifest

```json
{
  "name": "morphir-typescript-backend",
  "version": "1.0.0",
  "description": "TypeScript code generator for Morphir IR",
  "world": "morphir:component/backend-component@0.4.0",
  "exports": {
    "generator": {
      "target": "typescript",
      "granularities": ["distribution", "module", "definition"]
    },
    "validator": {
      "categories": ["typescript-compat", "naming"]
    }
  },
  "wasm": {
    "path": "morphir-typescript-backend.wasm",
    "sha256": "abc123..."
  }
}
```

## Security Model

| World | Imports | Access Level |
|-------|---------|--------------|
| `info-component` | None | Metadata only (minimal) |
| `discoverable-component` | None | Metadata + capability query |
| `minimal-compiler-component` | None | Pure function (source → IR) |
| `compiler-component` | None | Pure function with capabilities |
| `compiler-with-vfs-component` | VFS reader | Read-only (for dependencies) |
| `streaming-compiler-component` | None | Streaming compilation |
| `incremental-compiler-component` | VFS reader | Incremental with dependency graph |
| `full-compiler-component` | VFS reader | All frontend capabilities |
| `minimal-generator-component` | None | Pure function (IR → target) |
| `generator-component` | None | Pure function with capabilities |
| `streaming-generator-component` | None | Streaming generation |
| `incremental-generator-component` | None | Incremental generation |
| `full-generator-component` | None | All codegen capabilities |
| `validator-component` | None | Pure function |
| `backend-component` | None | Generator + validator |
| `transform-component` | None | Pure IR transformation |
| `transformer-component` | VFS reader, writer | Scoped to distribution |
| `workspace-manager-component` | None (exports only) | Workspace lifecycle management |
| `workspace-compiler-component` | Workspace, VFS reader | Workspace-aware compilation |
| `toolchain-component` | VFS reader | Full compilation pipeline |
| `workspace-toolchain-component` | Workspace, VFS r/w | Full pipeline with workspace |
| `plugin-component` | Full VFS + workspace | Maximum access (all capabilities) |

Components are sandboxed:
- No filesystem access outside VFS
- No network access
- No environment variables
- Memory and CPU limits enforced
