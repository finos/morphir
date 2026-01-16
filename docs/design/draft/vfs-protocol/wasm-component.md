---
title: WASM Component Model
sidebar_label: WASM Components
sidebar_position: 12
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
├── morphir-frontend/
│   └── compiler.wit       # Source → IR compilation
├── morphir-backend/
│   ├── generator.wit      # IR → target code generation
│   └── validator.wit      # Validation interface
├── morphir-vfs/
│   ├── reader.wit         # VFS read access
│   └── writer.wit         # VFS write access
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
```

## World Definitions (`worlds.wit`)

```wit
package morphir:component@0.4.0;

use morphir:frontend@0.4.0.{compiler};
use morphir:backend@0.4.0.{generator, validator};
use morphir:vfs@0.4.0.{reader, writer};

// ============================================================
// FRONTEND COMPONENTS (Source → IR)
// ============================================================

/// Frontend compiler component
world compiler-component {
    export compiler;
}

/// Frontend with VFS access (for reading dependencies)
world compiler-with-vfs-component {
    import reader;
    export compiler;
}

// ============================================================
// BACKEND COMPONENTS (IR → Target)
// ============================================================

/// Code generator component
world generator-component {
    export generator;
}

/// Validator component
world validator-component {
    export validator;
}

/// Full backend (generator + validator)
world backend-component {
    export generator;
    export validator;
}

// ============================================================
// TRANSFORMER COMPONENTS (IR → IR)
// ============================================================

/// Transformer with VFS access
world transformer-component {
    import reader;
    import writer;

    /// Transformation interface
    export transform: interface {
        use morphir:backend@0.4.0.generator.{diagnostic};

        record transform-options {
            dry-run: bool,
            custom: option<string>,
        }

        record transform-result {
            success: bool,
            files-modified: u32,
            diagnostics: list<diagnostic>,
        }

        run: func(options: transform-options) -> transform-result;
    };
}

// ============================================================
// FULL PIPELINE COMPONENTS
// ============================================================

/// Full toolchain component (frontend + backend)
world toolchain-component {
    import reader;
    export compiler;
    export generator;
    export validator;
}

/// Full plugin with all capabilities
world plugin-component {
    import reader;
    import writer;
    export compiler;
    export generator;
    export validator;
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
| `compiler-component` | None | Pure function (source → IR) |
| `compiler-with-vfs-component` | VFS reader | Read-only (for dependencies) |
| `generator-component` | None | Pure function (IR → target) |
| `validator-component` | None | Pure function |
| `backend-component` | None | Pure function |
| `transformer-component` | VFS reader, writer | Scoped to distribution |
| `toolchain-component` | VFS reader | Full compilation pipeline |
| `plugin-component` | Full VFS | Maximum access |

Components are sandboxed:
- No filesystem access outside VFS
- No network access
- No environment variables
- Memory and CPU limits enforced
