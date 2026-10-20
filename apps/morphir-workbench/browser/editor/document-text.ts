/**
 * The text of the code editor's document, keyed by the host's document key.
 *
 * The host renders a value for each document. A user edit reaches the host as an input event and comes back in a later
 * render. Rabbita sets the value property only when its virtual DOM value changes, so a render can change the key and
 * leave the value as it was. Then the new document's value is the last rendered value, and an edit the host has not
 * rendered yet belongs to the document it was typed in, never to the new one.
 */
export class DocumentText {
  /** The last value the host rendered. */
  rendered = '';
  /** The current document's text: the last rendered value, or a later user edit. */
  current = '';
  /** The current document's key, or `null` before the first document opens. */
  key: string | null = null;
  /** The host rendered `value` for the current document, or for the document that opens next. */
  render(value: string) {
    this.rendered = value;
    this.current = value;
  }
  /** The user changed the current document to `text`. */
  edit(text: string) {
    this.current = text;
  }
  /** Makes `key` the current document and returns its text. A different key starts from the rendered value. */
  open(key: string): string {
    if (key !== this.key) {
      this.key = key;
      this.current = this.rendered;
    }
    return this.current;
  }
}
