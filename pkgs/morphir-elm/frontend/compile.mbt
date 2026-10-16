///|
/// Compiles an Elm project to a Morphir IR library, as `morphir-elm make` 2.100.0 does. `package_name` is the
/// package name, dotted or with `/` (`Morphir.Sample` or `Morphir/Sample`), and `exposed` holds the exposed module
/// names relative to the package, as in `morphir.json`. Each pass reports all of its problems; the first pass with
/// problems stops the compile. The last pass infers the type of every value and pattern node; its problems are
/// `elm.type`. `output` chooses the output modules: `Parity` (the default) keeps the modules that morphir-elm keeps;
/// `Referenced` also keeps every module that the output names.
pub fn compile_project(
  sources : Array[ElmSource],
  package_name : String,
  exposed : Array[String],
  output~ : OutputModules = Parity,
) -> @ir.IRFile raise ElmFailed {
  compile_project_output(sources, package_name, exposed, output~).ir
}

///|
/// `compile_project` with the origin of each value declaration that the output keeps.
pub fn compile_project_output(
  sources : Array[ElmSource],
  package_name : String,
  exposed : Array[String],
  output~ : OutputModules = Parity,
) -> ProjectOutput raise ElmFailed {
  let package_name = elm_package(package_name)
  if exposed.is_empty() {
    raise ElmFailed([
      problem(
        "elm.exposed_module",
        "a project must expose at least one module",
        "",
        None,
      ),
    ])
  }
  // morphir-elm parses every source and checks the import cycles of all modules, but it checks the other rules
  // only in the modules that it processes: the exposed modules and the modules that they import, transitively.
  let parsed = parse_sources(sources, package_name)
  let all = parsed.map(entry => entry.0)
  let exposed_names = exposed.map(e => package_name + "." + e)
  let reached : Set[String] = Set([])
  for
    m in imported_modules(
      all,
      all.filter(m => exposed_names.contains(dotted(m.name))),
    ) {
    reached.add(dotted(m.name))
  }
  let rule_problems : Array[ElmProblem] = []
  for entry in parsed {
    if reached.contains(dotted(entry.0.name)) {
      rule_problems.append(entry.1)
    }
  }
  fail_if_any(rule_problems)
  check_cycles(all)
  let modules = parsed.filter(entry => entry.1.is_empty()).map(entry => entry.0)
  let pkg_segs = package_segments(package_name)
  let roots = check_exposed(modules, package_name, exposed)
  let processed = imported_modules(modules, roots)
  let processed_names : Set[String] = Set([])
  for m in processed {
    processed_names.add(dotted(m.name))
  }
  // The exposing lists, imports and declarations of the processed modules.
  let (project, module_problems) = @resolve.Project::with_problems(
    pkg_segs, modules,
  )
  let resolve_problems : Array[ElmProblem] = []
  for m in modules {
    if processed_names.contains(dotted(m.name)) {
      resolve_problems.append(
        module_problems.get(dotted(m.name)).unwrap_or([]).map(from_resolve),
      )
    }
  }
  fail_if_any(resolve_problems)
  // The reference problems of all processed modules are raised together.
  let problems : Array[ElmProblem] = []
  let body_values : Array[Array[@ir.FQName]] = []
  for m in processed {
    let found = project.module_references(m.name)
    problems.append(found.problems.map(from_resolve))
    body_values.push(found.values)
  }
  fail_if_any(problems)
  let contents : Map[String, String] = Map([])
  for source in sources {
    contents[source.path] = source.content
  }
  let lowered : Array[(@ir.Path, @ir.ModuleDefinition)] = []
  // The source path of each module, by canonical module path, to place the problems of inference.
  let module_sources : Map[String, String] = Map([])
  let origins : Array[DeclarationOrigin] = []
  for m in processed {
    let module_name = module_path(m.name, pkg_segs)
    module_sources[module_name.to_canonical()] = m.path
    let definition = lower_module(
      project,
      m,
      module_name,
      contents.get(m.path).unwrap_or(""),
      problems,
      origins,
    )
    lowered.push((module_name, definition))
  }
  fail_if_any(problems)
  // The output keeps the modules that the exposed modules reach in the module graph. They are Private, except the
  // exposed modules and the modules that the exposed modules show in public types and value signatures.
  let edges : Map[@ir.Path, Array[@ir.Path]] = Map([])
  for i, entry in lowered {
    edges[entry.0] = module_dependencies(entry.0, entry.1, body_values[i])
  }
  let exposed = roots.map(m => module_path(m.name, pkg_segs))
  let used = used_modules(exposed, edges)
  let kept : Map[@ir.Path, @ir.ModuleDefinition] = Map([])
  for entry in lowered {
    if used.contains(entry.0) {
      kept[entry.0] = entry.1
    }
  }
  let package_name = @mapping.elm_path(pkg_segs)
  let public_modules = implicitly_exposed(package_name, kept, exposed)
  // Inference sees every processed module, as in morphir-elm: a value signature can name a type of a module that
  // the output drops. The output then keeps the modules that are used.
  let all_modules : @ir.PackageDefinition = { modules: Map([]), }
  for entry in lowered {
    let access : @ir.Access = if exposed.contains(entry.0) ||
      public_modules.contains(entry.0) {
      Public
    } else {
      Private
    }
    all_modules.modules[entry.0] = { access, value: entry.1, }
  }
  let file = @ir.IRFile::new(Library(package_name, Map([]), all_modules)) catch {
    e => abort("the current IR version is not valid: " + @debug.to_string(e))
  }
  // The last pass: the shared IR inference types every value and pattern node.
  guard infer_library(file, module_sources).distribution
    is Library(_, _, inferred) else {
    abort("inference returns a library for a library")
  }
  let library : @ir.PackageDefinition = { modules: Map([]), }
  let selected : Set[@ir.Path] = Set([])
  for path, _ in kept {
    selected.add(path)
  }
  if output is Referenced {
    add_referenced_modules(package_name, inferred.modules, selected)
  }
  for path, m in inferred.modules {
    if selected.contains(path) {
      library.modules[path] = m
    }
  }
  let kept_origins = origins.filter(o => selected.contains(o.module_name))
  // Lexical order by code unit, so that the list reads alphabetically; `Compare for String` is shortlex.
  kept_origins.sort_by((a, b) => {
    let by_module = a.module_name.to_canonical()[:].lexical_compare(
      b.module_name.to_canonical()[:],
    )
    if by_module != 0 {
      by_module
    } else {
      a.name.to_canonical()[:].lexical_compare(b.name.to_canonical()[:])
    }
  })
  {
    ir: @ir.IRFile::new(Library(package_name, Map([]), library)) catch {
      e => abort("the current IR version is not valid: " + @debug.to_string(e))
    },
    origins: kept_origins,
  }
}

