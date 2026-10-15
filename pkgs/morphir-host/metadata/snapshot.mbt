///|
priv struct ContextFile {
  path : String
  bytes : Bytes
  digest : String
}

///|
priv struct RetainedLibrary {
  manifest : Bytes
  native : Bytes
  native_path : String
  revision : String
  contexts : Array[ContextFile]
}

///|
/// A shape-checked wire response, NOT an authenticated capability. Only a host
/// that freshly completed its qualified service may install its views. All
/// original graph buffers remain retained; returned core/metadata are reparsed
/// so caller mutation cannot change this response's accepted inventory.
pub struct Snapshot {
  priv libraries : Array[RetainedLibrary]
  priv root : Int
  priv core : String
  priv metadata : String?
}

///|
fn inventory_path(path : String) -> String raise {
  if path == "" ||
    path.has_prefix("/") ||
    path.contains("\\") ||
    path.contains(":") ||
    path.split("/").any(p => p == "" || p == "." || p == "..") {
    invalid("Noncanonical inventory path")
  }
  path
}

///|
fn checked_bytes(value : @ion.IonValue, digest : String) -> Bytes raise {
  let bytes = blob(value)
  if @identity.sha256(bytes) != digest {
    invalid("Retained byte digest mismatch")
  }
  bytes
}

///|
/// Validate one correlated response and retain its complete graph. This checks
/// transport identities only; it does not independently verify signatures.
pub fn Snapshot::decode(bytes : Bytes, expected : Expected) -> Snapshot raise {
  let values = frame(bytes, "morphir_provider_snapshot_response_v1", [
    "invocation", "projectScope", "service", "profile", "profileVersion", "release",
    "policySha256", "lockSha256", "codec", "core", "metadata", "libraries",
  ])
  correlate(values, expected.invocation, expected.project_scope)
  if text(required(values, "release")) != expected.release ||
    raw_digest(text(required(values, "policySha256"))) != expected.policy_sha256 ||
    raw_digest(text(required(values, "lockSha256"))) != expected.lock_sha256 {
    invalid("Release, policy or lock identity mismatch")
  }
  let libraries : Array[RetainedLibrary] = []
  let releases : Map[String, Bool] = Map([])
  let mut root = -1
  let mut total_contexts = 0
  for value in list(required(values, "libraries"), 128) {
    let library = fields(value, [
      "release", "manifest", "nativePath", "revision", "native", "contexts",
    ])
    let release = text(required(library, "release"))
    if releases.contains(release) {
      invalid("Duplicate Library release")
    }
    releases[release] = true
    let revision = raw_digest(text(required(library, "revision")))
    let native = checked_bytes(required(library, "native"), revision)
    let native_path = inventory_path(text(required(library, "nativePath")))
    let manifest = blob(required(library, "manifest"))
    let contexts = []
    let paths = Map::from_array([(native_path, true)])
    for value in list(required(library, "contexts"), 256) {
      let context = fields(value, ["path", "sha256", "bytes"])
      let path = inventory_path(text(required(context, "path")))
      if paths.contains(path) {
        invalid("Duplicate inventory path")
      }
      paths[path] = true
      let digest = raw_digest(text(required(context, "sha256")))
      contexts.push({
        path,
        digest,
        bytes: checked_bytes(required(context, "bytes"), digest),
      })
      total_contexts += 1
      if total_contexts > 1024 {
        invalid("Context inventory limit")
      }
    }
    if release == expected.release {
      root = libraries.length()
    }
    libraries.push({ manifest, native, native_path, revision, contexts, })
  }
  if root < 0 {
    invalid("Missing requested root Library")
  }
  let native = members(
    @ion_json.read_json(@utf8.decode(libraries[root].native[:])[:]),
  )
  if text(required(native, "formatVersion")) != "4.1.0" {
    invalid("Wrong native root format")
  }
  let distribution = members(required(native, "distribution"))
  let library = members(required(distribution, "Library"))
  if text(required(library, "packageName")) != "morphir/naming" {
    invalid("Wrong native IR package")
  }
  let core = @utf8.decode(blob(required(values, "core"))[:])
  guard @ir_json.read(core).distribution
    is @ir.Distribution::Library(name, _, _) &&
    name.to_canonical() == "morphir/naming" else {
    invalid("Wrong core Library identity")
  }
  let raw_metadata = required(values, "metadata")
  let metadata = if raw_metadata.kind() is @ion.Null(@ion.Blob) &&
    !raw_metadata.has_annotations() {
    if native.contains("$meta") {
      invalid("Missing authored metadata")
    }
    None
  } else {
    let body = @utf8.decode(blob(raw_metadata)[:])
    guard native.get("$meta") is Some(authored) &&
      authored.equals(@ion_json.read_json(body[:])) else {
      invalid("Native metadata view differs from original payload")
    }
    Some(body)
  }
  { libraries, root, core, metadata, }
}

