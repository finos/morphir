import { basicSetup } from 'codemirror';
import { toml } from '@codemirror/legacy-modes/mode/toml';
import { Compartment, EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { DocumentText } from './document-text.ts';
import { markSet, position } from './marks.ts';
import { HighlightStyle, StreamLanguage, syntaxHighlighting } from '@codemirror/language';
import { yaml } from '@codemirror/legacy-modes/mode/yaml';
import { scheme } from '@codemirror/legacy-modes/mode/scheme';
import { scala } from '@codemirror/legacy-modes/mode/clike';
import { elm } from '@codemirror/legacy-modes/mode/elm';
import { json } from '@codemirror/lang-json';
import { javascript } from '@codemirror/lang-javascript';
import { java } from '@codemirror/lang-java';
import { python } from '@codemirror/lang-python';
import { tags } from '@lezer/highlight';
import { ion } from './ion-language.ts';
import { moonbit } from './moonbit-language.ts';

// The bounded, in-memory session store retains source history when Rabbita
// removes an experience. Read-only output never occupies a session slot.
const sessions = new Map<string, EditorState>();
// The last reveal request any editor acted on: a remount with the same request does not move the cursor again.
let lastReveal = '';
// Compartments belong to each EditorState; this identity also works on a cached state.
const configuration = new Compartment();
// Colors are appearance tokens from workbench.css; custom properties inherit into the editor's shadow root.
const highlighting = HighlightStyle.define([
  { tag: [tags.keyword, tags.controlKeyword, tags.definitionKeyword], color: 'var(--code-keyword)', fontWeight: '600' },
  { tag: [tags.name, tags.variableName], color: 'var(--ink)' },
  { tag: [tags.function(tags.variableName), tags.standard(tags.name), tags.standard(tags.variableName)], color: 'var(--code-function)' },
  { tag: [tags.string, tags.character], color: 'var(--code-string)' },
  { tag: [tags.number, tags.bool, tags.atom], color: 'var(--code-number)' },
  { tag: tags.comment, color: 'var(--code-comment)', fontStyle: 'italic' },
  { tag: [tags.operator, tags.punctuation], color: 'var(--code-punctuation)' },
  { tag: tags.propertyName, color: 'var(--code-property)' },
]);
const theme = EditorView.theme({
  '&': { height: '100%', color: 'var(--ink)', backgroundColor: 'var(--surface)', fontSize: '13px' },
  '&.cm-focused': { outline: '2px solid var(--focus-ring)', outlineOffset: '-2px' },
  '.cm-scroller': { overflow: 'auto', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace', lineHeight: '1.85' },
  '.cm-content': { padding: 'var(--editor-padding-top, 16px) 0 16px' },
  '.cm-line': { padding: '0 16px' },
  '.cm-gutters': { backgroundColor: 'var(--surface-alt)', color: 'var(--muted)', borderRight: '1px solid var(--line)' },
  '.cm-activeLine, .cm-activeLineGutter': { backgroundColor: 'var(--selection)' },
  '&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, ::selection': { backgroundColor: 'var(--code-selection)' },
  '.cm-cursor': { borderLeftColor: 'var(--link)' },
  '.cm-morphir-problem': { textDecoration: 'underline wavy var(--danger-ink)' },
  '.cm-foldPlaceholder': { backgroundColor: 'var(--selection)', borderColor: 'var(--line-strong)', color: 'var(--link-strong)' },
  // The search panel and completion tooltips replace CodeMirror's light-only defaults.
  '.cm-panels': { backgroundColor: 'var(--paper)', color: 'var(--ink)' },
  '.cm-panels-top': { borderBottom: '1px solid var(--line)' },
  '.cm-panels-bottom': { borderTop: '1px solid var(--line)' },
  '.cm-textfield': { backgroundColor: 'var(--surface)', border: '1px solid var(--line-strong)' },
  '.cm-button': { backgroundImage: 'none', backgroundColor: 'var(--surface)', border: '1px solid var(--line-strong)' },
  '.cm-tooltip': { backgroundColor: 'var(--surface)', color: 'var(--ink)', border: '1px solid var(--line-strong)' },
  '.cm-tooltip-section:not(:first-child)': { borderTop: '1px solid var(--line)' },
});

function languageSupport(id: string) {
  switch (id.toLowerCase()) {
    case 'scheme': case 'scm': return StreamLanguage.define(scheme);
    case 'toml': return StreamLanguage.define(toml);
    case 'scala': return StreamLanguage.define(scala);
    case 'elm': return StreamLanguage.define(elm);
    case 'json': return json();
    case 'yaml': case 'yml': return StreamLanguage.define(yaml);
    case 'ion': return StreamLanguage.define(ion);
    case 'moonbit': case 'mbt': return StreamLanguage.define(moonbit);
    case 'javascript': case 'js': return javascript();
    case 'typescript': case 'ts': return javascript({ typescript: true });
    case 'java': return java();
    case 'python': case 'py': return python();
    default: return [];
  }
}

export class CodeEditor extends HTMLElement {
  declare readonly shadowRoot: ShadowRoot;
  configuration: Compartment;
  text: DocumentText;
  view: EditorView | null;
  readOnly: boolean;
  queued: boolean;
  static observedAttributes = ['data-document', 'data-language', 'data-readonly', 'data-marks', 'data-reveal', 'aria-label'];
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    const style = document.createElement('style');
    style.textContent = ':host{display:block;height:var(--editor-height,440px);min-width:0}';
    this.shadowRoot.append(style);
    // Only the component's normalized input event crosses into Rabbita.
    this.shadowRoot.addEventListener('input', event => event.stopPropagation());
    this.configuration = configuration;
    this.text = new DocumentText();
    this.view = null;
    this.readOnly = true;
    this.queued = false;
  }
  /** The line of the caret, one-based; read by tests. */
  get caretLine() { return this.view ? this.view.state.doc.lineAt(this.view.state.selection.main.head).number : 0; }
  get value() { return this.view?.state.doc.toString() ?? this.text.current; }
  set value(value: string) { this.text.render(String(value ?? '')); this.schedule(); }
  connectedCallback() { this.schedule(); }
  disconnectedCallback() {
    this.remember();
    this.view?.destroy();
    this.view = null;
  }
  attributeChangedCallback() { this.schedule(); }
  schedule() {
    if (this.queued) return;
    this.queued = true;
    queueMicrotask(() => {
      this.queued = false;
      if (this.isConnected) this.reconcile();
    });
  }
  remember() {
    const key = this.text.key;
    if (!this.view || this.readOnly || !key) return;
    sessions.delete(key);
    sessions.set(key, this.view.state);
    if (sessions.size > 20) sessions.delete(sessions.keys().next().value!);
  }
  extensions() {
    const readOnly = this.dataset.readonly === 'true';
    const marks = this.dataset.marks ?? '';
    return [
      EditorView.decorations.of(view => markSet(view.state.doc, marks)),
      languageSupport(this.dataset.language ?? ''),
      EditorState.readOnly.of(readOnly),
      EditorView.editable.of(!readOnly),
      EditorView.contentAttributes.of({ 'aria-label': this.getAttribute('aria-label') ?? 'Code editor', 'aria-readonly': String(readOnly), spellcheck: 'false' }),
    ];
  }
  newState() {
    return EditorState.create({ doc: this.text.current, extensions: [
      basicSetup, theme, syntaxHighlighting(highlighting),
      this.configuration.of(this.extensions()),
      // Synchronize focus before a browser selection replaces the current caret.
      // Otherwise CodeMirror's delayed focus update can restore that old caret
      // between select-all and text insertion, leaving the old document behind.
      EditorView.domEventHandlers({ focus: (_event, view) => { view.dispatch({}); return false; } }),
      EditorView.updateListener.of(update => {
        const component = (update.view.dom.getRootNode() as ShadowRoot).host as CodeEditor;
        if (!update.docChanged || component.readOnly) return;
        component.text.edit(update.state.doc.toString());
        component.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, inputType: 'insertText' }));
      }),
    ] });
  }
  reconcile() {
    const key = this.dataset.document ?? '';
    const readOnly = this.dataset.readonly === 'true';
    if (!this.view || key !== this.text.key || readOnly !== this.readOnly) {
      this.remember();
      // A new key opens at its rendered value; an edit not yet rendered stays in the session of its own document.
      const text = this.text.open(key);
      this.readOnly = readOnly;
      const cached = !readOnly && sessions.get(key);
      const state = cached && cached.doc.toString() === text ? cached : this.newState();
      if (this.view) this.view.setState(state);
      else this.view = new EditorView({ state, parent: this.shadowRoot, root: this.shadowRoot });
    } else if (this.view.state.doc.toString() !== this.text.current) {
      // External replacement (an example or host result) starts a new history.
      this.view.setState(this.newState());
    }
    this.view.dispatch({ effects: this.configuration.reconfigure(this.extensions()) });
    const reveal = this.dataset.reveal ?? '';
    // A reveal waits until the view holds the current document for the current key; it is recorded only once moved.
    if (reveal && reveal !== lastReveal && this.text.key === key && this.view.state.doc.toString() === this.text.current) {
      const [line = NaN, column = NaN, , endLine, endColumn] = reveal.split(':').map(Number);
      if (Number.isFinite(line) && Number.isFinite(column)) {
        const anchor = position(this.view.state.doc, line, column);
        const head = endLine !== undefined && endColumn !== undefined && Number.isFinite(endLine) && Number.isFinite(endColumn)
          ? position(this.view.state.doc, endLine, endColumn) : anchor;
        this.view.dispatch({ selection: { anchor, head }, scrollIntoView: true });
        this.view.focus();
        lastReveal = reveal;
      }
    }
  }
}

customElements.define('morphir-code-editor', CodeEditor);
window.addEventListener('pagehide', () => sessions.clear());
