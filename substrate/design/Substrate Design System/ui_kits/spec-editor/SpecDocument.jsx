/* global React */
const { useState: useStateDoc } = React;

// Rendered markdown of order-total.md with live value overlays.
function SpecDocument({ values, step, diff }) {
  // values: { name: number } — current bound outputs
  // step: name of active step or null
  // diff: { name: {old, new} } or null

  const V = (name) => {
    if (values[name] === undefined) return null;
    const d = diff && diff[name];
    if (d) {
      return (
        <span className="val-chip diff">
          <span className="old">{formatNum(d.old)}</span>
          <span className="arr">→</span>
          <span className="new">{formatNum(d.new)}</span>
        </span>
      );
    }
    return <span className={'val-chip' + (step===name?' active':'')}>{formatNum(values[name])}</span>;
  };

  return (
    <article className="spec-doc substrate">
      <header className="spec-head">
        <div className="path">examples / <b>order-total.md</b></div>
        <h1>Order Total</h1>
        <p className="s-lede">Calculates the total amount due for a customer order, including a percentage discount and sales tax.</p>
      </header>

      <h2>Inputs</h2>
      <ul className="input-list">
        <li><code>unit_price</code> — price per individual item <span className="val-chip bound">{formatNum(values.unit_price)}</span></li>
        <li><code>quantity</code> — number of items ordered <span className="val-chip bound">{formatNum(values.quantity)}</span></li>
        <li><code>discount_rate</code> — fractional discount rate <span className="val-chip bound">{formatNum(values.discount_rate)}</span></li>
        <li><code>tax_rate</code> — fractional sales tax rate <span className="val-chip bound">{formatNum(values.tax_rate)}</span></li>
      </ul>

      <h2>Definitions</h2>

      <Definition id="subtotal" title="subtotal" desc="Gross cost before discount or tax." step={step} valueEl={V('subtotal')}>
        <pre className="op-tree">
{'- '}<span className="op">Multiply</span>{'\n'}
{'  - '}<span className="id">unit_price</span>{'\n'}
{'  - '}<span className="id">quantity</span>
        </pre>
      </Definition>

      <Definition id="discount_amount" title="discount_amount" desc="Amount deducted from the subtotal." step={step} valueEl={V('discount_amount')}>
        <pre className="op-tree">
{'- '}<span className="id">subtotal</span> <span className="op">×</span> <span className="id">discount_rate</span>
        </pre>
      </Definition>

      <Definition id="discounted_subtotal" title="discounted_subtotal" desc="Cost after applying the discount." step={step} valueEl={V('discounted_subtotal')}>
        <pre className="op-tree">
{'- '}<span className="op">Subtract</span>{'\n'}
{'  - '}<span className="id">subtotal</span>{'\n'}
{'  - '}<span className="id">discount_amount</span>
        </pre>
      </Definition>

      <Definition id="tax_amount" title="tax_amount" desc="Sales tax charged on the discounted subtotal." step={step} valueEl={V('tax_amount')}>
        <pre className="op-tree">
{'- '}<span className="op">Multiply</span>{'\n'}
{'  - '}<span className="id">discounted_subtotal</span>{'\n'}
{'  - '}<span className="id">tax_rate</span>
        </pre>
      </Definition>

      <Definition id="total" title="total" desc="Final amount due." step={step} valueEl={V('total')} final>
        <pre className="op-tree">
{'- '}<span className="op">Add</span>{'\n'}
{'  - '}<span className="id">discounted_subtotal</span>{'\n'}
{'  - '}<span className="id">tax_amount</span>
        </pre>
      </Definition>

      <h2>Validations</h2>

      <Definition id="is_valid_quantity" title="is_valid_quantity" desc="Returns true when quantity is at least 1." step={step} valueEl={V('is_valid_quantity')}>
        <pre className="op-tree">
{'- '}<span className="op">Greater Than or Equal</span>{'\n'}
{'  - '}<span className="id">quantity</span>{'\n'}
{'  - '}<span className="lit">1</span>
        </pre>
      </Definition>
    </article>
  );
}

function Definition({ id, title, desc, children, step, valueEl, final }) {
  const active = step === title;
  return (
    <section id={id} className={'def ' + (active?'active ':'') + (final?'final':'')}>
      <div className="def-head">
        <h3><code>{title}</code></h3>
        {valueEl}
      </div>
      <p className="def-desc">{desc}</p>
      {children}
    </section>
  );
}

function formatNum(v) {
  if (v === undefined || v === null) return '—';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') {
    if (Number.isInteger(v)) return v.toString();
    return v.toFixed(v < 1 ? 3 : 2);
  }
  return String(v);
}

window.SpecDocument = SpecDocument;