///|
/// Return a fresh semantic view after the host has granted this response.
pub fn Snapshot::restored(
  self : Snapshot,
) -> @linked_metadata.RestoredLibrary raise {
  let revision = self.libraries[self.root].revision
  {
    core: @ir_json.read(self.core),
    format: "4.1.0",
    revision,
    document: "morphir://ir/pkg/morphir/naming?format=4.1.0&rev=sha256:" +
    revision +
    "#/distribution",
    document_metadata: match self.metadata {
      Some(body) => @ion_json.read_json(body[:])
      None => @ion.IonValue::from_fields([])
    },
  }
}

///|
/// Resolve only retained inventory bytes. A document URI is not a filesystem
/// grant. Relative imports remain within their selected Library's inventory.
pub fn Snapshot::context(
  self : Snapshot,
  resource : String,
  base : String,
) -> @linked_metadata.ContextDocument raise {
  if resource.has_prefix("morphir://context/sha256/") {
    let digest = resource["morphir://context/sha256/".length():].to_owned()
    for library in self.libraries {
      for context in library.contexts {
        if context.digest == digest {
          return {
            url: "morphir-provider-context://" +
            @identity.sha256(library.manifest) +
            "/" +
            context.path,
            bytes: Bytes::from_array(context.bytes.to_array()),
            sha256: context.digest,
          }
        }
      }
    }
    invalid("Context digest is absent from retained inventory")
  }
  let root = self.libraries[self.root]
  let document = "morphir://ir/pkg/morphir/naming?format=4.1.0&rev=sha256:" +
    root.revision +
    "#/distribution"
  let mut selected = self.root
  let mut current = root.native_path
  if base != document {
    let mut found = false
    for index, library in self.libraries {
      let prefix = "morphir-provider-context://" +
        @identity.sha256(library.manifest) +
        "/"
      if base.has_prefix(prefix) {
        selected = index
        current = base[prefix.length():].to_owned()
        found = library.contexts.any(c => c.path == current)
        break
      }
    }
    if !found {
      invalid("Unknown context base")
    }
  }
  if resource.has_prefix("/") ||
    resource.contains(":") ||
    resource.contains("\\") {
    invalid("Context reference is not a relative inventory path")
  }
  let parts = current.split("/").map(p => p.to_owned()).collect()
  ignore(parts.pop())
  for part in resource.split("/") {
    if part == "." {
      continue
    }
    if part == ".." {
      if parts.pop() is None {
        invalid("Context path escapes retained inventory")
      }
    } else if part == "" {
      invalid("Empty context path component")
    } else {
      parts.push(part.to_owned())
    }
  }
  let path = parts.join("/")
  let library = self.libraries[selected]
  guard library.contexts.iter().find_first(c => c.path == path) is Some(context) else {
    invalid("Context path is absent from retained inventory")
  }
  {
    url: "morphir-provider-context://" +
    @identity.sha256(library.manifest) +
    "/" +
    path,
    bytes: Bytes::from_array(context.bytes.to_array()),
    sha256: context.digest,
  }
}
