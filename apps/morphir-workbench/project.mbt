///|
/// One file of a workbench project, with its path relative to the project root.
priv struct ProjectFile {
  path : @ids.SourcePath
  content : String
}

///|
/// A compile request after parsing at the worker boundary. A `source` request becomes a project of one file.
priv struct ProjectRequest {
  name : @ids.SourcePackageName
  language : @ids.LanguageId
  provider : @ids.ProviderId?
  profile : @ids.ProfileId?
  files : Array[ProjectFile]
  exposed : Array[@ids.SourceModuleName]
}

///|
fn optional_text(value : Json, key : String) -> String? raise {
  match @wire.optional(value, key) {
    None => None
    Some(String(text)) => Some(text)
    _ =>
      raise @wire.Invalid(
        "workbench.invalid_request",
        key + " must be a string",
      )
  }
}

///|
/// A package name for a generated morphir.toml: letters, digits, `_`, `.`, `/` and `-` only.
fn package_name(text : String) -> @ids.SourcePackageName raise {
  let safe = text
    .to_array()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '/' ||
      c == '-'
    })
  if !safe {
    raise @wire.Invalid(
      "workbench.invalid_package",
      "Invalid package name: " + text,
    )
  }
  @ids.SourcePackageName::parse(text)
}

///|
/// The module name in an Elm module header (`module A.B exposing (..)`, `port module` or `effect module`). It skips
/// white space, `--` comments and nested `{- -}` comments before the header.
fn elm_module_name(source : String) -> String? {
  let chars = source.to_array()
  let n = chars.length()
  let words : Array[String] = []
  let mut i = 0
  let mut depth = 0
  while i < n && words.length() < 3 {
    let c = chars[i]
    let next = if i + 1 < n { Some(chars[i + 1]) } else { None }
    if depth > 0 {
      if c == '-' && next == Some('}') {
        depth -= 1
        i += 2
      } else if c == '{' && next == Some('-') {
        depth += 1
        i += 2
      } else {
        i += 1
      }
    } else if c == '{' && next == Some('-') {
      depth = 1
      i += 2
    } else if c == '-' && next == Some('-') {
      while i < n && chars[i] != '\n' {
        i += 1
      }
    } else if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      i += 1
    } else {
      let word = StringBuilder()
      while i < n &&
            (
              (chars[i] >= 'a' && chars[i] <= 'z') ||
              (chars[i] >= 'A' && chars[i] <= 'Z') ||
              (chars[i] >= '0' && chars[i] <= '9') ||
              chars[i] == '_' ||
              chars[i] == '.'
            ) {
        word.write_char(chars[i])
        i += 1
      }
      if word.is_empty() {
        return None
      }
      words.push(word.to_string())
    }
  }
  match words {
    ["module", name, ..] => Some(name)
    ["port" | "effect", "module", name] => Some(name)
    _ => None
  }
}

///|
/// The one-module Elm project of the single editor: the header `A.B.C` gives package `A.B` and module `C`.
fn elm_shorthand(
  source : String,
) -> (@ids.SourcePackageName, ProjectFile, @ids.SourceModuleName) raise {
  let fix = "Name the module Package.Module, for example `module Workbench.Main exposing (..)`"
  guard elm_module_name(source) is Some(name) else {
    raise @wire.Invalid(
      "elm.missing_module_header",
      "The Elm source has no module header. " + fix,
    )
  }
  let segments = name.split(".").map(StringView::to_owned).collect()
  guard segments.length() >= 2 else {
    raise @wire.Invalid(
      "elm.module_needs_package",
      "The module " + name + " has no package. " + fix,
    )
  }
  let pkg_name = segments[:segments.length() - 1].to_owned().join(".")
  (
    package_name(pkg_name),
    {
      path: @ids.SourcePath::parse("src/" + segments.join("/") + ".elm"),
      content: source,
    },
    @ids.SourceModuleName::parse(segments[segments.length() - 1]),
  )
}

