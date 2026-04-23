/* global React */
const { useState: useStateIns } = React;

function Inspector({ values, onBind, onStep, onReplay, mode, setMode, step, testResults }) {
  return (
    <div className="inspector">
      <div className="insp-section">
        <div className="insp-eyebrow">Bound data</div>
        <div className="insp-kv">
          <label><span>unit_price</span><input className="s-input" value={values.unit_price} onChange={e=>onBind('unit_price', +e.target.value)} /></label>
          <label><span>quantity</span><input className="s-input" value={values.quantity} onChange={e=>onBind('quantity', +e.target.value)} /></label>
          <label><span>discount_rate</span><input className="s-input" value={values.discount_rate} onChange={e=>onBind('discount_rate', +e.target.value)} /></label>
          <label><span>tax_rate</span><input className="s-input" value={values.tax_rate} onChange={e=>onBind('tax_rate', +e.target.value)} /></label>
        </div>
      </div>

      <div className="insp-section">
        <div className="insp-eyebrow">Step through</div>
        <div className="insp-step">
          <button className="s-btn secondary" onClick={()=>onStep(-1)}>◀ Prev</button>
          <div className="step-name">{step || <em>idle</em>}</div>
          <button className="s-btn secondary" onClick={()=>onStep(1)}>Next ▶</button>
        </div>
        <div className="insp-actions">
          <button className="s-btn primary-blue" onClick={()=>setMode('debug')}>Step</button>
          <button className="s-btn primary-orange" onClick={()=>setMode('impact')}>Impact diff</button>
          <button className="s-btn secondary" onClick={onReplay}>Replay</button>
        </div>
      </div>

      <div className="insp-section">
        <div className="insp-eyebrow">Tests · order-total.md</div>
        <div className="insp-tests">
          {testResults.map((t,i)=>(
            <div key={i} className={'t-row ' + t.status}>
              <span className={'s-chip ' + (t.status==='pass'?'ok':'fail')}>{t.status==='pass'?'✓':'✗'}</span>
              <code>{t.def}</code>
              <span className="t-inputs">{t.inputs}</span>
              <span className="t-val">{t.expected}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="insp-section provenance">
        <div className="insp-eyebrow">Provenance · <code>total</code></div>
        <div className="prov-list">
          <a href="#">examples/order-total.md §Definitions</a>
          <div className="prov-quote">“Final amount due.”</div>
        </div>
      </div>
    </div>
  );
}

window.Inspector = Inspector;
