///|
/// Marks the "On this page" link of the heading at the top of the view with
/// `aria-current="location"`. The links are server-rendered; this only sets the marker.
extern "js" fn track_toc(id : String) -> Unit =
  #| (id) => {
  #|   const links = [...document.getElementById(id).querySelectorAll("a[href^='#']")];
  #|   const targets = links.map((a) => document.getElementById(decodeURIComponent(a.hash.slice(1))));
  #|   let current = -1, queued = false;
  #|   const update = () => {
  #|     queued = false;
  #|     const line = (document.querySelector(".site-header")?.offsetHeight ?? 0) + 24;
  #|     let next = 0;
  #|     targets.forEach((t, i) => { if (t && t.getBoundingClientRect().top <= line) next = i; });
  #|     if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2) next = links.length - 1;
  #|     if (next === current) return;
  #|     links[current]?.removeAttribute("aria-current");
  #|     links[next]?.setAttribute("aria-current", "location");
  #|     current = next;
  #|   };
  #|   addEventListener("scroll", () => { if (!queued) { queued = true; requestAnimationFrame(update); } }, { passive: true });
  #|   addEventListener("resize", update);
  #|   update();
  #| }
