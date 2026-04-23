/* global React */
const { useState } = React;

function ModuleTree({ active, onPick }) {
  const modules = [
    { id: 'order-total', name: 'order-total.md', defs: ['subtotal','discount_amount','discounted_subtotal','tax_amount','total','is_valid_quantity','is_valid_discount','clamped_discount_rate'] },
    { id: 'retail-outflow', name: 'retail-outflow.md', defs: ['outflow_rate'] },
    { id: 'counterparty', name: 'counterparty.md', defs: ['classification'] },
  ];
  return (
    <div className="tree">
      <div className="tree-eyebrow">Corpus</div>
      <div className="tree-folder">
        <span className="tree-folder-name">examples/</span>
        {modules.map(m => (
          <div key={m.id} className={'tree-mod ' + (active===m.id?'active':'')} onClick={()=>onPick(m.id)}>
            <div className="tree-mod-name">{m.name}</div>
            {active===m.id && (
              <ul className="tree-defs">
                {m.defs.map(d => <li key={d}><code>{d}</code></li>)}
              </ul>
            )}
          </div>
        ))}
      </div>
      <div className="tree-eyebrow">Inputs</div>
      <div className="tree-inputs">
        <div><code>unit_price</code><span>Decimal</span></div>
        <div><code>quantity</code><span>Integer</span></div>
        <div><code>discount_rate</code><span>Decimal</span></div>
        <div><code>tax_rate</code><span>Decimal</span></div>
      </div>
    </div>
  );
}

window.ModuleTree = ModuleTree;
