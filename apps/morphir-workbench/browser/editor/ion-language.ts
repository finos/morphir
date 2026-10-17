import type { StreamParser, StringStream } from '@codemirror/language';
interface IonState { quote: string | null; comment: boolean; }
// Lexical highlighting only. The shared Ion parser validates evaluation input.
function quoted(stream: StringStream, state: IonState) {
  while (!stream.eol()) {
    if (stream.match(state.quote!)) { state.quote = null; break; }
    if (stream.next() === '\\') stream.next();
  }
  return 'string';
}

export const ion: StreamParser<IonState> = {
  startState: () => ({ quote: null, comment: false }),
  token(stream, state) {
    if (state.comment) {
      while (!stream.eol()) {
        if (stream.match('*/')) { state.comment = false; break; }
        stream.next();
      }
      return 'comment';
    }
    if (state.quote) return quoted(stream, state);
    if (stream.eatSpace()) return null;
    if (stream.match('//')) { stream.skipToEnd(); return 'comment'; }
    if (stream.match('/*')) { state.comment = true; return 'comment'; }
    for (const quote of ["'''", '"', "'"]) {
      if (stream.match(quote)) { state.quote = quote; return quoted(stream, state); }
    }
    if (stream.match(/[+-]?(?:\d[\w.+:-]*|inf|nan)\b/i)) return 'number';
    if (stream.match(/(?:true|false|null)(?:\.[a-z]+)?\b/)) return 'atom';
    if (stream.match(/[A-Za-z_$][\w$]*/)) return stream.match(/\s*::/, false) ? 'keyword' : 'property';
    stream.next();
    return 'punctuation';
  },
};
