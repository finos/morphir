///|
fn unique(seen : Map[String, Bool], value : Json) -> String {
  let name = text(value, token=true)
  guard !seen.contains(name) else {
    abort("native owner MCK: repeated fixture id")
  }
  seen[name] = true
  name
}

///|
fn checkpoint(value : Json, replace~ : Bool = false) -> (String, Bytes) raise {
  ignore(
    closed(
      value,
      if replace {
        ["op", "root", "name", "encoding", "source"]
      } else {
        ["name", "encoding", "source"]
      },
    ),
  )
  let name = text(field(value, "name"))
  guard [
    "morphir-ir.json", "morphir-ir.ion", "morphir-ir.10n", "morphir-ir.ionb",
  ].contains(name) else {
    abort("native owner MCK: invalid checkpoint name")
  }
  let source = text(field(value, "source"), maximum=393216)
  let bytes = match field(value, "encoding") {
    String("utf8") => @utf8.encode(source)
    String("base64") => {
      let bytes = @base64.decode(source[:])
      guard @base64.encode(bytes) == source else {
        abort("native owner MCK: noncanonical base64")
      }
      bytes
    }
    _ => abort("native owner MCK: invalid fixture encoding")
  }
  guard bytes.length() <= 262144 else {
    abort("native owner MCK: checkpoint exceeds limit")
  }
  (name, bytes)
}

///|
fn admit_context(value : Json, action~ : Bool = false) -> Unit {
  ignore(
    closed(
      value,
      if action {
        ["op", "window", "origin", "page"]
      } else {
        ["window", "origin", "page"]
      },
    ),
  )
  ignore(text(field(value, "window")))
  ignore(text(field(value, "origin")))
  ignore(optional_text(field(value, "page"), maximum=256))
}

///|
fn admit_input(value : Json) -> Unit raise {
  ignore(
    closed(value, [
      "context", "services", "evaluation", "roots", "pickers", "cleanups", "actions",
    ]),
  )
  guard @utf8.encode(value.stringify()).length() <= 491520 else {
    abort("native owner MCK: compact input exceeds limit")
  }
  admit_context(field(value, "context"))
  let services = closed(field(value, "services"), ["jobs", "workspace"])
  guard ["enabled", "disabled", "unavailable"].contains(text(services["jobs"])) else {
    abort("native owner MCK: invalid jobs availability")
  }
  ignore(boolean(services["workspace"]))
  let evaluation = closed(field(value, "evaluation"), [
    "model", "entry", "inputs",
  ])
  guard !text(evaluation["model"], maximum=262144).is_empty() &&
    !text(evaluation["entry"], maximum=512).is_empty() else {
    abort("native owner MCK: empty evaluation model or entry")
  }
  let inputs = closed(evaluation["inputs"], ["format", "source"])
  let source = text(inputs["source"], maximum=16384)
  match inputs["format"] {
    String("json") => {
      guard @wire.parse(source) is Array(_) else {
        abort("native owner MCK: JSON arguments must be an array")
      }
    }
    String("ion-text") => ()
    _ => abort("native owner MCK: invalid argument format")
  }
  let roots : Map[String, Map[String, Bool]] = Map([])
  for root in array(field(value, "roots"), 8) {
    let fields = closed(root, ["id", "manifest", "files"])
    let id = text(fields["id"], token=true)
    guard !roots.contains(id) else { abort("native owner MCK: repeated root") }
    ignore(text(fields["manifest"], maximum=16384))
    let names : Map[String, Bool] = Map([])
    for file in array(fields["files"], 4) {
      let (name, _) = checkpoint(file)
      guard !names.contains(name) else {
        abort("native owner MCK: repeated checkpoint")
      }
      names[name] = true
    }
    roots[id] = names
  }
  let boundaries : Map[String, Bool] = Map([])
  let held : Map[String, Bool] = Map([])
  let pickers = array(field(value, "pickers"), 128)
  let cleanups = array(field(value, "cleanups"), 128)
  guard pickers.length() + cleanups.length() <= 128 else {
    abort("native owner MCK: too many boundaries")
  }
  for picker in pickers {
    let fields = closed(picker, ["id", "held", "root", "fail"])
    let id = unique(boundaries, fields["id"])
    if boolean(fields["held"]) {
      held[id] = true
    }
    ignore(boolean(fields["fail"]))
    if optional_text(fields["root"]) is Some(root) {
      guard roots.contains(root) else {
        abort("native owner MCK: undeclared root")
      }
    }
  }
  let sessions : Map[String, Bool] = Map([])
  for cleanup in cleanups {
    let fields = closed(cleanup, ["id", "session", "held", "success"])
    let id = unique(boundaries, fields["id"])
    ignore(unique(sessions, fields["session"]))
    if boolean(fields["held"]) {
      held[id] = true
    }
    ignore(boolean(fields["success"]))
  }
  let attempts : Map[String, Bool] = Map([])
  let delivered : Map[String, Bool] = Map([])
  for action in array(field(value, "actions"), 32) {
    let op = text(field(action, "op"))
    if op == "call" {
      let operation = text(field(action, "operation"))
      let extra = match operation {
        "session.open" => []
        "session.check"
        | "session.close"
        | "job.submit"
        | "workspace.choose"
        | "workspace.cancel-picker" => ["session"]
        "job.query" | "job.cancel" | "job.release" => ["session", "job"]
        "workspace.revoke" => ["session", "grant"]
        "workspace.open" => ["session", "grant", "project", "sequence"]
        "workspace.read" => ["session", "grant", "sequence", "offset"]
        "workspace.release" => ["session", "grant", "sequence"]
        _ => abort("native owner MCK: invalid native operation")
      }
      let fields = closed(action, ["op", "id", "operation"] + extra)
      ignore(unique(attempts, fields["id"]))
      for key in extra {
        if key == "sequence" {
          ignore(integer(fields[key], 1, 2147483647))
        } else if key == "offset" {
          ignore(integer(fields[key], 0, 16777216))
        } else {
          ignore(text(fields[key], token=true))
        }
      }
    } else if op == "context" {
      admit_context(action, action=true)
    } else if op == "revoke" || op == "close" {
      ignore(closed(action, ["op"]))
    } else if op == "shutdown" {
      ignore(closed(action, ["op", "id"]))
      ignore(unique(attempts, field(action, "id")))
    } else if op == "deliver" {
      ignore(closed(action, ["op", "id"]))
      let id = unique(delivered, field(action, "id"))
      guard held.contains(id) else {
        abort("native owner MCK: undeclared held delivery")
      }
    } else if op == "complete" {
      ignore(closed(action, ["op", "job", "outcomes"]))
      ignore(text(field(action, "job"), token=true))
      guard field(action, "outcomes") is Object(_) else {
        abort("native owner MCK: complete outcomes must be an object")
      }
      // Outcomes are production Host input, not interpreted by fixture controls.
    } else if op == "replace" {
      let (name, _) = checkpoint(action, replace=true)
      let root = text(field(action, "root"), token=true)
      guard roots.get(root) is Some(files) && files.contains(name) else {
        abort("native owner MCK: replace requires existing checkpoint")
      }
    } else {
      abort("native owner MCK: invalid action")
    }
  }
}
