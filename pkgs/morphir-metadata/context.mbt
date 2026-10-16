///|
priv struct Term {
  iri : String
  coercion : String?
  prefix : Bool
  is_protected : Bool
} derive(Eq)

///|
priv struct Context {
  terms : Map[String, Term]
  mut vocab : String?
}

///|
fn Context::new() -> Context {
  { terms: Map([]), vocab: None, }
}

///|
fn Context::copy(self : Context) -> Context {
  { terms: self.terms.copy(), vocab: self.vocab, }
}

///|
fn check_reference(uri : String, stem~ : Bool = false) -> Unit raise {
  let parsed = address(uri)
  let parts = parsed.fragment.split("/").collect()
  if parts.length() != 5 ||
    parts[0].to_owned() != "" ||
    parts[1].to_owned() != "module" ||
    (parts[3].to_owned() != "value" && parts[3].to_owned() != "type") ||
    (stem && parts[4].to_owned() != "") {
    raise Invalid(
      "metadata.invalid_predicate_uri", uri, "Use a declaration URI or declaration stem",
    )
  }
  let module_name = @ir.Path::parse(
    parts[2]
    .to_owned()
    .split("%2F")
    .map(StringView::to_owned)
    .collect()
    .join("/"),
  ) catch {
    _ =>
      raise Invalid(
        "metadata.invalid_predicate_uri", uri, "Invalid module path",
      )
  }
  if module_name
    .to_canonical()
    .split("/")
    .map(StringView::to_owned)
    .collect()
    .join("%2F") !=
    parts[2].to_owned() {
    raise Invalid(
      "metadata.invalid_predicate_uri", uri, "Noncanonical module encoding",
    )
  }
  if !stem {
    let local_name = @ir.Name::parse(parts[4].to_owned()) catch {
      _ =>
        raise Invalid(
          "metadata.invalid_predicate_uri", uri, "Use a canonical local name; camelCase requires an explicit alias",
        )
    }
    if local_name.to_canonical() != parts[4].to_owned() {
      raise Invalid(
        "metadata.invalid_predicate_uri", uri, "Use a canonical local name; camelCase requires an explicit alias",
      )
    }
  }
}

///|
fn Context::expand(self : Context, key : String) -> (String, String?) raise {
  if self.terms.get(key) is Some(term) && !term.prefix {
    return (term.iri, term.coercion)
  }
  if key.has_prefix("morphir://ir/") {
    check_reference(key)
    return (key, None)
  }
  let parts = key.split(":").collect()
  if parts.length() == 2 &&
    self.terms.get(parts[0].to_owned()) is Some(term) &&
    term.prefix {
    let iri = term.iri + parts[1].to_owned()
    check_reference(iri)
    return (iri, None)
  }
  if !key.contains(":") && self.vocab is Some(stem) {
    let iri = stem + key
    check_reference(iri)
    return (iri, None)
  }
  raise Invalid(
    "metadata.unresolved_term", key, "Supply an explicit alias, declared prefix or @vocab",
  )
}

///|
fn bool_true(value : @ion.IonValue, owner : String) -> Unit raise {
  if !value.annotations().is_empty() || !(value.kind() is Bool(true)) {
    raise Invalid(
      "metadata.invalid_context_form", owner, "This context flag only admits true",
    )
  }
}

