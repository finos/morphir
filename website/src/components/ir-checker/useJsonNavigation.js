import { useCallback } from 'react';

/**
 * Hook for navigating to JSON paths in the Monaco editor
 */
export function useJsonNavigation(editorRef, jsonInput) {
  const navigateToPath = useCallback((path) => {
    if (!editorRef.current || !path || path === '/') return;

    const editor = editorRef.current;
    const model = editor.getModel();
    if (!model) return;

    // Parse the path into segments
    const segments = path.split('/').filter(Boolean);
    if (segments.length === 0) return;

    const text = jsonInput;
    let searchPos = 0;

    // Navigate through each segment to find the final position
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      const isArrayIndex = /^\d+$/.test(segment);

      if (isArrayIndex) {
        // For array indices, find the nth element after current position
        const index = parseInt(segment);
        let bracketDepth = 0;
        let elementCount = 0;
        let foundStart = false;

        for (let j = searchPos; j < text.length; j++) {
          const char = text[j];
          if (char === '[' && !foundStart) {
            foundStart = true;
            bracketDepth = 1;
            if (index === 0) {
              // Find the first non-whitespace after [
              for (let k = j + 1; k < text.length; k++) {
                if (!/\s/.test(text[k])) {
                  searchPos = k;
                  break;
                }
              }
              break;
            }
            continue;
          }
          if (!foundStart) continue;

          if (char === '[' || char === '{') bracketDepth++;
          else if (char === ']' || char === '}') bracketDepth--;
          else if (char === ',' && bracketDepth === 1) {
            elementCount++;
            if (elementCount === index) {
              // Find the first non-whitespace after comma
              for (let k = j + 1; k < text.length; k++) {
                if (!/\s/.test(text[k])) {
                  searchPos = k;
                  break;
                }
              }
              break;
            }
          }
        }
      } else {
        // For object keys, search for the key name
        const keyPattern = new RegExp(`"${segment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"\\s*:`);
        const match = text.substring(searchPos).match(keyPattern);
        if (match) {
          searchPos = searchPos + match.index + match[0].length;
          // Skip whitespace to get to the value
          while (searchPos < text.length && /\s/.test(text[searchPos])) {
            searchPos++;
          }
        }
      }
    }

    // Convert position to line/column
    const textBefore = text.substring(0, searchPos);
    const lines = textBefore.split('\n');
    const lineNumber = lines.length;
    const column = lines[lines.length - 1].length + 1;

    // Find the extent of the value at this position
    let endPos = searchPos;
    const startChar = text[searchPos];
    if (startChar === '{' || startChar === '[') {
      // Find matching bracket
      let depth = 1;
      endPos++;
      while (endPos < text.length && depth > 0) {
        const c = text[endPos];
        if (c === '{' || c === '[') depth++;
        else if (c === '}' || c === ']') depth--;
        endPos++;
      }
    } else if (startChar === '"') {
      // Find end of string
      endPos++;
      while (endPos < text.length && text[endPos] !== '"') {
        if (text[endPos] === '\\') endPos++;
        endPos++;
      }
      endPos++;
    } else {
      // Find end of primitive (number, boolean, null)
      while (endPos < text.length && /[^\s,\]\}]/.test(text[endPos])) {
        endPos++;
      }
    }

    const textToEnd = text.substring(0, endPos);
    const endLines = textToEnd.split('\n');
    const endLineNumber = endLines.length;
    const endColumn = endLines[endLines.length - 1].length + 1;

    // Set selection and reveal
    editor.setSelection({
      startLineNumber: lineNumber,
      startColumn: column,
      endLineNumber: endLineNumber,
      endColumn: endColumn,
    });
    editor.revealLineInCenter(lineNumber);
    editor.focus();
  }, [editorRef, jsonInput]);

  return { navigateToPath };
}

export default useJsonNavigation;
