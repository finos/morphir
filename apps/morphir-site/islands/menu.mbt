///|
extern "js" fn set_menu_open(open : Bool) -> Unit =
  #| (open) => { if (open) document.documentElement.dataset.navOpen = "true"; else delete document.documentElement.dataset.navOpen }

///|
fn menu_toggle() -> @rabbita.Val[@html.Html] {
  let (open, emit) = @rabbita.create_state(false, update=(open, _msg : Unit, _) => {
    let next = !open
    (next, @rabbita.effect(fn() noraise { set_menu_open(next) }))
  })
  open.view(o => {
    @html.button(
      class="menu-toggle",
      type_="button",
      on_click=emit(()),
      attrs=@html.Attrs::build()
        .aria_expanded(if o { "true" } else { "false" })
        .aria_controls("site-links"),
      "Menu",
    )
  })
}
