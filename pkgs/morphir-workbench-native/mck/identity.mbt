///|
priv struct Aliases {
  forward : Map[String, String]
  reverse : Map[String, Json]
  next : Map[String, Int32]
}

///|
fn Aliases::new() -> Aliases {
  { forward: Map([]), reverse: Map([]), next: Map([]), }
}

///|
fn Aliases::name(
  self : Aliases,
  domain : String,
  scope : String,
  raw : String,
  reference~ : Json? = None,
) -> String {
  let key = canonical(([domain, scope, raw] : Json))
  if self.forward.get(key) is Some(name) {
    return name
  }
  let next = self.next.get(domain).unwrap_or(0) + 1
  self.next[domain] = next
  let name = domain + "-" + next.to_string()
  self.forward[key] = name
  self.reverse[name] = reference.unwrap_or(Json::string(raw))
  name
}

///|
fn Aliases::session(self : Aliases, raw : String) -> String {
  self.name("session", "", raw)
}

///|
fn Aliases::offer(self : Aliases, value : Json) -> Json {
  let fields = closed(value, [
    "profile", "contractVersion", "hostId", "sessionId", "providerId", "operations",
  ]).copy()
  let session = text(fields["sessionId"])
  fields["hostId"] = Json::string(
    self.name("host", session, text(fields["hostId"])),
  )
  fields["sessionId"] = Json::string(self.session(session))
  Json::object(fields)
}

///|
fn Aliases::identity(self : Aliases, value : Json) -> Json {
  let fields = closed(value, [
    "hostId", "sessionId", "providerId", "executionId", "snapshotId",
  ]).copy()
  let host = text(fields["hostId"])
  let session = text(fields["sessionId"])
  let scope = canonical(([host, session, text(fields["providerId"])] : Json))
  // Allocation order is semantic and independent of JSON object iteration.
  fields["hostId"] = Json::string(self.name("host", session, host))
  fields["sessionId"] = Json::string(self.session(session))
  fields["executionId"] = Json::string(
    self.name(
      "execution",
      scope,
      text(fields["executionId"]),
      reference=Some(value),
    ),
  )
  fields["snapshotId"] = Json::string(
    self.name("snapshot", scope, text(fields["snapshotId"])),
  )
  Json::object(fields)
}

///|
fn Aliases::execution_value(self : Aliases, value : Json) -> Json {
  guard value is Object(fields) else { return value }
  let fields = fields.copy()
  if fields.get("identity") is Some(identity) {
    fields["identity"] = self.identity(identity)
  }
  if fields.get("receipt") is Some(receipt) {
    fields["receipt"] = self.execution_value(receipt)
  }
  Json::object(fields)
}

///|
fn Runtime::workspace_value(
  self : Runtime,
  session : String,
  value : Json,
) -> Json {
  guard value is Object(fields) else { return value }
  let fields = fields.copy()
  if fields.get("grantId") is Some(String(grant)) {
    let lifetime = self.workspace_scopes
      .get(session)
      .unwrap_or("uncreated:" + session)
    let scope = canonical(([lifetime, grant] : Json))
    fields["grantId"] = Json::string(
      self.aliases.name("grant", lifetime, grant),
    )
    if fields.get("projectId") is Some(String(project)) {
      fields["projectId"] = Json::string(
        self.aliases.name("project", scope, project),
      )
    }
    if fields.get("projects") is Some(Array(projects)) {
      fields["projects"] = Json::array(
        projects.map(project => {
          guard project is Object(project) else {
            abort("native owner MCK: invalid project reply")
          }
          let project = project.copy()
          project["id"] = Json::string(
            self.aliases.name("project", scope, text(project["id"])),
          )
          Json::object(project)
        }),
      )
    }
  }
  Json::object(fields)
}

///|
fn Runtime::normalize(
  self : Runtime,
  operation : String,
  session : String,
  value : Json,
) -> Json {
  if operation == "session.open" || operation == "session.check" {
    guard value is Object(fields) else {
      abort("native owner MCK: invalid descriptor")
    }
    let fields = fields.copy()
    fields["sessionId"] = Json::string(
      self.aliases.session(text(fields["sessionId"])),
    )
    if fields.get("offer") is Some(offer) {
      fields["offer"] = self.aliases.offer(offer)
    }
    Json::object(fields)
  } else if operation.has_prefix("execution.") {
    self.aliases.execution_value(value)
  } else if operation.has_prefix("workspace.") {
    self.workspace_value(session, value)
  } else {
    value
  }
}
