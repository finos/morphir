/* global React, DocsNav, Landing, DecisionTablePage */
const { useState: useStateDocs, useEffect: useEffectDocs } = React;

function DocsSite() {
  const [page, setPage] = useStateDocs('intro');

  useEffectDocs(() => {
    if (page === 'intro' && window.SubstrateLattice) {
      const host = document.getElementById('lattice-host');
      if (host && !host.dataset.installed) {
        window.SubstrateLattice.install(host);
        host.dataset.installed = '1';
      }
    }
  }, [page]);

  return (
    <div className="docs-app substrate">
      <header className="docs-top">
        <a href="#" className="docs-brand" onClick={(e)=>{e.preventDefault();setPage('intro');}}>
          <img src="../../assets/logo.svg" alt=""/>
          <span>Substrate</span>
        </a>
        <nav className="docs-topnav">
          <a className={page==='intro'?'active':''} onClick={(e)=>{e.preventDefault();setPage('intro');}} href="#">Overview</a>
          <a className={page!=='intro'?'active':''} onClick={(e)=>{e.preventDefault();setPage('decision-table');}} href="#">Docs</a>
          <a href="#">Examples</a>
          <a href="#">Blog</a>
        </nav>
        <div className="docs-top-right">
          <div className="search"><span>⌘K</span> Search the corpus</div>
          <a className="s-btn secondary" href="#">GitHub</a>
        </div>
      </header>

      {page === 'intro' ? (
        <Landing onCta={()=>setPage('decision-table')} />
      ) : (
        <div className="docs-work">
          <aside className="docs-sidebar">
            <DocsNav active={page} onPick={setPage} />
          </aside>
          <main className="docs-main">
            <DecisionTablePage/>
          </main>
          <aside className="docs-toc">
            <div className="toc-eyebrow">On this page</div>
            <ul>
              <li><a href="#">Structure</a></li>
              <li><a href="#">Condition cells</a></li>
              <li><a href="#">Result cells</a></li>
              <li><a href="#">Otherwise row</a></li>
              <li><a href="#">Completeness</a></li>
              <li><a href="#">Example</a></li>
            </ul>
          </aside>
        </div>
      )}

      <footer className="docs-footer">
        <div className="foot-brand">
          <img src="../../assets/logo-mono-ink.svg" alt=""/>
          <span>Substrate · a FINOS project</span>
        </div>
        <div className="foot-links">
          <a href="#">GitHub</a>
          <a href="#">Spec</a>
          <a href="#">CLI</a>
          <a href="#">License</a>
        </div>
      </footer>
    </div>
  );
}
window.DocsSite = DocsSite;