///|
fn from_resolve(p : @resolve.ResolveProblem) -> ElmProblem {
  {
    code: p.code,
    message: p.message,
    path: p.path,
    location: p.range.map(location_of),
  }
}

///|
/// Every exposed name must be a parsed module of the package. A missing module is reported at the source path
/// where it is expected. Returns the exposed modules in the order given.
fn check_exposed(
  modules : Array[@resolve.ParsedModule],
  package_name : String,
  exposed : Array[String],
) -> Array[@resolve.ParsedModule] raise ElmFailed {
  let by_name : Map[String, @resolve.ParsedModule] = Map([])
  for m in modules {
    by_name[dotted(m.name)] = m
  }
  let problems : Array[ElmProblem] = []
  let roots : Array[@resolve.ParsedModule] = []
  for e in exposed {
    let name = package_name + "." + e
    match by_name.get(name) {
      Some(m) => if !roots.iter().any(r => r.name == m.name) { roots.push(m) }
      None =>
        problems.push(
          problem(
            "elm.exposed_module",
            "the exposed module \{name} has no source",
            name.replace_all(old=".", new="/") + ".elm",
            None,
          ),
        )
    }
  }
  fail_if_any(problems)
  roots
}

///|
/// Lowers every type definition and value definition of a module. Lowering problems go to `problems`.
fn lower_module(
  project : @resolve.Project,
  m : @resolve.ParsedModule,
  module_name : @ir.Path,
  content : String,
  problems : Array[ElmProblem],
  origins : Array[DeclarationOrigin],
) -> @ir.ModuleDefinition {
  let scope = project.scope(m.name)
  let exports = project.exports(m.name)
  let docs = DocComments::new(m.file)
  let types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ] = Map([])
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map([])
  for d in m.file.declarations {
    let doc = Some(docs.take(declaration_start_row(d, content)).unwrap_or(""))
    try {
      match d.value {
        FunctionDeclaration(f) => {
          let (name, definition, parameters) = @lower.lower_value_definition(
            scope, f,
          )
          values[@mapping.elm_name(name)] = {
            access: value_access(exports, name),
            value: { doc, value: definition, },
          }
          origins.push({
            module_name,
            name: @mapping.elm_name(name),
            source_name: name,
            path: m.path,
            span: location_of(f.declaration.value.name.range),
            parameters: parameters.map(p => (p.0, location_of(p.1))),
          })
        }
        _ =>
          if @lower.lower_type_definition(scope, d.value)
            is Some((name, definition, _)) {
            let (access, constructors) = type_access(exports, name)
            let definition : @ir.TypeDefinition = match definition {
              CustomTypeDefinition(params, ctors) =>
                CustomTypeDefinition(params, { ..ctors, access: constructors, })
              other => other
            }
            types[@mapping.elm_name(name)] = {
              access,
              value: { doc, value: definition, },
            }
          }
      }
    } catch {
      @lower.LowerError(code, message, range) =>
        problems.push(problem(code, message, m.path, range))
    }
  }
  { types, values, doc: module_doc(docs), }
}

