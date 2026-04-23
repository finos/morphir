/* global React */
function DocsNav({ active, onPick }) {
  const sections = [
    { name: 'Getting started', items: [
      ['intro', 'Introduction'],
      ['vision', 'Vision'],
      ['install', 'Install'],
    ]},
    { name: 'Language', items: [
      ['concepts', 'Concepts'],
    ]},
    { name: 'Concepts', items: [
      ['record', 'Record'],
      ['choice', 'Choice'],
      ['decision-table', 'Decision Table', true],
      ['operation', 'Operation'],
      ['provenance', 'Provenance'],
      ['type-class', 'Type Class'],
    ], indent: 1 },
    { name: 'Expressions', items: [
      ['boolean', 'Boolean'],
      ['number', 'Number'],
      ['ordering', 'Ordering'],
      ['collection', 'Collection'],
      ['string', 'String'],
      ['date', 'Date'],
    ], indent: 1 },
    { name: 'Tools', items: [
      ['cli', 'CLI'],
    ]},
  ];
  return (
    <nav className="docs-nav">
      {sections.map(s => (
        <div key={s.name} className={'nav-section indent-' + (s.indent||0)}>
          <div className="nav-eyebrow">{s.name}</div>
          <ul>
            {s.items.map(([id, label]) => (
              <li key={id}>
                <a className={active===id?'active':''} onClick={(e)=>{e.preventDefault();onPick(id);}} href="#">{label}</a>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </nav>
  );
}
window.DocsNav = DocsNav;
