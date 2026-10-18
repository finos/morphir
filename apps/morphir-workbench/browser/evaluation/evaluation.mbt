///|
/// The selected evaluation semantics, captured before dispatching work.
pub(all) enum Runtime {
  LocalScheme
  TypedInvocation
} derive(Eq)

///|
pub extend Runtime with Eq::{equal, not_equal}

///|
pub fn Runtime::is_typed(self : Runtime) -> Bool {
  match self {
    LocalScheme => false
    TypedInvocation => true
  }
}

///|
pub(all) enum InputMode {
  Fields
  Json
  Ion
} derive(Eq)

///|
pub extend InputMode with Eq::{equal, not_equal}

///|
pub(all) struct Props {
  profile : Json
  document_key : String
  arguments : String
  result : Json
  terminal : @outcomes.Projection
  stale : Bool
  busy : Bool
  connected : Bool
  executions_available : Bool
  execution_pending : Bool
  runtime : Runtime
  policy : @capabilities.CapabilityPolicy
  policy_available : Bool
  input_mode : InputMode
  result_mode : @result.Mode
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
fn input_help(schema : Json) -> String {
  match text(schema, "kind") {
    "int" => "decimal string, e.g. \"42\""
    "float" => "finite JSON number"
    "bool" => "true or false"
    "string" => "JSON string"
    "char" => "one Unicode character"
    "unit" => "null"
    "list" => "array of " + input_help(field(schema, "item"))
    "tuple" =>
      "ordered array: " +
      items(field(schema, "items")).map(input_help).join("; ")
    "record" =>
      match field(schema, "fields") {
        Object(fields) => {
          let entries = fields.iter().collect()
          entries.sort_by((a, b) => a.0.lexical_compare(b.0))
          "object { " +
          entries.map(pair => pair.0 + ": " + input_help(pair.1)).join(", ") +
          " }"
        }
        _ => "object"
      }
    "custom" =>
      "object with constructor and arguments; constructor: " +
      items(field(schema, "variants"))
      .map(variant => {
        text(variant, "constructor") +
        "(" +
        items(field(variant, "arguments")).map(input_help).join(", ") +
        ")"
      })
      .join(" | ")
    _ => text(schema, "label")
  }
}

///|
fn at(
  path : Array[@arguments.Segment],
  segment : @arguments.Segment,
) -> Array[@arguments.Segment] {
  let next = path.copy()
  next.push(segment)
  next
}

///|
fn form_field(
  schema : Json,
  value : Json,
  path : Array[@arguments.Segment],
  caption : String,
  address : String,
  emit : @cmd.Emit[@arguments.Edit],
) -> @html.Html {
  let kind = text(schema, "kind")
  if ["float", "int", "string", "char", "bool"].contains(kind) {
    let input = if kind == "bool" {
      @html.select(
        attrs=@html.Attrs::build()
          .aria_label(address)
          .value_prop(@arguments.scalar_text(value)),
        on_change=emit.map(value => @arguments.Scalar(path, kind, value)),
        [
          @html.option(
            value="false",
            selected=value == Json::boolean(false),
            "false",
          ),
          @html.option(
            value="true",
            selected=value == Json::boolean(true),
            "true",
          ),
        ],
      )
    } else if kind == "string" {
      @html.textarea(
        rows=1,
        attrs=@html.Attrs::build()
          .aria_label(address)
          .value_prop(@arguments.scalar_text(value)),
        on_input=emit.map(value => @arguments.Scalar(path, kind, value)),
        "",
      )
    } else {
      @html.input(
        inputmode=if kind == "float" {
          "decimal"
        } else if kind == "int" {
          "numeric"
        } else {
          "text"
        },
        attrs=@html.Attrs::build()
          .aria_label(address)
          .value_prop(@arguments.scalar_text(value)),
        on_input=emit.map(value => @arguments.Scalar(path, kind, value)),
      )
    }
    return @html.label(class="argument-field", [
      @html.span(class="argument-field-label", [
        @html.strong(caption),
        @html.code(text(schema, "label")),
      ]),
      input,
    ])
  }
  if kind == "unit" {
    return @html.div(class="argument-unit", [
      @html.strong(caption),
      @html.code("() · no value required"),
    ])
  }
  let children : Array[@html.Html] = [
    @html.legend([@html.strong(caption), @html.code(text(schema, "label"))]),
  ]
  if kind == "record" {
    let fields = match field(schema, "fields") {
      Object(fields) => fields.iter().collect()
      _ => []
    }
    fields.sort_by((a, b) => a.0.lexical_compare(b.0))
    for (key, child) in fields {
      children.push(
        form_field(
          child,
          field(value, key),
          at(path, @arguments.Field(key)),
          key,
          address + "." + key,
          emit,
        ),
      )
    }
  } else if kind == "tuple" {
    let values = items(value)
    for i, child in items(field(schema, "items")) {
      children.push(
        form_field(
          child,
          values[i],
          at(path, @arguments.Index(i)),
          "Item " + (i + 1).to_string(),
          address + "[" + (i + 1).to_string() + "]",
          emit,
        ),
      )
    }
  } else if kind == "list" {
    let values = items(value)
    let child = field(schema, "item")
    for i, value in values {
      let address = address + "[" + (i + 1).to_string() + "]"
      children.push(
        @html.div(class="argument-list-item", [
          form_field(
            child,
            value,
            at(path, @arguments.Index(i)),
            "Item " + (i + 1).to_string(),
            address,
            emit,
          ),
          @html.button(
            class="argument-remove secondary",
            attrs=@html.Attrs::build().aria_label("Remove " + address),
            on_click=emit(@arguments.Remove(path, i)),
            "Remove",
          ),
        ]),
      )
    }
    if values.is_empty() {
      children.push(@html.p(class="small muted", "No items"))
    }
    children.push(
      @html.button(
        class="secondary",
        attrs=@html.Attrs::build().aria_label("Add item to " + address),
        on_click=emit(@arguments.Append(path, field(child, "default"))),
        "Add item",
      ),
    )
  } else if kind == "custom" {
    let variants = items(field(schema, "variants"))
    let tag = text(value, "constructor")
    children.push(
      @html.label(class="argument-field", [
        @html.span("Constructor"),
        @html.select(
          attrs=@html.Attrs::build()
            .aria_label(address + " constructor")
            .value_prop(tag),
          on_change=emit.map(tag => {
            let variant = variants
              .iter()
              .find_first(variant => text(variant, "constructor") == tag)
              .unwrap()
            @arguments.Set(path, field(variant, "default"))
          }),
          variants.map(variant => {
            @html.option(
              value=text(variant, "constructor"),
              selected=text(variant, "constructor") == tag,
              title=text(variant, "constructor"),
              text(variant, "label"),
            )
          }),
        ),
      ]),
    )
    let variant = variants
      .iter()
      .find_first(variant => text(variant, "constructor") == tag)
      .unwrap()
    let values = items(field(value, "arguments"))
    let labels = items(field(variant, "argumentLabels"))
    for i, child in items(field(variant, "arguments")) {
      let caption = match labels[i] {
        String(label) => label
        _ => "Argument " + (i + 1).to_string()
      }
      children.push(
        form_field(
          child,
          values[i],
          at(at(path, @arguments.Field("arguments")), @arguments.Index(i)),
          caption,
          address + "." + caption,
          emit,
        ),
      )
    }
  }
  @html.fieldset(class="argument-group", children)
}

///|
fn form_view(props : Props, emit : @cmd.Emit[@arguments.Edit]) -> @html.Html {
  match @arguments.form_error(props.profile, props.arguments) {
    Some(error) =>
      @html.div(class="argument-shape-error", [
        @html.p(error),
        @html.p(
          class="small muted",
          "Use JSON inputs to repair or edit this document, or reset to the model’s defaults.",
        ),
        @html.button(
          class="secondary",
          on_click=emit(@arguments.Set([], field(props.profile, "default"))),
          "Reset inputs",
        ),
      ])
    None => {
      let values = items(
        @wire.parse(props.arguments) catch {
          _ => Json::null()
        },
      )
      @html.div(
        class="argument-fields",
        items(field(props.profile, "inputs")).mapi((i, input) => {
          form_field(
            field(input, "schema"),
            values[i],
            [@arguments.Index(i)],
            text(input, "label"),
            text(input, "label"),
            emit,
          )
        }),
      )
    }
  }
}

///|
/// Independent controlled component using the same editor as the source experience.
pub fn view(
  props : Props,
  on_change : @cmd.Emit[String],
  on_run : @cmd.Cmd,
  on_mode : @cmd.Emit[InputMode],
  on_edit : @cmd.Emit[@arguments.Edit],
  on_result_mode : @cmd.Emit[@result.Mode],
  on_runtime : @cmd.Emit[Runtime],
  on_policy : @cmd.Emit[@capabilities.CapabilityPolicy],
) -> @html.Html {
  let captured_policy = Some(
    @capabilities.selection_from_json(field(props.result, "admission")),
  ) catch {
    _ => None
  }
  let heading : Array[@html.Html] = [@html.h3("Evaluate function")]
  if !props.connected {
    heading.push(
      @html.div(
        class="segmented",
        attrs=@html.Attrs::build()
          .role("group")
          .aria_label("Evaluation runtime"),
        [
          @html.button(
            disabled=props.execution_pending,
            class=if !props.runtime.is_typed() { "selected" } else { "" },
            attrs=@html.Attrs::build().aria_pressed(
              (!props.runtime.is_typed()).to_string(),
            ),
            on_click=on_runtime(LocalScheme),
            "Local Scheme",
          ),
          @html.button(
            disabled=props.execution_pending,
            class=if props.runtime.is_typed() { "selected" } else { "" },
            attrs=@html.Attrs::build().aria_pressed(
              props.runtime.is_typed().to_string(),
            ),
            on_click=on_runtime(TypedInvocation),
            "Typed invocation",
          ),
        ],
      ),
    )
  }
  let contents : Array[@html.Html] = [
    @html.div(class="evaluation-heading", heading),
  ]
  let incompatible = props.runtime.is_typed() &&
    props.policy == @capabilities.CapabilityPolicy::Permissive &&
    !props.policy_available
  if props.runtime.is_typed() {
    contents.push(
      @html.label(class="checking-policy small", [
        @html.span("Capability checks"),
        @html.select(
          disabled=props.execution_pending,
          attrs=@html.Attrs::build()
            .aria_label("Capability checks")
            .value_prop(@capabilities.policy_value(props.policy)),
          on_change=@cmd.Emit(value => {
            match @capabilities.policy_from_control(value) {
              Some(policy) => on_policy(policy)
              None => @cmd.none
            }
          }),
          [
            @html.option(
              value="strict",
              selected=props.policy == @capabilities.CapabilityPolicy::Strict,
              @capabilities.policy_label(@capabilities.CapabilityPolicy::Strict),
            ),
            @html.option(
              value="permissive",
              selected=props.policy ==
                @capabilities.CapabilityPolicy::Permissive,
              disabled=!props.policy_available,
              @capabilities.policy_label(
                @capabilities.CapabilityPolicy::Permissive,
              ),
            ),
          ],
        ),
      ]),
    )
    if incompatible || !props.policy_available {
      contents.push(
        @html.p(
          class="small muted",
          if incompatible {
            "The selected checking policy is unavailable for this runtime or function. Choose whole-model checks or return to a supported local typed function. Your inputs are retained."
          } else {
            "Checking as code executes is unavailable for this runtime or function. Whole-model checks remain selected."
          },
        ),
      )
    }
  }
  let supported = field(props.profile, "supported") == Json::boolean(true)
  if props.connected && !props.executions_available {
    contents.push(
      @html.p(
        class="muted",
        "Evaluation is unavailable in connected protocol v1. The upstream evaluation profile is tracked separately.",
      ),
    )
  } else if !supported {
    contents.push(
      @html.p(
        class="muted",
        if text(props.profile, "reason") == "" {
          "This model has no local executable definition."
        } else {
          text(props.profile, "reason")
        },
      ),
    )
  } else {
    contents.push(
      @html.p(
        class="muted small",
        if props.connected {
          "Evaluated by the authenticated bounded host runtime. Inputs are captured when the execution is submitted."
        } else if props.runtime.is_typed() {
          "Each run starts in a fresh bounded runtime. Tagged JSON preserves exact numbers, UTF-16 units and constructor identity."
        } else {
          "Each run starts in a fresh local runtime. Use JSON or Ion inputs for larger values."
        },
      ),
    )
    let inputs = items(field(props.profile, "inputs"))
    if props.runtime.is_typed() {
      if props.input_mode == Ion {
        contents.push(
          @html.p(
            class="small muted",
            "Enter one Ion list in parameter order. Int, Bool and Decimal are native values; rich values use morphir_value annotations.",
          ),
        )
      }
      if text(props.profile, "defaultReason") != "" {
        contents.push(
          @html.p(class="small muted", text(props.profile, "defaultReason")),
        )
      }
      contents.push(
        @html.details(class="evaluation-types", [
          @html.summary("Input and output types"),
          @html.pre(props.profile.stringify()),
        ]),
      )
      if !inputs.is_empty() {
        contents.push(mode_switch(props.input_mode, on_mode))
        if props.input_mode != Fields {
          contents.push(
            @html.div(class="evaluation-editor", [
              @editor.view(
                {
                  id: "evaluation-input",
                  document_key: props.document_key +
                  (if props.input_mode == Ion { "-ion" } else { "-json" }),
                  value: props.arguments,
                  language: if props.input_mode == Ion {
                    "ion"
                  } else {
                    "json"
                  },
                  label: "Function arguments",
                  read_only: false,
                  marks: "",
                  reveal: "",
                },
                on_change~,
              ),
            ]),
          )
        } else {
          contents.push(
            @typed_input.view(
              { profile: props.profile, arguments: props.arguments, },
              on_edit,
            ),
          )
        }
      }
    } else if !inputs.is_empty() {
      contents.push(mode_switch(props.input_mode, on_mode))
      if props.input_mode != Fields {
        if props.input_mode == Ion {
          contents.push(
            @html.p(
              class="small muted",
              "Enter one Ion list in parameter order using JSON-compatible shapes. Int also accepts a native Ion integer. Annotations, symbols, timestamps, typed nulls and binary values require the published typed profile.",
            ),
          )
        }
        contents.push(
          @html.ol(
            class="evaluation-input-help",
            inputs.map(input => {
              @html.li([
                @html.strong(text(input, "label")),
                @html.span(" · " + input_help(field(input, "schema"))),
              ])
            }),
          ),
        )
        contents.push(
          @html.div(class="evaluation-editor", [
            @editor.view(
              {
                id: "evaluation-input",
                document_key: props.document_key +
                (if props.input_mode == Ion { "-ion" } else { "-json" }),
                value: props.arguments,
                language: if props.input_mode == Ion {
                  "ion"
                } else {
                  "json"
                },
                label: "Function arguments",
                read_only: false,
                marks: "",
                reveal: "",
              },
              on_change~,
            ),
          ]),
        )
      } else {
        contents.push(form_view(props, on_edit))
      }
    }
    contents.push(
      @html.div(class="evaluation-actions", [
        @html.button(
          class="primary",
          disabled=props.busy || props.execution_pending || incompatible,
          on_click=on_run,
          "Evaluate",
        ),
        @html.span(
          class="muted small",
          if inputs.is_empty() {
            "No arguments required"
          } else {
            "Validated against the model’s input types"
          },
        ),
      ]),
    )
  }
  if props.result != Json::null() {
    contents.push(
      @html.div(
        class=if props.stale {
          "evaluation-result stale"
        } else if props.terminal is Valid(summary) && summary.has_value() {
          "evaluation-result"
        } else if props.terminal is Valid(summary) &&
          summary.calls.all(c => c.kind == @outcomes.Cancelled) {
          "evaluation-result cancelled"
        } else if field(props.result, "success") != Json::boolean(true) {
          "evaluation-result failed"
        } else {
          "evaluation-result"
        },
        [
          @html.p(
            class="small muted evaluation-result-heading",
            if props.stale {
              "Inputs changed · evaluate again"
            } else if props.terminal is Valid(summary) && !summary.has_value() {
              summary.heading()
            } else if props.terminal is Valid(summary) &&
              summary.cleanup != None {
              "Result · " + text(props.result, "profile")
            } else if field(props.result, "success") == Json::boolean(true) {
              if props.runtime.is_typed() {
                "Result · " +
                text(props.result, "profile") +
                (if text(props.result, "outcome") == "model-error" {
                  " · model error"
                } else {
                  ""
                })
              } else {
                "Result · local runtime"
              }
            } else {
              "Evaluation failed"
            },
          ),
          @html.p(
            hidden=captured_policy is None,
            class="small muted captured-policy",
            "Run checks · " +
            (match captured_policy {
              Some(policy) => @capabilities.policy_label(policy)
              None => ""
            }),
          ),
          @terminal_view.view(props.terminal),
          @result.view(
            {
              result: props.result,
              terminal: props.terminal,
              document_key: props.document_key + "-result",
              mode: props.result_mode,
            },
            on_result_mode,
          ),
        ],
      ),
    )
  }
  @html.section(class="declaration-section function-evaluation", contents)
}

///|
fn mode_switch(mode : InputMode, emit : @cmd.Emit[InputMode]) -> @html.Html {
  @html.div(
    class="view-tabs",
    attrs=@html.Attrs::build().role("group").aria_label("Argument input mode"),
    [(Fields, "Input fields"), (Json, "JSON inputs"), (Ion, "Ion inputs")].map(choice => {
      @html.button(
        class=if mode == choice.0 { "selected" } else { "" },
        attrs=@html.Attrs::build().aria_pressed((mode == choice.0).to_string()),
        on_click=emit(choice.0),
        choice.1,
      )
    }),
  )
}
