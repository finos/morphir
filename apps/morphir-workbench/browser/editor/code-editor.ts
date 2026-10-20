import { basicSetup } from 'codemirror';
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
const highlighting = HighlightStyle.define([
  { tag: [tags.keyword, tags.controlKeyword, tags.definitionKeyword], color: '#005878', fontWeight: '600' },
  { tag: [tags.name, tags.variableName], color: '#1c1e21' },
  { tag: [tags.function(tags.variableName), tags.standard(tags.name), tags.standard(tags.variableName)], color: '#00729e' },
  { tag: [tags.string, tags.character], color: '#a34400' },
  { tag: [tags.number, tags.bool, tags.atom], color: '#7b3fb0' },
  { tag: tags.comment, color: '#606770', fontStyle: 'italic' },
  { tag: [tags.operator, tags.punctuation], color: '#606770' },
  { tag: tags.propertyName, color: '#005878' },
]);
const theme = EditorView.theme({
  '&': { height: '100%', color: 'var(--ink, #1c1e21)', backgroundColor: '#fff', fontSize: '13px' },
  '&.cm-focused': { outline: '2px solid var(--link, #00729e)', outlineOffset: '-2px' },
  '.cm-scroller': { overflow: 'auto', fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace', lineHeight: '1.85' },
  '.cm-content': { padding: '16px 0' },
  '.cm-line': { padding: '0 16px' },
  '.cm-gutters': { backgroundColor: '#fafbfc', color: '#606770', borderRight: '1px solid #e4e6e8' },
  '.cm-activeLine, .cm-activeLineGutter': { backgroundColor: '#e5f5fc' },
  '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection': { backgroundColor: '#ccecfb' },
  '.cm-cursor': { borderLeftColor: '#00729e' },
  '.cm-morphir-problem': { textDecoration: 'underline wavy #b42318' },
  '.cm-foldPlaceholder': { backgroundColor: '#e5f5fc', borderColor: '#dadde1', color: '#005878' },
});

function languageSupport(id: string) {
  switch (id.toLowerCase()) {
    case 'scheme': case 'scm': return StreamLanguage.define(scheme);
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
