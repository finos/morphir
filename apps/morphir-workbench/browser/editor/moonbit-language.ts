import type { StreamParser } from '@codemirror/language';
// Lexical highlighting. The portable MoonBit frontend validates the source profile.
const keywords = new Set('pub priv fn let mut if else match guard return raise try catch type struct enum trait derive import async for while loop break continue as is with impl test extern'.split(' '));
export const moonbit: StreamParser<{ commentDepth: number }> = {
  startState: () => ({ commentDepth: 0 }),
  token(stream, state) {
    if (state.commentDepth) {
      while (!stream.eol()) {
        if (stream.match('/*')) state.commentDepth++;
        else if (stream.match('*/')) { if (--state.commentDepth === 0) break; }
        else stream.next();
      }
      return 'comment';
    }
    if (stream.eatSpace()) return null;
    if (stream.match('//')) { stream.skipToEnd(); return 'comment'; }
    if (stream.match('/*')) { state.commentDepth = 1; return 'comment'; }
    if (stream.match('#|')) { stream.skipToEnd(); return 'string'; }
    if (stream.match(/b?["']/)) {
      const quote = stream.current().at(-1);
      while (!stream.eol()) {
        const character = stream.next();
        if (character === '\\') stream.next();
        else if (character === quote) break;
      }
      return 'string';
    }
    if (stream.match(/(?:0[xX][\da-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d[\d_]*)?)[A-Za-z]*/)) return 'number';
    if (stream.match(/[\p{L}_][\p{L}\p{N}_]*/u)) {
      const word = stream.current();
      if (word === 'true' || word === 'false') return 'bool';
      if (keywords.has(word)) return 'keyword';
      if (/^[A-Z]/.test(word)) return 'type';
      return stream.match(/\s*\(/, false) ? 'variableName.function' : 'variableName';
    }
    stream.next();
    return 'operator';
  },
};
