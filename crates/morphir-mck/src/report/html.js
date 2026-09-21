(() => {
  "use strict";
  const form = document.getElementById("filters");
  const search = document.getElementById("case-search");
  const filters = [
    ["outcome-filter", "outcome"], ["ir-filter", "ir"],
    ["profile-filter", "profile"], ["path-filter", "path"]
  ].map(([id, key]) => [document.getElementById(id), key]);
  const rows = Array.from(document.querySelectorAll("tr[data-case]"));
  const cases = Array.from(document.querySelectorAll("section.case"));
  const counter = document.getElementById("shown-count");
  const update = () => {
    const query = search.value.trim().toLowerCase();
    const counts = {pass: 0, fail: 0, "kit-error": 0, skipped: 0};
    let shown = 0;
    for (const row of rows) {
      row.hidden = !row.dataset.case.toLowerCase().includes(query) ||
        filters.some(([control, key]) => control.value && row.dataset[key] !== control.value);
      if (!row.hidden) { shown++; counts[row.dataset.outcome]++; }
    }
    let shownCases = 0;
    for (const group of cases) {
      group.hidden = !Array.from(group.querySelectorAll("tr[data-case]")).some(row => !row.hidden);
      if (!group.hidden) shownCases++;
    }
    counter.textContent = `Showing ${shown} of ${rows.length} records across ${shownCases} of ${cases.length} cases. Shown outcomes: ${counts.pass} pass, ${counts.fail} fail, ${counts["kit-error"]} kit-error, ${counts.skipped} skipped.`;
    document.getElementById("no-matches").hidden = shown > 0 || rows.length === 0;
  };
  form.addEventListener("submit", event => event.preventDefault());
  form.addEventListener("input", update);
  form.addEventListener("change", update);
  form.addEventListener("reset", () => setTimeout(update, 0));
  document.getElementById("expand-details").addEventListener("click", () => {
    for (const row of rows.filter(row => !row.hidden)) {
      const details = row.querySelector("details");
      if (details) details.open = true;
    }
  });
  document.getElementById("collapse-details").addEventListener("click", () => {
    document.querySelectorAll("details.diagnostic").forEach(details => { details.open = false; });
  });
  // Attention links remain useful after filtering a record out of view.
  document.querySelectorAll('a[href^="#record-"]').forEach(link => {
    link.addEventListener("click", () => {
      form.reset();
      update();
      const target = document.getElementById(link.getAttribute("href").slice(1));
      const details = target.querySelector("details");
      if (details) details.open = true;
    });
  });
  // Include closed disclosures in print, then restore the reader's view.
  let printState = [];
  window.addEventListener("beforeprint", () => {
    printState = Array.from(document.querySelectorAll("details"), item => [item, item.open]);
    printState.forEach(([item]) => { item.open = true; });
  });
  window.addEventListener("afterprint", () => {
    printState.forEach(([item, open]) => { item.open = open; });
  });
  form.hidden = false;
  update();
})();
