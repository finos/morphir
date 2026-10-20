///|
pub(all) struct Props {
  data : Json
  selected : String
  query : String
  collapsed_modules : Array[String]
  raw : Bool
  original_yaml : String?
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
fn items(value : Json) -> Array[Json] {
  match value {
    Array(values) => values
    _ => []
  }
}

///|
fn pretty(value : String) -> String {
  @json.parse(value).stringify(indent=2) catch {
    _ => value
  }
}

///|
fn matches(node : Json, query : String) -> Bool {
  query == "" ||
  (text(node, "id") + " " + text(node, "label"))
  .to_lower()
  .contains(query.to_lower())
}

///|
fn count(nodes : Array[Json], kind : String) -> Int32 {
  nodes.filter(node => text(node, "kind") == kind).length()
}

///|
fn selected_node(props : Props) -> Json? {
  items(field(props.data, "nodes"))
  .iter()
  .find_first(node => text(node, "key") == props.selected)
}

///|
fn declaration_button(
  node : Json,
  selected : String,
  emit : @cmd.Emit[String],
) -> @html.Html {
  @html.button(
    class=if selected == text(node, "key") {
      "tree-item selected"
    } else {
      "tree-item"
    },
    attrs=@html.Attrs::build()
      .aria_pressed((selected == text(node, "key")).to_string())
      .data_set("tree-row", "declaration")
      .data_set("level", "1"),
    title=text(node, "id"),
    on_click=emit(text(node, "key")),
    [
      @html.span(
        class="node-kind",
        if text(node, "kind") == "type" {
          "T"
        } else {
          "ƒ"
        },
      ),
      @html.span(text(node, "label")),
    ],
  )
}

///|
pub fn navigation(
  props : Props,
  on_select : @cmd.Emit[String],
  on_toggle : @cmd.Emit[String],
) -> @html.Html {
  let nodes = items(field(props.data, "nodes"))
  let by_module : Map[String, Array[Json]] = Map([])
  for node in nodes {
    if text(node, "kind") != "module" {
      let id = text(node, "module")
      match by_module.get(id) {
        Some(entries) => entries.push(node)
        None => by_module[id] = [node]
      }
    }
  }
  let groups : Array[@html.Html] = []
  let mut match_count = 0
  for module_node in nodes.filter(node => text(node, "kind") == "module") {
    let id = text(module_node, "id")
    let members = by_module.get(id).unwrap_or([])
    let module_match = matches(module_node, props.query)
    let visible = members.filter(node => {
      module_match || matches(node, props.query)
    })
    if !module_match && visible.is_empty() {
      continue
    }
    match_count += visible.length()
    let expanded = props.query != "" || !props.collapsed_modules.contains(id)
    let children : Array[@html.Html] = []
    for kind in ["type", "value"] {
      let declarations = visible.filter(node => text(node, "kind") == kind)
      if declarations.is_empty() {
        continue
      }
      children.push(
        @html.p(
          class="tree-group-label",
          if kind == "type" {
            "Types"
          } else {
            "Values"
          },
        ),
      )
      for node in declarations {
        children.push(declaration_button(node, props.selected, on_select))
      }
    }
    groups.push(
      @html.div(class="module-group", [
        @html.div(class="module-heading", [
          @html.button(
            class="module-toggle",
            title=if expanded {
              "Collapse " + text(module_node, "label")
            } else {
              "Expand " + text(module_node, "label")
            },
            disabled=props.query != "",
            attrs=@html.Attrs::build()
              .aria_label(
                if expanded {
                  "Collapse " + text(module_node, "label")
                } else {
                  "Expand " + text(module_node, "label")
                },
              )
              .aria_expanded(expanded.to_string())
              .data_set("tree-row", "module")
              .data_set("level", "0"),
            on_click=on_toggle(id),
            if expanded {
              "▾"
            } else {
              "▸"
            },
          ),
          @html.button(
            class=if text(module_node, "key") == props.selected {
              "tree-module selected"
            } else {
              "tree-module"
            },
            on_click=on_select(text(module_node, "key")),
            title=id,
            text(module_node, "label"),
          ),
          @html.span(class="muted small", visible.length().to_string()),
        ]),
        @html.div(hidden=!expanded, children),
      ]),
    )
  }
  if nodes.is_empty() {
    groups.push(
      @html.p(
        class="muted",
        "Compile a snippet or import Morphir JSON to explore its declarations.",
      ),
    )
  } else if groups.is_empty() {
    groups.push(
      @html.p(class="muted small", "No declarations match this search."),
    )
  } else if props.query != "" {
    groups.push(
      @html.p(
        class="muted small",
        match_count.to_string() + " matching declarations",
      ),
    )
  }
  @html.div(
    class="model-tree",
    attrs=@html.Attrs::build()
      .data_set("tree", "models")
      .on_keydown(@shell.on_tree_key),
    groups,
  )
}

///|
fn member_cards(
  nodes : Array[Json],
  on_select : @cmd.Emit[String],
) -> @html.Html {
  @html.div(
    class="declaration-grid",
    nodes.map(node => {
      @html.button(
        class="declaration-card",
        on_click=on_select(text(node, "key")),
        [
          @html.div(class="declaration-card-title", [
            @html.strong(text(node, "label")),
            @html.span(class="kind-badge", text(node, "kind")),
          ]),
          @html.p(
            class="small muted",
            if text(node, "signature") == "" {
              text(node, "id")
            } else {
              text(node, "signature")
            },
          ),
        ],
      )
    }),
  )
}

///|
fn table(title : String, rows : Array[Json]) -> @html.Html {
  @html.section(class="declaration-section", [
    @html.h3(title),
    @html.div(class="inspector-table", [
      @html.table([
        @html.thead([@html.tr([@html.th("Name"), @html.th("Type")])]),
        @html.tbody(
          rows.map(row => {
            @html.tr([
              @html.td(text(row, "name")),
              @html.td([@html.code(text(row, "type"))]),
            ])
          }),
        ),
      ]),
    ]),
  ])
}

///|
fn reference_index(nodes : Array[Json]) -> Map[String, Json] {
  let index : Map[String, Json] = Map([])
  for node in nodes {
    index[text(node, "key")] = node
    for variant in items(field(node, "constructors")) {
      index["constructor|" + text(variant, "id")] = node
    }
  }
  index
}

///|
fn reference_target(reference : Json, index : Map[String, Json]) -> Json? {
  index.get(text(reference, "key"))
}

///|
fn links(
  title : String,
  references : Array[Json],
  index : Map[String, Json],
  on_select : @cmd.Emit[String],
) -> @html.Html {
  @html.section(class="declaration-section", [
    @html.h3(title),
    @html.div(
      class="reference-list",
      references.map(reference => {
        match reference_target(reference, index) {
          Some(target) =>
            @html.button(
              class="reference-link",
              title=text(reference, "id"),
              on_click=on_select(text(target, "key")),
              text(reference, "label"),
            )
          None =>
            @html.span(
              class="reference-external",
              title=text(reference, "id") +
                " · not present among this model's declarations",
              [@html.span(text(reference, "label")), @html.small("external")],
            )
        }
      }),
    ),
  ])
}

///|
fn overview(
  data : Json,
  nodes : Array[Json],
  on_select : @cmd.Emit[String],
) -> @html.Html {
  @html.div(class="inspector-content", [
    @html.h2(text(data, "package")),
    @html.p(
      class="canonical-id",
      text(data, "distributionKind") +
      " · Current IR " +
      text(data, "formatVersion"),
    ),
    @html.div(class="model-metrics", [
      @html.div([
        @html.strong(count(nodes, "module").to_string()),
        @html.span("Modules"),
      ]),
      @html.div([
        @html.strong(count(nodes, "type").to_string()),
        @html.span("Types"),
      ]),
      @html.div([
        @html.strong(count(nodes, "value").to_string()),
        @html.span("Values"),
      ]),
    ]),
    @html.h3("Browse modules"),
    member_cards(
      nodes.filter(node => text(node, "kind") == "module"),
      on_select,
    ),
  ])
}

///|
pub fn details(
  props : Props,
  on_select : @cmd.Emit[String],
  on_raw : @cmd.Emit[Bool],
  evaluation : @html.Html,
) -> @html.Html {
  let nodes = items(field(props.data, "nodes"))
  let selected = selected_node(props)
  let index = reference_index(nodes)
  let contents : Array[@html.Html] = []
  if props.raw {
    let raw = match selected {
      Some(node) =>
        if text(node, "bodySource") != "" {
          text(node, "bodySource")
        } else {
          field(node, "body").stringify()
        }
      None =>
        if text(props.data, "irSource") != "" {
          text(props.data, "irSource")
        } else {
          field(props.data, "ir").stringify()
        }
    }
    contents.push(
      @editor.view({
        id: "model-detail",
        document_key: "model-detail",
        language: "json",
        label: "Model IR",
        read_only: true,
        marks: "",
        reveal: "",
        value: pretty(raw),
      }),
    )
  } else if selected is Some(node) {
    let detail : Array[@html.Html] = [
      @html.div(class="declaration-title", [
        @html.h2(text(node, "label")),
        @html.span(
          class="kind-badge",
          text(node, "access") +
          " · " +
          (if text(node, "flavor") == "" {
            "Module"
          } else {
            text(node, "flavor")
          }),
        ),
      ]),
    ]
    if text(node, "signature") != "" {
      detail.push(@html.pre(class="type-signature", text(node, "signature")))
    }
    if text(node, "doc") != "" {
      detail.push(@html.p(class="declaration-doc", text(node, "doc")))
    }
    if text(node, "kind") == "module" {
      let members = nodes.filter(entry => {
        text(entry, "kind") != "module" &&
        text(entry, "module") == text(node, "id")
      })
      if members.is_empty() {
        detail.push(
          @html.p(
            class="muted",
            "This module contains no type or value declarations.",
          ),
        )
      }
      detail.push(member_cards(members, on_select))
    }
    let fields = items(field(node, "fields"))
    if !fields.is_empty() {
      detail.push(table("Record fields", fields))
    }
    let constructors = items(field(node, "constructors"))
    if !constructors.is_empty() {
      detail.push(
        @html.section(class="declaration-section", [
          @html.h3("Constructors"),
          @html.div(
            class="constructor-list",
            constructors.map(variant => {
              @html.div([
                @html.strong(text(variant, "name")),
                @html.code(
                  items(field(variant, "arguments"))
                  .map(arg => text(arg, "name") + " : " + text(arg, "type"))
                  .join(" · "),
                ),
              ])
            }),
          ),
        ]),
      )
    }
    if text(node, "kind") == "value" {
      let inputs = items(field(node, "inputs"))
      if !inputs.is_empty() {
        detail.push(table("Parameters", inputs))
      } else {
        detail.push(
          @html.p(class="small muted", "This value takes no parameters."),
        )
      }
      detail.push(
        @html.section(class="declaration-section", [
          @html.h3("Returns"),
          @html.code(text(node, "output")),
        ]),
      )
    }
    if text(node, "kind") == "value" {
      detail.push(evaluation)
    }
    let refs = items(field(node, "references"))
    if !refs.is_empty() {
      detail.push(links("References", refs, index, on_select))
    }
    let used_by = nodes.filter(candidate => {
      text(candidate, "key") != text(node, "key") &&
      items(field(candidate, "references")).any(reference => {
        match reference_target(reference, index) {
          Some(target) => text(target, "key") == text(node, "key")
          None => false
        }
      })
    })
    if !used_by.is_empty() {
      detail.push(
        @html.section(class="declaration-section", [
          @html.h3("Used by"),
          member_cards(used_by, on_select),
        ]),
      )
    }
    contents.push(@html.div(class="inspector-content", detail))
  } else if nodes.is_empty() {
    contents.push(
      @html.div(class="inspector-empty", [
        @html.h2("Open a Morphir model"),
        @html.p(
          class="muted",
          "Import Morphir IR as JSON, YAML or Ion, or compile a snippet in Try Morphir. Its modules, types and values will appear here.",
        ),
      ]),
    )
  } else {
    contents.push(overview(props.data, nodes, on_select))
  }
  if props.original_yaml is Some(original) {
    contents.push(
      @html.details([
        @html.summary("Original YAML"),
        @editor.view({
          id: "model-original",
          document_key: "model-original",
          language: "yaml",
          label: "Original YAML",
          read_only: true,
          marks: "",
          reveal: "",
          value: original,
        }),
      ]),
    )
  }

  @html.section(class="panel model-detail", [
    @html.div(class="panel-heading", [
      match selected {
        Some(node) =>
          @html.code(
            class="panel-context",
            title=text(node, "id"),
            text(node, "id"),
          )
        None => @html.span(class="panel-context", "Model overview")
      },
      @html.div(class="tabs", [
        @html.button(
          class=if props.raw { "tab" } else { "tab selected" },
          attrs=@html.Attrs::build().aria_pressed((!props.raw).to_string()),
          on_click=on_raw(false),
          "Details",
        ),
        @html.button(
          class=if props.raw { "tab selected" } else { "tab" },
          disabled=nodes.is_empty(),
          attrs=@html.Attrs::build().aria_pressed(props.raw.to_string()),
          on_click=on_raw(true),
          "IR JSON",
        ),
      ]),
    ]),
    @html.div(contents),
  ])
}
