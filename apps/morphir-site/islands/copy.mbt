///|
/// Adds a copy button to each code block. The block is wrapped in `div.code-block`, so
/// the button stays in place when the code scrolls sideways. The copied text comes from
/// `<code>`, so the button label is never part of it.
extern "js" fn add_copy_buttons(selector : String) -> Unit =
  #| (selector) => {
  #|   const status = document.createElement("span");
  #|   status.className = "visually-hidden";
  #|   status.setAttribute("aria-live", "polite");
  #|   document.body.append(status);
  #|   for (const pre of document.querySelectorAll(selector)) {
  #|     const wrap = document.createElement("div");
  #|     wrap.className = "code-block";
  #|     pre.before(wrap);
  #|     wrap.append(pre);
  #|     const button = document.createElement("button");
  #|     button.type = "button";
  #|     button.className = "copy-button";
  #|     button.dataset.tooltip = "Copy";
  #|     button.setAttribute("aria-label", "Copy code");
  #|     let timer;
  #|     const show = (state, tip) => {
  #|       button.dataset.state = state;
  #|       button.dataset.tooltip = tip;
  #|       status.textContent = state === "idle" ? "" : tip;
  #|       clearTimeout(timer);
  #|       if (state !== "idle") timer = setTimeout(() => show("idle", "Copy"), 2000);
  #|     };
  #|     button.addEventListener("click", () => {
  #|       const text = (pre.querySelector("code") ?? pre).innerText.replace(/\n$/, "");
  #|       (navigator.clipboard?.writeText(text) ?? Promise.reject())
  #|         .then(() => show("copied", "Copied"), () => show("failed", "Copy failed"));
  #|     });
  #|     wrap.append(button);
  #|   }
  #| }
