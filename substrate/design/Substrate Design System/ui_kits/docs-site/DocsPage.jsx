/* global React */
function DecisionTablePage() {
  return (
    <article className="docs-page substrate">
      <div className="page-breadcrumb">Language · Concepts · <b>Decision Table</b></div>
      <h1>Decision Table</h1>
      <p className="s-lede">A tabular representation of a conditional: a set of rules, evaluated top to bottom, where the first rule whose conditions all match determines the result.</p>

      <p>Decision Tables are well suited to regulatory material, rate sheets, classification rules, and any logic whose authoritative reference is itself a table. The rendered markdown table is the authoritative specification; no separate machine form is required.</p>

      <p>A declaration is identified by a heading whose text links to this concept page:</p>

      <pre><code>{`### Retail Outflow Rate [Decision Table](decision-table.md)`}</code></pre>

      <h2>Structure</h2>
      <p>A decision table declaration has three parts:</p>
      <ul>
        <li><a href="#">Inputs</a> — the named values the table reads, each with its declared type.</li>
        <li><a href="#">Outputs</a> — the named values the table produces, each with its declared type.</li>
        <li><a href="#">Rules</a> — a markdown table where each row is a rule. Column headers name an input or output; headers prefixed with <code>→</code> name outputs.</li>
      </ul>

      <h2>Condition cells</h2>
      <p>A condition cell takes one of the following forms:</p>
      <ul>
        <li><b>Literal value.</b> A bare value matches when the input is <a href="#">equal</a> to the value.</li>
        <li><b>Comparison.</b> One of <code>=</code>, <code>≠</code>, <code>&gt;</code>, <code>≥</code>, <code>&lt;</code>, <code>≤</code> followed by a literal.</li>
        <li><b>Blank (don't care).</b> An empty cell matches any input value.</li>
      </ul>

      <h2>Example</h2>
      <h3>Retail Outflow Rate <a href="#">Decision Table</a></h3>
      <h4>Rules</h4>
      <table className="spec-table">
        <thead><tr><th>counterparty</th><th>insured</th><th>account_type</th><th>relationship</th><th><span style={{color:'var(--brand-orange)'}}>→</span> outflow_rate</th></tr></thead>
        <tbody>
          <tr><td>Retail</td><td>true</td><td>Transactional</td><td></td><td><code>0.03</code></td></tr>
          <tr><td>Retail</td><td>true</td><td>Non-Transactional</td><td>Established</td><td><code>0.03</code></td></tr>
          <tr><td>Retail</td><td>true</td><td>Non-Transactional</td><td>None</td><td><code>0.10</code></td></tr>
          <tr><td>Retail</td><td>false</td><td></td><td></td><td><code>0.40</code></td></tr>
          <tr><td><em>otherwise</em></td><td></td><td></td><td></td><td><code>0.40</code></td></tr>
        </tbody>
      </table>

      <h3><a href="#">Provenance</a></h3>
      <ul>
        <li>
          <a href="#">12 CFR §249.32(a)</a>
          <blockquote>The agencies are adopting a 3 percent outflow rate for stable retail deposits, a 10 percent outflow rate for other retail deposits, and higher rates for brokered deposits reflecting their reduced stability during periods of liquidity stress.</blockquote>
        </li>
      </ul>

      <nav className="page-pager">
        <a href="#"><span>← Prev</span><b>Choice</b></a>
        <a href="#" className="next"><span>Next →</span><b>Operation</b></a>
      </nav>
    </article>
  );
}
window.DecisionTablePage = DecisionTablePage;
