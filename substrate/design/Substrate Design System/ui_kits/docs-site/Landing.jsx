/* global React, CliDemo */
function Landing({ onCta }) {
  return (
    <div className="landing">
      <div className="lattice-host" id="lattice-host"></div>
      <div className="landing-inner">
        <header className="lead">
          <div className="eyebrow">A FINOS project · v0.1.0</div>
          <h1>Executable specifications, in markdown.</h1>
          <p className="s-lede">Substrate is an LLM-native specification language. The specification is the program — a typed dataflow graph of transformations and decisions, traceable to the natural language it was derived from.</p>
          <div className="cta-row">
            <button className="s-btn" onClick={onCta}>Read the vision</button>
            <button className="s-btn secondary">View on GitHub</button>
          </div>
        </header>

        <section className="three-up">
          <div>
            <div className="threeup-eyebrow">Semantics over syntax</div>
            <p>There is no rigid grammar. The canonical representation is GitHub-flavored Markdown, enriched with links between operations and types.</p>
          </div>
          <div>
            <div className="threeup-eyebrow">Spec-first</div>
            <p>The executable specification is the single source of truth — for documentation, tests, runtime, and projection to target languages.</p>
          </div>
          <div>
            <div className="threeup-eyebrow">LLM-native</div>
            <p>Designed for natural-language extraction, partial regeneration, structure-aware diffing, and deterministic refinement.</p>
          </div>
        </section>

        <section className="demo-slab">
          <div className="demo-copy">
            <div className="eyebrow">Command line</div>
            <h2>A specification runs like a test suite.</h2>
            <p>The <code>substrate</code> CLI parses, evaluates, and tests the test cases embedded in a user module. Exits non-zero on failure — the same shape as any other linter or test runner in a CI pipeline.</p>
            <ul className="cli-flags">
              <li><code>test</code> — run every embedded case</li>
              <li><code>eval</code> — evaluate a single definition with supplied inputs</li>
              <li><code>list</code> — inspect the module's structure</li>
            </ul>
          </div>
          <CliDemo/>
        </section>
      </div>
    </div>
  );
}
window.Landing = Landing;
