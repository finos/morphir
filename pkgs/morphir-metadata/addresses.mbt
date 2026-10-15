///|
pub fn value_uri(file : @ir.IRFile, name : @ir.FQName) -> String raise {
  ignore(@ir.FQName::parse(name.to_canonical()))
  "morphir://ir/pkg/" +
  name.package_name.to_canonical() +
  "?format=" +
  file.format_version.to_release_string() +
  "#/module/" +
  name.module_name
  .to_canonical()
  .split("/")
  .map(StringView::to_owned)
  .collect()
  .join("%2F") +
  "/value/" +
  name.local_name.to_canonical()
}

///|
priv struct Address {
  package_name : @ir.Path
  format : String
  revision : String?
  fragment : String
}

///|
/// A bounded named-node URI reader. Ordered children, workspace aliases and
/// positional guards are not supported by the value-definition consumer.
fn address(uri : String) -> Address raise {
  let prefix = "morphir://ir/pkg/"
  guard uri.has_prefix(prefix) else {
    raise Invalid(
      "metadata.invalid_node_uri", uri, "Use a canonical package Node URI",
    )
  }
  let pieces = uri[prefix.length():].split("#").collect()
  if pieces.length() != 2 {
    raise Invalid(
      "metadata.invalid_node_uri", uri, "Supply one semantic fragment",
    )
  }
  let query = pieces[0].split("?").collect()
  if query.length() != 2 {
    raise Invalid(
      "metadata.invalid_node_uri", uri, "Supply an exact format release",
    )
  }
  let package_name = @ir.Path::parse(query[0].to_owned()) catch {
    _ =>
      raise Invalid(
        "metadata.invalid_node_uri", uri, "Package path must use canonical Morphir names",
      )
  }
  if package_name.to_canonical() != query[0].to_owned() {
    raise Invalid("metadata.invalid_node_uri", uri, "Noncanonical package path")
  }
  let parameters = Map([])
  for p in query[1].to_owned().split("&") {
    let pair = p.split("=").collect()
    if pair.length() != 2 || parameters.contains(pair[0].to_owned()) {
      raise Invalid(
        "metadata.invalid_node_uri", uri, "Duplicate or malformed query parameter",
      )
    }
    parameters[pair[0].to_owned()] = pair[1].to_owned()
  }
  guard parameters.get("format") is Some(format) else {
    raise Invalid("metadata.invalid_node_uri", uri, "Missing format")
  }
  ignore(@version.FormatVersion::parse(format)) catch {
    _ =>
      raise Invalid(
        "metadata.invalid_node_uri", uri, "Use an exact three-component format release",
      )
  }
  if parameters.length() > 2 ||
    parameters.keys().any(k => k != "format" && k != "rev") {
    raise Invalid(
      "metadata.invalid_node_uri", uri, "Unsupported query parameter for a named declaration",
    )
  }
  let revision = parameters.get("rev")
  if revision is Some(r) &&
    (!r.has_prefix("sha256:") || !digest(r[7:].to_owned())) {
    raise Invalid(
      "metadata.invalid_node_uri", uri, "Use rev=sha256:<64 lowercase hex digits>",
    )
  }
  let canonical = prefix +
    package_name.to_canonical() +
    "?format=" +
    format +
    revision.map(r => "&rev=" + r).unwrap_or("") +
    "#" +
    pieces[1].to_owned()
  if canonical != uri {
    raise Invalid(
      "metadata.invalid_node_uri", uri, "Use canonical query order: format, then rev",
    )
  }
  { package_name, format, revision, fragment: pieces[1].to_owned(), }
}

///|
fn declaration(uri : String) -> (@ir.FQName, Address) raise {
  let parsed = address(uri)
  let parts = parsed.fragment.split("/").collect()
  if parts.length() != 5 ||
    parts[0].to_owned() != "" ||
    parts[1].to_owned() != "module" ||
    parts[3].to_owned() != "value" {
    raise Invalid(
      "metadata.unsupported_subject_role", uri, "This consumer requires a ValueDefinition URI, not its body or attributes",
    )
  }
  let module_path = parts[2]
    .to_owned()
    .split("%2F")
    .map(StringView::to_owned)
    .collect()
    .join("/")
  let module_name = @ir.Path::parse(module_path) catch {
    _ =>
      raise Invalid(
        "metadata.invalid_node_uri", uri, "Invalid canonical module path",
      )
  }
  let local_name = @ir.Name::parse(parts[4].to_owned()) catch {
    _ =>
      raise Invalid(
        "metadata.invalid_node_uri", uri, "Invalid canonical value name",
      )
  }
  let encoded = module_name
    .to_canonical()
    .split("/")
    .map(StringView::to_owned)
    .collect()
    .join("%2F")
  if encoded != parts[2].to_owned() ||
    local_name.to_canonical() != parts[4].to_owned() {
    raise Invalid(
      "metadata.invalid_node_uri", uri, "Noncanonical fragment encoding",
    )
  }
  ({ package_name: parsed.package_name, module_name, local_name, }, parsed)
}

///|
/// Recognize the 4.1 target-names declaration, including optional native revision
/// pins. Recognition grants no authority and does not check revision equality;
/// admission checks the pin against the freshly restored native Library.
pub fn is_target_names_predicate(uri : String) -> Bool raise {
  if !uri.has_prefix("morphir://ir/pkg/morphir/naming?") {
    return false
  }
  let (name, parsed) = declaration(uri)
  name.to_canonical() == "morphir/naming:naming#target-names" &&
  parsed.format == "4.1.0"
}
