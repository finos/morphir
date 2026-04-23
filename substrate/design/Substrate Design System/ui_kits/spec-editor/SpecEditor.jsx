/* global React, ModuleTree, SpecDocument, Inspector */
const { useState: useStateApp, useMemo } = React;

const STEPS = ['subtotal','discount_amount','discounted_subtotal','tax_amount','total','is_valid_quantity'];

function computeAll(v) {
  const subtotal = v.unit_price * v.quantity;
  const discount_amount = subtotal * v.discount_rate;
  const discounted_subtotal = subtotal - discount_amount;
  const tax_amount = discounted_subtotal * v.tax_rate;
  const total = discounted_subtotal + tax_amount;
  const is_valid_quantity = v.quantity >= 1;
  const is_valid_discount = v.discount_rate <= 1;
  const clamped_discount_rate = is_valid_discount ? v.discount_rate : 0;
  return { ...v, subtotal, discount_amount, discounted_subtotal, tax_amount, total, is_valid_quantity, is_valid_discount, clamped_discount_rate };
}

function SpecEditor() {
  const [active, setActive] = useStateApp('order-total');
  const [inputs, setInputs] = useStateApp({ unit_price: 10, quantity: 3, discount_rate: 0.1, tax_rate: 0.2 });
  const [baseline, setBaseline] = useStateApp({ unit_price: 10, quantity: 3, discount_rate: 0.05, tax_rate: 0.2 });
  const [stepIdx, setStepIdx] = useStateApp(3);
  const [mode, setMode] = useStateApp('debug'); // 'debug' | 'impact'

  const values = useMemo(()=>computeAll(inputs), [inputs]);
  const baseValues = useMemo(()=>computeAll(baseline), [baseline]);
  const step = mode==='debug' ? STEPS[stepIdx] : null;

  const diff = useMemo(()=>{
    if (mode !== 'impact') return null;
    const d = {};
    for (const k of Object.keys(values)) {
      if (typeof values[k] === 'number' && typeof baseValues[k] === 'number') {
        if (Math.abs(values[k] - baseValues[k]) > 1e-9) d[k] = { old: baseValues[k], new: values[k] };
      }
    }
    return d;
  }, [mode, values, baseValues]);

  const tests = [
    { def: 'subtotal', inputs: 'unit_price=10, quantity=3', expected: '30', status: 'pass' },
    { def: 'subtotal', inputs: 'unit_price=25, quantity=2', expected: '50', status: 'pass' },
    { def: 'discounted_subtotal', inputs: '30, 3', expected: '27', status: 'pass' },
    { def: 'total', inputs: '27, 5.4', expected: '32.4', status: 'pass' },
    { def: 'clamped_discount_rate', inputs: 'false, 2', expected: '0', status: 'pass' },
    { def: 'is_valid_quantity', inputs: 'quantity=0', expected: 'false', status: 'pass' },
  ];

  return (
    <div className="app substrate">
      <header className="topbar">
        <div className="brand">
          <img src="../../assets/logo.svg" alt=""/>
          <span className="brand-name">Substrate</span>
          <span className="brand-sub">spec editor</span>
        </div>
        <div className="breadcrumbs">
          <a href="#">corpus</a> <span className="sep">/</span>
          <a href="#">examples</a> <span className="sep">/</span>
          <b>order-total.md</b>
        </div>
        <div className="top-actions">
          <span className="s-chip ok">✓ 24/24 passed</span>
          <button className="s-btn secondary">Export</button>
          <button className="s-btn">Bind live data</button>
        </div>
      </header>

      <div className="work">
        <aside className="left-rail">
          <ModuleTree active={active} onPick={setActive} />
        </aside>

        <main className="reader">
          <div className={'reader-mode-banner ' + mode}>
            {mode === 'debug'
              ? <>Stepping: <b>{step}</b> — values overlaid inline. Use <kbd>←</kbd> <kbd>→</kbd> or the inspector.</>
              : <>Impact diff vs. <code>discount_rate = {baseline.discount_rate}</code>. Orange chips show old → new.</>}
          </div>
          <SpecDocument values={values} step={step} diff={diff} />
        </main>

        <aside className="right-rail">
          <Inspector
            values={inputs}
            onBind={(k,v)=>setInputs({...inputs, [k]: v})}
            onStep={(d)=>setStepIdx(Math.max(0, Math.min(STEPS.length-1, stepIdx + d)))}
            onReplay={()=>{setStepIdx(0); setMode('debug');}}
            mode={mode}
            setMode={setMode}
            step={step}
            testResults={tests}
          />
        </aside>
      </div>

      <footer className="statusbar">
        <span><span className="s-chip blue">bound · in-memory</span></span>
        <span>8 definitions · 24 test cases · 0 unreachable</span>
        <span>substrate 0.1.0</span>
      </footer>
    </div>
  );
}

window.SpecEditor = SpecEditor;
