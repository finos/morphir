///|
extern "js" fn element_exists(id : String) -> Bool =
  #| (id) => document.getElementById(id) !== null

///|
extern "js" fn base_path() -> String =
  #| () => document.documentElement.dataset.base ?? "/"

///|
extern "js" fn mark_js() -> Unit =
  #| () => { document.documentElement.dataset.js = "true" }

///|
extern "js" fn focus_search_on_slash() -> Unit =
  #| () => document.addEventListener("keydown", (e) => {
  #|   const t = document.activeElement?.tagName;
  #|   if (e.key === "/" && t !== "INPUT" && t !== "TEXTAREA") {
  #|     e.preventDefault(); document.getElementById("search-input")?.focus();
  #|   }
  #| })

///|
fn main {
  mark_js()
  let base = base_path()
  if element_exists("site-search") {
    @rabbita.new(() => search_box(base)).mount("site-search")
    focus_search_on_slash()
  }
  if element_exists("site-theme") {
    @rabbita.new(theme_toggle).mount("site-theme")
  }
  if element_exists("site-nav") {
    @rabbita.new(menu_toggle).mount("site-nav")
  }
  add_copy_buttons(".prose pre, .code-window pre")
  if element_exists("site-toc") {
    track_toc("site-toc")
  }
}