///|
fn project_request(
  request : Json,
  offers : Array[@engine.LanguageOffer],
) -> ProjectRequest raise {
  let project = @wire.optional(request, "project")
  let fields = project.unwrap_or(request)
  let language = @ids.LanguageId::parse(
    optional_text(fields, "languageId").unwrap_or("scheme"),
  )
  let offer = offers.filter(o => o.language == language)
  guard offer is [first, ..] else {
    raise @wire.Invalid(
      "workbench.unavailable_language",
      "This local input language is unavailable: " + language.to_string(),
    )
  }
  let provider = match optional_text(fields, "frontendProvider") {
    Some(text) => Some(@ids.ProviderId::parse(text))
    None => None
  }
  let profile = match optional_text(fields, "frontendProfile") {
    Some(text) => Some(@ids.ProfileId::parse(text))
    None => None
  }
  match project {
    Some(_) => {
      let files = @wire.array(@wire.field(fields, "files")).map(file => {
        (
          {
            path: @ids.SourcePath::parse(
              @wire.string(@wire.field(file, "path")),
            ),
            content: @wire.string(@wire.field(file, "content")),
          } : ProjectFile)
      })
      let exposed = match @wire.optional(fields, "exposedModules") {
        Some(Array(items)) =>
          items.map(item => @ids.SourceModuleName::parse(@wire.string(item)))
        _ => []
      }
      {
        name: package_name(@wire.string(@wire.field(fields, "name"))),
        language,
        provider,
        profile,
        files,
        exposed,
      }
    }
    None => {
      let source = @wire.string(@wire.field(request, "source"))
      if language.to_string() == "elm" {
        let (name, file, module_name) = elm_shorthand(source)
        {
          name,
          language,
          provider,
          profile,
          files: [file],
          exposed: [module_name],
        }
      } else {
        // The requested provider's offer gives the extension. A provider no offer has falls to the engine's
        // `frontend.unknown_provider` refusal.
        let chosen = match provider {
          Some(wanted) => offer.search_by(o => o.provider == wanted)
          None => None
        }
        let extension = offer[chosen.unwrap_or(0)].extensions
          .get(0)
          .map(e => e.to_string())
          .unwrap_or("")
        {
          name: package_name("user"),
          language,
          provider,
          profile,
          files: [
            {
              path: @ids.SourcePath::parse("src/main" + extension),
              content: source,
            },
          ],
          exposed: [],
        }
      }
    }
  }
}

///|
/// A TOML basic string for any text: `\`, `"` and every control character are escaped, so the text cannot end
/// the string or start a new key.
fn toml_string(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    match c {
      '\\' => out.write_string("\\\\")
      '"' => out.write_string("\\\"")
      _ =>
        if c.to_int() < 0x20 || c.to_int() == 0x7F {
          let hex = c.to_int().to_string(radix=16)
          out.write_string("\\u" + "0000"[:4 - hex.length()].to_owned() + hex)
        } else {
          out.write_char(c)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// The morphir.toml of a project without a manifest: its name, the `src` source directory, its exposed modules
/// (whole-project languages) and its language.
fn manifest(project : ProjectRequest) -> String {
  let text = StringBuilder()
  text.write_string(
    "[project]\nname = " +
    toml_string(project.name.to_string()) +
    "\nsource_directory = \"src\"\n",
  )
  if !project.exposed.is_empty() {
    text.write_string(
      "exposed_modules = [" +
      project.exposed.map(m => toml_string(m.to_string())).join(", ") +
      "]\n",
    )
  }
  text.write_string(
    "[frontend]\nlanguage = " + toml_string(project.language.to_string()) + "\n",
  )
  text.to_string()
}

///|
fn project_tree(project : ProjectRequest) -> @workspace.Tree {
  let files : Map[String, String] = Map([])
  for file in project.files {
    files[file.path.to_string()] = file.content
  }
  if !files.contains("morphir.json") && !files.contains("morphir.toml") {
    files["morphir.toml"] = manifest(project)
  }
  let directories = [""]
  for path, _ in files {
    let parts = path.split("/").map(StringView::to_owned).collect()
    for i in 1..<parts.length() {
      let directory = parts[:i].to_owned().join("/")
      if !directories.contains(directory) {
        directories.push(directory)
      }
    }
  }
  { files, directories, }
}

///|
/// The request overlay: the frontend selection and the pipeline for `backend`. Generators validate source only:
/// the worker never builds generated code.
fn overlay(
  project : ProjectRequest,
  backend : String,
) -> @config.Document raise {
  let text = StringBuilder()
  text.write_string(
    "[frontend]\nlanguage = " + toml_string(project.language.to_string()) + "\n",
  )
  if project.provider is Some(provider) {
    text.write_string("provider = " + toml_string(provider.to_string()) + "\n")
  }
  if project.profile is Some(profile) {
    text.write_string("profile = " + toml_string(profile.to_string()) + "\n")
  }
  text.write_string(
    "[pipeline]\nbackend = " +
    toml_string(backend) +
    "\nvalidation = \"source-only\"\ncheckpoint_format = \"ion-binary\"\n",
  )
  text.to_string() |> @config.parse()
}
