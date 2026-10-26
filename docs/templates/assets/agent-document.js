addEventListener("DOMContentLoaded", () => {
  if (!window.hljs) return; // highlight.js did not load: plain code blocks
  hljs.registerAliases(["moonbit", "mbt"], { languageName: "rust" }); // the closest bundled grammar
  hljs.highlightAll();
});