///|
fn apply_inline(
  context : Context,
  value : @ion.IonValue,
  imports : Bool,
) -> Unit raise {
  let record = fields(value, "@context")
  let names = record.keys().collect()
  names.sort()
  for name in names {
    if name.has_prefix("@") && name != "@vocab" {
      raise Invalid(
        "metadata.unsupported_context_keyword", name, "Remove unsupported context keyword",
      )
    }
  }
  // Prefixes are declared first; compact targets can refer forward to them.
  let pending = []
  for name in names {
    if name == "@vocab" {
      let stem = text(record[name], name)
      check_reference(stem, stem=true)
      if imports && context.vocab is Some(old) && old != stem {
        raise Invalid(
          "metadata.context_vocab_collision", name, "Imported contexts disagree on @vocab",
        )
      }
      context.vocab = Some(stem)
      continue
    }
    if name.is_empty() || name.has_prefix("@") {
      raise Invalid("metadata.invalid_context_form", name, "Invalid term name")
    }
    let value = record[name]
    let term = match value.kind() {
      String(_) =>
        {
          iri: text(value, name),
          coercion: None,
          prefix: false,
          is_protected: false,
        }
      Struct(_) => {
        let definition = fields(value, name)
        for key in definition.keys() {
          if !["@id", "@type", "@prefix", "@protected"].contains(key) {
            raise Invalid(
              "metadata.unsupported_context_keyword", key, "Remove unsupported term-definition keyword",
            )
          }
        }
        let coercion = definition.get("@type").map(v => text(v, name))
        if coercion is Some(c) && c != "@json" && c != "@id" {
          raise Invalid(
            "metadata.invalid_context_form", name, "Only @json and @id coercions are admitted",
          )
        }
        if definition.get("@prefix") is Some(v) {
          bool_true(v, name)
        }
        if definition.get("@protected") is Some(v) {
          bool_true(v, name)
        }
        {
          iri: text(required(definition, "@id", name), name),
          coercion,
          prefix: definition.contains("@prefix"),
          is_protected: definition.contains("@protected"),
        }
      }
      _ =>
        raise Invalid(
          "metadata.invalid_context_form", name, "Term definitions must be strings or objects",
        )
    }
    if term.prefix {
      if term.coercion is Some(_) {
        raise Invalid(
          "metadata.invalid_context_form", name, "Prefixes cannot carry a coercion",
        )
      }
      check_reference(term.iri, stem=true)
      set_term(context, name, term, imports)
    } else {
      pending.push((name, term))
    }
  }
  for (name, term) in pending {
    if !term.iri.has_prefix("morphir://ir/") && !term.iri.contains(":") {
      raise Invalid(
        "metadata.invalid_context_form", name, "A term target must be an absolute declaration URI or compact IRI",
      )
    }
    let iri = if term.iri.has_prefix("morphir://ir/") {
      term.iri
    } else {
      context.expand(term.iri).0
    }
    check_reference(iri)
    set_term(context, name, { ..term, iri, }, imports)
  }
}

///|
fn set_term(
  context : Context,
  name : String,
  term : Term,
  imports : Bool,
) -> Unit raise {
  if context.terms.get(name) is Some(old) && old != term {
    if old.is_protected {
      raise Invalid(
        "metadata.protected_term_redefinition", name, "Retain the protected binding",
      )
    }
    if imports {
      raise Invalid(
        "metadata.context_term_collision", name, "Imported contexts disagree; a trailing override cannot cure the collision",
      )
    }
  }
  context.terms[name] = term
}

///|
fn Context::merge_import(self : Context, other : Context) -> Unit raise {
  if other.vocab is Some(v) {
    if self.vocab is Some(old) && old != v {
      raise Invalid(
        "metadata.context_vocab_collision", "@vocab", "Imported contexts disagree",
      )
    }
    self.vocab = Some(v)
  }
  for name, term in other.terms {
    set_term(self, name, term, true)
  }
}

