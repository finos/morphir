///|
fn candidate(
  owner : String,
  role : String,
  name : @ir.Name,
  module_name : @ir.Path,
  original : String?,
  source : @diagnostics.Span?,
  upper : Bool,
  requested~ : String? = None,
) -> NamingCandidate {
  let semantic = render_name(name, upper)
  let base = match original {
    Some(text) if usable_identifier(text, upper) => text
    _ => semantic
  }
  let reason = if keyword(base) {
    "keyword"
  } else if original is Some(text) && !usable_identifier(text, upper) {
    "invalid-source-hint"
  } else {
    "automatic"
  }
  let base = if keyword(base) { base + "_value" } else { base }
  let qualifier = module_name
    .to_names()
    .map(n => render_name(n, upper))
    .join("_")
  {
    owner,
    role,
    original,
    requested,
    source,
    candidate: base,
    qualified: qualifier + "_" + base,
    reason,
  }
}

///|
fn allocate_namespace(
  plan : TargetNames,
  candidates : Array[NamingCandidate],
  blocked : Map[String, Bool],
  reserve_global~ : Bool = true,
) -> Unit {
  let exact = candidates.filter(c => c.requested is Some(_))
  let blocked = blocked.copy()
  for c in exact {
    let name = c.requested.unwrap()
    blocked[name] = true
    plan.names[c.owner] = name
    if reserve_global {
      plan.reserved[name] = true
      plan.reserved_locations
      .get_or_init(name, fn() { [] })
      .push({
        owner: c.owner,
        original: c.original.unwrap_or(c.candidate),
        allocated: name,
        source: c.source,
      })
    }
    plan.allocations.push({
      owner: c.owner,
      role: c.role,
      original: c.original,
      requested: c.requested,
      candidate: c.candidate,
      allocated: name,
      reason: "explicit-request",
    })
  }
  let candidates = candidates.filter(c => c.requested is None)
  candidates.sort_by(fn(a, b) { a.owner.compare(b.owner) })
  let groups : Map[String, Array[NamingCandidate]] = Map([])
  let reserved = blocked.copy()
  for c in candidates {
    groups.get_or_init(c.candidate, fn() { [] }).push(c)
    reserved[c.candidate] = true
  }
  // Reserve qualified candidates too, so recovery cannot take a later owner's spelling.
  for c in candidates {
    if groups[c.candidate].length() > 1 || blocked.contains(c.candidate) {
      reserved[c.qualified] = true
    }
  }
  let used = blocked.copy()
  for c in candidates {
    let collision = groups[c.candidate].length() > 1 ||
      blocked.contains(c.candidate)
    let mut allocated = if collision { c.qualified } else { c.candidate }
    if used.contains(allocated) || (collision && groups.contains(allocated)) {
      let token = hex(c.owner)
      let mut bytes = if token.length() < 8 { token.length() / 2 } else { 4 }
      let mut counter = 0
      while true {
        let next = allocated +
          "_source_" +
          token[:bytes * 2].to_owned() +
          (if counter == 0 { "" } else { "_" + counter.to_string() })
        if !reserved.contains(next) && !used.contains(next) {
          allocated = next
          break
        }
        if bytes * 2 < token.length() {
          bytes += 1
        } else {
          counter += 1
        }
      }
    }
    used[allocated] = true
    if reserve_global {
      plan.reserved[allocated] = true
      plan.reserved_locations
      .get_or_init(allocated, fn() { [] })
      .push({
        owner: c.owner,
        original: c.original.unwrap_or(c.candidate),
        allocated,
        source: c.source,
      })
    }
    plan.names[c.owner] = allocated
    let reason = if collision { "namespace-collision" } else { c.reason }
    plan.allocations.push({
      owner: c.owner,
      role: c.role,
      original: c.original,
      requested: None,
      candidate: c.candidate,
      allocated,
      reason,
    })
  }
  let emitted : Map[String, Bool] = Map([])
  for c in candidates {
    let collision = groups[c.candidate].length() > 1 ||
      blocked.contains(c.candidate)
    let key = if collision { c.candidate } else { c.owner }
    if (collision || (c.reason != "automatic" && c.reason != "legacy")) &&
      !emitted.contains(key) {
      emitted[key] = true
      let related = if collision { groups[c.candidate] } else { [c] }
      let locations = related.map(r => @diagnostics.Location::{
        owner: r.owner,
        original: r.original.unwrap_or(r.candidate),
        allocated: plan.names[r.owner],
        source: r.source,
      })
      if blocked.contains(c.candidate) {
        locations.append(plan.reserved_locations.get(c.candidate).unwrap_or([]))
      }
      locations.sort_by(fn(a, b) { a.owner.compare(b.owner) })
      plan.warnings.push({
        code: "moonbit_backend.name_" +
        (if collision { "collision" } else { "recovery" }),
        stage: "backend",
        message: "Allocated a portable MoonBit " +
        c.role +
        " name" +
        (if collision {
          " after a namespace collision"
        } else {
          " after " + c.reason
        }),
        locations,
        fix: "Rename " +
        c.owner +
        " to a distinct non-keyword spelling such as '" +
        plan.names[c.owner] +
        "'. Consult symbols.10n for the final allocation.",
      })
    }
  }
}

///|
fn allocate_fields(
  plan : TargetNames,
  shape : String,
  names : Array[@ir.Name],
) -> Unit {
  if plan.fields.contains(shape) {
    return
  }
  let mapped = Map([])
  let candidates = []
  for name in names {
    let id = "shape:" + shape + "/field/" + name.to_canonical()
    if plan.style == LegacyHex {
      mapped[name] = "f_" + hex(name.to_canonical())
    } else {
      let rendered = render_name(name, false)
      candidates.push({
        owner: id,
        role: "field",
        original: None,
        requested: None,
        candidate: if keyword(rendered) {
          rendered + "_value"
        } else {
          rendered
        },
        qualified: rendered + "_field",
        source: None,
        reason: if keyword(rendered) {
          "keyword"
        } else {
          "automatic"
        },
      })
    }
  }
  allocate_namespace(plan, candidates, Map([]), reserve_global=false)
  if plan.style == Readable {
    for name in names {
      mapped[name] = plan.names["shape:" +
        shape +
        "/field/" +
        name.to_canonical()]
    }
  }
  plan.fields[shape] = mapped
}
