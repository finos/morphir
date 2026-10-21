///|
fn quote(text : String) -> String {
  Json::string(text).stringify()
}

///|
/// Legacy projects always used src/. Write their settings once, then discover and compile the real files.
fn legacy_config(project : @project.Project) -> String {
  let text = StringBuilder()
  text.write_string(
    "[project]\nname = " +
    quote(project.name.to_string()) +
    "\nsource_directory = \"src\"\n",
  )
  if !project.exposed.is_empty() {
    text.write_string(
      "exposed_modules = [" +
      project.exposed.map(m => quote(m.to_string())).join(", ") +
      "]\n",
    )
  }
  text.write_string(
    "\n[frontend]\nlanguage = " + quote(project.language.to_string()) + "\n",
  )
  if project.provider is Some(provider) {
    text.write_string("provider = " + quote(provider.to_string()) + "\n")
  }
  if project.profile is Some(profile) {
    text.write_string("profile = " + quote(profile.to_string()) + "\n")
  }
  let backend = match project.target {
    Some(target) if target.id() != "" => target.id()
    _ => "checkpoint"
  }
  text.write_string(
    "\n[pipeline]\nbackend = " +
    quote(backend) +
    "\ncheckpoint_format = \"ion-binary\"\n",
  )
  text.to_string()
}

///|
/// Most recently used language becomes the root project. Other folders use project names;
/// language is appended only to disambiguate a collision. Drafts become ordinary files.
pub fn migrate(
  projects : Array[@project.Project],
  recent_language : String,
  intent~ : String? = None,
  concept~ : String? = None,
  worksheet~ : String? = None,
) -> Files raise {
  let files : Map[String, String] = Map([])
  let ordered = projects.copy()
  ordered.sort_by(fn(a, b) {
    let a_recent = a.language.to_string() == recent_language
    let b_recent = b.language.to_string() == recent_language
    if a_recent != b_recent {
      if a_recent {
        -1
      } else {
        1
      }
    } else {
      a.language.to_string().compare(b.language.to_string())
    }
  })
  let members : Array[String] = []
  let used : Map[String, Bool] = Map([])
  let mut opened = None
  for i, project in ordered {
    let name = project.name
      .to_string()
      .replace_all(old=".", new="-")
      .replace_all(old="/", new="-")
    let collision = projects.filter(p => p.name == project.name).length() > 1
    let base = "packages/" +
      name +
      (if collision { "-" + project.language.to_string() } else { "" })
    let mut path = if i == 0 { "" } else { base }
    let mut number = 2
    while used.contains(path) {
      path = base + "-" + number.to_string()
      number += 1
    }
    used[path] = true
    if path != "" {
      members.push(path)
    }
    files[@discovery.join(path, "morphir.toml")] = legacy_config(project)
    for file in project.files {
      files[@discovery.join(path, file.path.to_string())] = file.content
    }
    if i == 0 {
      opened = Some(project.active.to_string())
    }
  }
  let root = "[workspace]\nmembers = [" +
    members.map(quote).join(", ") +
    "]\n\n" +
    files.get("morphir.toml").unwrap_or("")
  files["morphir.toml"] = root
  if intent is Some(text) {
    files["intent.md"] = text
  }
  if concept is Some(text) {
    files["src/model.mfs"] = text
  }
  if worksheet is Some(text) {
    files["worksheet.scm"] = text
  }
  Files::new(files, open_file=opened)
}