///|
/// The access of a type and of its constructors: `T(..)` and `exposing (..)` export both, `T` only the type.
fn type_access(
  exports : @resolve.Exports,
  name : String,
) -> (@ir.Access, @ir.Access) {
  if exports.all {
    return (Public, Public)
  }
  match exports.types.get(name) {
    Some(true) => (Public, Public)
    Some(false) => (Public, Private)
    None => (Private, Private)
  }
}

///|
fn value_access(exports : @resolve.Exports, name : String) -> @ir.Access {
  if exports.all || exports.values.contains(name) {
    Public
  } else {
    Private
  }
}

///|
/// All comments of a module in source order, as elm-syntax 7 lists them, and which of them are already a
/// declaration doc. krueger moves some doc comments onto the declarations. They go back into this list, because
/// morphir-elm attaches a doc by rows, not as krueger does.
priv struct DocComments {
  comments : Array[@ast.Node[String]]
  used : Array[Bool]
}

///|
fn DocComments::new(file : @ast.File) -> DocComments {
  let comments = file.comments.to_owned()
  for d in file.declarations {
    if declaration_doc(d.value) is Some(doc) {
      comments.push(doc)
    }
  }
  comments.sort_by((a, b) => {
    let row = a.range.start.row.compare(b.range.start.row)
    if row != 0 {
      row
    } else {
      a.range.start.column.compare(b.range.start.column)
    }
  })
  { comments, used: Array::make(comments.length(), false), }
}

///|
fn declaration_doc(d : @ast.Declaration) -> @ast.Node[String]? {
  match d {
    FunctionDeclaration(f) => f.documentation
    AliasDeclaration(a) => a.documentation
    CustomTypeDeclaration(t) => t.documentation
    _ => None
  }
}

///|
/// The doc of the declaration that starts on `start_row`, as elm-syntax 7 finds it: the first comment that ends
/// on the row before, when it is a `{-|` comment.
fn DocComments::take(self : DocComments, start_row : Int32) -> String? {
  for i, c in self.comments {
    if c.range.end.row + 1 == start_row {
      if self.used[i] || !c.value.has_prefix("{-|") {
        return None
      }
      self.used[i] = true
      return @lower.doc_text(Some(c))
    }
  }
  None
}

///|
/// The module doc: the first `{-|` comment that is not a declaration doc. morphir-elm drops the first 3 and the
/// last 3 characters of the comment, so the character before `-}` goes too: `{-| Doc. -}` gives `" Doc."` and
/// `{-| Doc.-}` gives `" Doc"`.
fn module_doc(docs : DocComments) -> String? {
  for i, c in docs.comments {
    if !docs.used[i] && c.value.has_prefix("{-|") {
      return Some(drop_ends(c.value, 3))
    }
  }
  None
}

///|
/// `text` without its first `n` and last `n` UTF-16 code units, as Elm's `String.dropLeft` and
/// `String.dropRight` do. Empty when `text` is shorter than `2 * n`.
fn drop_ends(text : String, n : Int32) -> String {
  if text.length() < 2 * n {
    ""
  } else {
    text.unsafe_substring(start=n, end=text.length() - n)
  }
}

///|
/// The row of the first token of a declaration, not counting its doc. When krueger attached a doc, the node range
/// starts at the doc, so the row comes from the signature or name; for a type it is the row of the `type` keyword,
/// found in the source after the doc.
fn declaration_start_row(
  d : @ast.Node[@ast.Declaration],
  content : String,
) -> Int32 {
  match d.value {
    FunctionDeclaration(f) =>
      match f.signature {
        Some(s) => s.range.start.row
        None => f.declaration.range.start.row
      }
    AliasDeclaration({ documentation: Some(doc), .. })
    | CustomTypeDeclaration({ documentation: Some(doc), .. }) =>
      next_token_row(content, doc.range.end)
    _ => d.range.start.row
  }
}

///|
/// The row of the first token at or after `from`, past whitespace and comments. Columns count code points, as in
/// krueger.
fn next_token_row(content : String, from : @ast.Location) -> Int32 {
  let chars = content.to_array()
  let mut row = 1
  let mut column = 1
  let mut i = 0
  fn step() {
    if chars[i] == '\n' {
      row += 1
      column = 1
    } else {
      column += 1
    }
    i += 1
  }

  fn at(first : Char, second : Char) -> Bool {
    i + 1 < chars.length() && chars[i] == first && chars[i + 1] == second
  }

  while i < chars.length() &&
        (row < from.row || (row == from.row && column < from.column)) {
    step()
  }
  let mut depth = 0
  while i < chars.length() {
    if depth > 0 {
      if at('-', '}') {
        step()
        step()
        depth -= 1
      } else if at('{', '-') {
        step()
        step()
        depth += 1
      } else {
        step()
      }
    } else if chars[i] is (' ' | '\t' | '\r' | '\n') {
      step()
    } else if at('-', '-') {
      while i < chars.length() && chars[i] != '\n' {
        step()
      }
    } else if at('{', '-') {
      step()
      step()
      depth = 1
    } else {
      return row
    }
  }
  row
}
