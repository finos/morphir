///|
extern "js" fn stored_theme() -> String =
  #| () => { try { return localStorage.getItem("site-theme") ?? "system" } catch (e) { return "system" } }

///|
extern "js" fn apply_theme(theme : String) -> Unit =
  #| (theme) => {
  #|   try { localStorage.setItem("site-theme", theme) } catch (e) {}
  #|   if (theme === "system") delete document.documentElement.dataset.theme;
  #|   else document.documentElement.dataset.theme = theme;
  #| }

///|
fn next_theme(theme : String) -> String {
  match theme {
    "system" => "light"
    "light" => "dark"
    _ => "system"
  }
}

///|
fn theme_toggle() -> @rabbita.Val[@html.Html] {
  let (theme, emit) = @rabbita.create_state(stored_theme(), update=(
    theme,
    _msg : Unit,
    _,
  ) => {
    let next = next_theme(theme)
    (next, @rabbita.effect(fn() noraise { apply_theme(next) }))
  })
  theme.view(t => {
    @html.button(
      class="theme-toggle",
      type_="button",
      on_click=emit(()),
      attrs=@html.Attrs::build().aria_label("Colour theme: \{t}"),
      "Theme: \{t}",
    )
  })
}
