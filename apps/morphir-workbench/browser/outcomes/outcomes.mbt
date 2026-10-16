///|
fn kind_class(kind : @terminal_model.Kind) -> String {
  match kind {
    Returned => "returned"
    ModelError => "model-error"
    Failed => "failed"
    Cancelled => "cancelled"
  }
}

///|
/// Shared by evaluation and history. Native disclosure does not remount editors.
pub fn view(
  projection : @terminal_model.Projection,
  show_values~ : Bool = false,
) -> @html.Html {
  match projection {
    Absent => @html.div(hidden=true, "")
    Invalid(code) =>
      @html.p(class="terminal-invalid", [
        @html.strong("Terminal evidence rejected"),
        @html.code(code),
      ])
    Valid(summary) =>
      @html.section(
        class="terminal-outcomes",
        attrs=@html.Attrs::build().aria_label("Terminal outcomes"),
        [
          @html.ol(
            class="terminal-calls",
            summary.calls.map(call => {
              @html.li(class="terminal-call " + kind_class(call.kind), [
                @html.div(class="terminal-heading", [
                  @html.strong(class="terminal-kind", call.kind.label()),
                  @html.code(class="terminal-id", "call " + call.id),
                  @html.span(
                    class="terminal-stage",
                    hidden=call.stage == "",
                    call.stage,
                  ),
                ]),
                @html.div(
                  class="terminal-cause",
                  hidden=call.code == "" && call.message == "",
                  [
                    @html.code(
                      class="terminal-code",
                      hidden=call.code == "",
                      call.code,
                    ),
                    @html.span(call.message),
                  ],
                ),
                @html.pre(
                  class="terminal-preview",
                  hidden=!show_values || call.preview == "",
                  call.preview,
                ),
              ])
            }),
          ),
          match summary.cleanup {
            None => @html.div(hidden=true, "")
            Some(cleanup) =>
              @html.div(
                class="terminal-cleanup",
                attrs=@html.Attrs::build().aria_label("Cleanup failure"),
                [
                  @html.strong("Cleanup failed"),
                  @html.code(class="terminal-code", cleanup.code),
                  @html.span(cleanup.message),
                ],
              )
          },
          @html.p(
            class="terminal-omitted",
            hidden=summary.omitted == 0,
            summary.omitted.to_string() +
            " more calls are not shown in this bounded preview.",
          ),
        ],
      )
  }
}
