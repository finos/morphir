/* global React */
const { useState: useStateCli, useEffect: useEffectCli, useRef: useRefCli } = React;

function CliDemo() {
  const lines = [
    { t:'prompt', c:'$ substrate test examples/order-total.md' },
    { t:'ok',     c:'✓ 24/24 tests passed' },
    { t:'dim',    c:'  subtotal, discount_amount, discounted_subtotal,' },
    { t:'dim',    c:'  tax_amount, total, is_valid_quantity,' },
    { t:'dim',    c:'  is_valid_discount, clamped_discount_rate' },
    { t:'gap',    c:'' },
    { t:'prompt', c:'$ substrate eval examples/order-total.md total \\' },
    { t:'prompt', c:'    -i unit_price=10 quantity=3 \\' },
    { t:'prompt', c:'       discount_rate=0.1 tax_rate=0.2' },
    { t:'num',    c:'32.4' },
    { t:'gap',    c:'' },
    { t:'prompt', c:'$ substrate list examples/order-total.md' },
    { t:'hdr',    c:'Order Total' },
    { t:'dim',    c:'  inputs:  unit_price, quantity, discount_rate, tax_rate' },
    { t:'def',    c:'  subtotal              (4 cases)' },
    { t:'def',    c:'  discount_amount       (4 cases)' },
    { t:'def',    c:'  discounted_subtotal   (4 cases)' },
    { t:'def',    c:'  tax_amount            (4 cases)' },
    { t:'def',    c:'  total                 (4 cases)' },
    { t:'def',    c:'  is_valid_quantity     (4 cases)' },
  ];
  const [n, setN] = useStateCli(0);
  const ref = useRefCli();
  useEffectCli(() => {
    if (n >= lines.length) return;
    const delay = lines[n].t === 'gap' ? 180 : lines[n].t === 'prompt' ? 340 : 90;
    const id = setTimeout(() => setN(n+1), delay);
    return () => clearTimeout(id);
  }, [n]);
  useEffectCli(() => {
    if (ref.current) ref.current.scrollTop = ref.current.scrollHeight;
  }, [n]);

  return (
    <div className="cli-window">
      <div className="cli-titlebar">
        <span className="dot" style={{background:'#F26A21'}}/>
        <span className="dot" style={{background:'#16A2DC'}}/>
        <span className="dot" style={{background:'#8BA191'}}/>
        <span className="cli-title">substrate — order-total</span>
      </div>
      <div className="cli-body" ref={ref}>
        {lines.slice(0, n).map((l, i) => (
          <div key={i} className={'cli-line cli-'+l.t}>{l.c || '\u00a0'}</div>
        ))}
        {n < lines.length && <span className="caret">▍</span>}
        {n >= lines.length && (
          <div className="cli-line cli-prompt">$ <span className="caret">▍</span></div>
        )}
      </div>
    </div>
  );
}
window.CliDemo = CliDemo;