///|
fn resolve_context(
  value : @ion.IonValue,
  inherited : Context,
  capabilities : Capabilities,
  base : String,
  seen : Map[String, Bool],
  active : Map[String, Bool],
  depth~ : Int32 = 0,
) -> Context raise {
  if !value.annotations().is_empty() {
    raise Invalid(
      "metadata.invalid_context_form", base, "Context must be unannotated JSON data",
    )
  }
  if depth > 32 {
    raise Invalid(
      "metadata.context_limit", base, "Context import depth exceeds 32",
    )
  }
  fn reference(resource_ref : String) -> Context raise {
    let content_prefix = "morphir://context/sha256/"
    let content_addressed = resource_ref.has_prefix(content_prefix)
    if content_addressed {
      if !digest(resource_ref[content_prefix.length():].to_owned()) {
        raise Invalid(
          "metadata.invalid_context_reference", resource_ref, "Invalid content digest",
        )
      }
    } else {
      if resource_ref.contains(":") ||
        resource_ref.has_prefix("/") ||
        resource_ref.contains("\\") ||
        !resource_ref.has_suffix(".jsonld") {
        raise Invalid(
          "metadata.remote_context_forbidden", resource_ref, "Use a confined relative .jsonld path or content-addressed context",
        )
      }
      if base == "" {
        raise Invalid(
          "metadata.relative_import_without_base", resource_ref, "Content-addressed contexts have no relative file base",
        )
      }
    }
    guard capabilities.load_context is Some(load) else {
      raise Invalid(
        "metadata.context_resource_unavailable", resource_ref, "Configure an explicit trusted context loader",
      )
    }
    // Host loader owns confinement and symlink resolution, which the portable
    // core cannot perform. It must reject escape from the accepted root.
    let resource = load(resource_ref, base)
    if active.contains(resource.url) {
      raise Invalid(
        "metadata.context_import_cycle",
        resource.url,
        "Remove the cyclic import",
      )
    }
    if seen.contains(resource.url) {
      raise Invalid(
        "metadata.duplicate_context_import",
        resource.url,
        "Import each resource once per transitive closure",
      )
    }
    if seen.length() >= 256 {
      raise Invalid(
        "metadata.context_limit", resource_ref, "Context closure exceeds 256 resources",
      )
    }
    if resource.bytes.length() > 1048576 {
      raise Invalid(
        "metadata.context_limit", resource_ref, "Context exceeds 1 MiB",
      )
    }
    let hash = @crypto.bytes_to_hex_string(@crypto.sha256(resource.bytes))
    if !digest(resource.sha256) ||
      hash != resource.sha256 ||
      (
        content_addressed &&
        hash != resource_ref[content_prefix.length():].to_owned()
      ) {
      raise Invalid(
        "metadata.context_digest_mismatch", resource_ref, "Use exact inventoried context bytes",
      )
    }
    let source = @utf8.decode(resource.bytes[:]) catch {
      _ =>
        raise Invalid(
          "metadata.invalid_context_form", resource_ref, "Context must be UTF-8 JSON",
        )
    }
    ignore(@json.parse(source)) catch {
      _ =>
        raise Invalid(
          "metadata.invalid_context_form", resource_ref, "Context must be JSON, not general Ion",
        )
    }
    let document = fields(@ion_text.read_ion(source[:]), resource_ref)
    if document.length() != 1 || !document.contains("@context") {
      raise Invalid(
        "metadata.invalid_context_form", resource_ref, "Context document needs exactly one @context member",
      )
    }
    seen[resource.url] = true
    active[resource.url] = true
    let resolved = resolve_context(
      document["@context"],
      Context::new(),
      capabilities,
      if content_addressed {
        ""
      } else {
        resource.url
      },
      seen,
      active,
      depth=depth + 1,
    )
    active.remove(resource.url)
    resolved
  }
  let output = inherited.copy()
  match value.kind() {
    Struct(_) => apply_inline(output, value, false)
    String(_) => {
      let imported = reference(text(value, "@context"))
      if imported.vocab is Some(v) {
        output.vocab = Some(v)
      }
      for name, term in imported.terms {
        set_term(output, name, term, false)
      }
    }
    List(items) => {
      if items.is_empty() || !(items[0].kind() is String(_)) {
        raise Invalid(
          "metadata.invalid_context_form", "@context", "An array needs one or more reference strings, then at most one object",
        )
      }
      let imports = Context::new()
      let mut trailing : @ion.IonValue? = None
      for item in items {
        match item.kind() {
          String(_) if trailing is None =>
            imports.merge_import(reference(text(item, "@context")))
          Struct(_) if trailing is None => trailing = Some(item)
          _ =>
            raise Invalid(
              "metadata.invalid_context_form", "@context", "No repeated object, nested array or reference after an object",
            )
        }
      }
      if imports.vocab is Some(v) {
        output.vocab = Some(v)
      }
      for name, term in imports.terms {
        set_term(output, name, term, false)
      }
      if trailing is Some(value) {
        apply_inline(output, value, false)
      }
    }
    _ =>
      raise Invalid(
        "metadata.invalid_context_form", "@context", "Use an object, reference string or bounded array",
      )
  }
  output
}
