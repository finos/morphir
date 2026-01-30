import React from 'react';
import Layout from '@theme/Layout';
import Editor from '@monaco-editor/react';
import { useColorMode } from '@docusaurus/theme-common';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';

const schemaVersions = [
  { value: 'v1', label: 'v1', file: 'morphir-ir-v1.json', status: 'Legacy' },
  { value: 'v2', label: 'v2', file: 'morphir-ir-v2.json', status: 'Legacy' },
  { value: 'v3', label: 'v3', file: 'morphir-ir-v3.json', status: 'Stable' },
  { value: 'v4', label: 'v4', file: 'morphir-ir-v4.json', status: 'Draft' },
];

const sampleJson = {
  v4: `{
  "formatVersion": 4,
  "distribution": {
    "Library": {
      "packageName": "my-org/my-package",
      "dependencies": {},
      "def": {
        "modules": {}
      }
    }
  }
}`,
  v3: `{
  "formatVersion": 3,
  "distribution": [
    "Library",
    [[["my"], ["org"]], [["my"], ["package"]]],
    [],
    { "modules": [] }
  ]
}`,
  v2: `{
  "formatVersion": 2,
  "distribution": [
    "Library",
    [[["my"], ["org"]], [["my"], ["package"]]],
    [],
    { "modules": [] }
  ]
}`,
  v1: `{
  "formatVersion": 1,
  "distribution": [
    "library",
    [[["my"], ["org"]], [["my"], ["package"]]],
    [],
    { "modules": [] }
  ]
}`,
};

function IRCheckerContent() {
  const [selectedVersion, setSelectedVersion] = React.useState('v4');
  const [jsonInput, setJsonInput] = React.useState(sampleJson.v4);
  const [validationResult, setValidationResult] = React.useState(null);
  const [schemas, setSchemas] = React.useState({});
  const [loadError, setLoadError] = React.useState(null);
  const [autoValidate, setAutoValidate] = React.useState(true);
  const [sidebarWidth, setSidebarWidth] = React.useState(350);
  const [isDragging, setIsDragging] = React.useState(false);
  const [expandedCards, setExpandedCards] = React.useState({});
  const { colorMode } = useColorMode();
  const fileInputRef = React.useRef(null);
  const editorRef = React.useRef(null);
  const containerRef = React.useRef(null);

  // Load schemas
  React.useEffect(() => {
    const loadSchemas = async () => {
      try {
        const loadedSchemas = {};
        for (const version of schemaVersions) {
          const response = await fetch(`/schemas/${version.file}`);
          if (response.ok) {
            loadedSchemas[version.value] = await response.json();
          }
        }
        setSchemas(loadedSchemas);
      } catch (err) {
        setLoadError(`Failed to load schemas: ${err.message}`);
      }
    };
    loadSchemas();
  }, []);

  // Auto-validate on input change
  React.useEffect(() => {
    if (autoValidate && jsonInput && Object.keys(schemas).length > 0) {
      validateJson();
    }
  }, [jsonInput, selectedVersion, schemas, autoValidate]);

  // Draggable splitter handlers
  const handleMouseDown = React.useCallback((e) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  React.useEffect(() => {
    const handleMouseMove = (e) => {
      if (!isDragging || !containerRef.current) return;

      const containerRect = containerRef.current.getBoundingClientRect();
      const newWidth = containerRect.right - e.clientX;

      // Constrain sidebar width between 200 and 600 pixels
      const constrainedWidth = Math.max(200, Math.min(600, newWidth));
      setSidebarWidth(constrainedWidth);
    };

    const handleMouseUp = () => {
      setIsDragging(false);
    };

    if (isDragging) {
      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
      // Prevent text selection while dragging
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
    }

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
    };
  }, [isDragging]);

  const handleEditorDidMount = (editor, monaco) => {
    editorRef.current = editor;
  };

  const handleFileUpload = (event) => {
    const file = event.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (e) => {
        setJsonInput(e.target.result);
      };
      reader.readAsText(file);
    }
  };

  const validateJson = () => {
    if (!jsonInput.trim()) {
      setValidationResult(null);
      return;
    }

    try {
      let parsedJson;
      try {
        parsedJson = JSON.parse(jsonInput);
      } catch (parseErr) {
        setValidationResult({
          valid: false,
          errors: [{
            type: 'parse',
            message: parseErr.message,
            line: extractLineNumber(parseErr.message),
          }],
          parsedJson: null,
        });
        return;
      }

      const schema = schemas[selectedVersion];
      if (!schema) {
        setValidationResult({
          valid: false,
          errors: [{ type: 'system', message: `Schema for ${selectedVersion} not loaded yet` }],
          parsedJson,
        });
        return;
      }

      const ajv = new Ajv({ allErrors: true, verbose: true, strict: false });
      addFormats(ajv);
      const validate = ajv.compile(schema);
      const valid = validate(parsedJson);

      setValidationResult({
        valid,
        errors: (validate.errors || []).map(err => ({
          type: 'schema',
          path: err.instancePath || '/',
          message: err.message,
          keyword: err.keyword,
          params: err.params,
        })),
        parsedJson,
        schemaVersion: selectedVersion,
      });
    } catch (err) {
      setValidationResult({
        valid: false,
        errors: [{ type: 'system', message: `Validation Error: ${err.message}` }],
        parsedJson: null,
      });
    }
  };

  const extractLineNumber = (message) => {
    const match = message.match(/position (\d+)/);
    if (match) {
      const pos = parseInt(match[1]);
      const lines = jsonInput.substring(0, pos).split('\n');
      return lines.length;
    }
    return null;
  };

  const formatJson = () => {
    try {
      const parsed = JSON.parse(jsonInput);
      setJsonInput(JSON.stringify(parsed, null, 2));
    } catch (e) {
      // Can't format invalid JSON
    }
  };

  // Find position in JSON text for a given JSON path and highlight it
  const navigateToPath = (path) => {
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
  };

  const toggleCard = (cardId) => {
    setExpandedCards(prev => ({
      ...prev,
      [cardId]: !prev[cardId]
    }));
  };

  const isCardExpanded = (cardId) => {
    // Default to expanded for error cards, collapsed for info cards
    if (expandedCards[cardId] === undefined) {
      return cardId.startsWith('error-') || cardId === 'success' || cardId === 'ready';
    }
    return expandedCards[cardId];
  };

  const styles = {
    container: {
      display: 'flex',
      flexDirection: 'column',
      height: 'calc(100vh - 60px)',
      backgroundColor: colorMode === 'dark' ? '#1e1e1e' : '#ffffff',
    },
    toolbar: {
      display: 'flex',
      alignItems: 'center',
      gap: '0.75rem',
      padding: '0.5rem 1rem',
      borderBottom: `1px solid ${colorMode === 'dark' ? '#333' : '#e0e0e0'}`,
      backgroundColor: colorMode === 'dark' ? '#252526' : '#f3f3f3',
      flexWrap: 'wrap',
    },
    toolbarGroup: {
      display: 'flex',
      alignItems: 'center',
      gap: '0.5rem',
    },
    toolbarLabel: {
      fontSize: '0.85rem',
      color: colorMode === 'dark' ? '#ccc' : '#666',
    },
    versionBtn: (isSelected) => ({
      padding: '0.25rem 0.75rem',
      fontSize: '0.85rem',
      border: `1px solid ${isSelected ? '#0078d4' : (colorMode === 'dark' ? '#555' : '#ccc')}`,
      borderRadius: '3px',
      backgroundColor: isSelected ? '#0078d4' : 'transparent',
      color: isSelected ? '#fff' : (colorMode === 'dark' ? '#ccc' : '#333'),
      cursor: 'pointer',
    }),
    toolbarBtn: {
      padding: '0.25rem 0.75rem',
      fontSize: '0.85rem',
      border: `1px solid ${colorMode === 'dark' ? '#555' : '#ccc'}`,
      borderRadius: '3px',
      backgroundColor: 'transparent',
      color: colorMode === 'dark' ? '#ccc' : '#333',
      cursor: 'pointer',
    },
    mainContent: {
      display: 'flex',
      flex: 1,
      overflow: 'hidden',
    },
    editorPane: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      minWidth: 0, // Allow flex shrinking
    },
    splitter: {
      width: '4px',
      cursor: 'col-resize',
      backgroundColor: isDragging
        ? '#0078d4'
        : (colorMode === 'dark' ? '#333' : '#e0e0e0'),
      transition: isDragging ? 'none' : 'background-color 0.2s',
      flexShrink: 0,
      position: 'relative',
    },
    splitterHover: {
      position: 'absolute',
      top: 0,
      bottom: 0,
      left: '-4px',
      right: '-4px',
      zIndex: 10,
    },
    editorHeader: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0.5rem 1rem',
      backgroundColor: colorMode === 'dark' ? '#2d2d2d' : '#f8f8f8',
      borderBottom: `1px solid ${colorMode === 'dark' ? '#333' : '#e0e0e0'}`,
      fontSize: '0.85rem',
      color: colorMode === 'dark' ? '#ccc' : '#666',
    },
    sidebar: {
      width: `${sidebarWidth}px`,
      display: 'flex',
      flexDirection: 'column',
      backgroundColor: colorMode === 'dark' ? '#252526' : '#f8f8f8',
      flexShrink: 0,
    },
    sidebarHeader: {
      padding: '0.75rem 1rem',
      borderBottom: `1px solid ${colorMode === 'dark' ? '#333' : '#e0e0e0'}`,
      fontWeight: 'bold',
      fontSize: '0.9rem',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
    },
    sidebarContent: {
      flex: 1,
      overflow: 'auto',
      padding: '0.5rem',
    },
    card: (type) => ({
      backgroundColor: colorMode === 'dark' ? '#2d2d2d' : '#fff',
      border: `1px solid ${type === 'error' ? '#f44336' : type === 'success' ? '#4caf50' : (colorMode === 'dark' ? '#444' : '#ddd')}`,
      borderLeft: `3px solid ${type === 'error' ? '#f44336' : type === 'success' ? '#4caf50' : '#2196f3'}`,
      borderRadius: '4px',
      marginBottom: '0.5rem',
      overflow: 'hidden',
    }),
    cardHeader: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0.5rem 0.75rem',
      backgroundColor: colorMode === 'dark' ? '#333' : '#f5f5f5',
      borderBottom: `1px solid ${colorMode === 'dark' ? '#444' : '#eee'}`,
      cursor: 'pointer',
      userSelect: 'none',
    },
    cardTitle: {
      fontSize: '0.8rem',
      fontWeight: 'bold',
      display: 'flex',
      alignItems: 'center',
      gap: '0.5rem',
    },
    cardToggle: {
      fontSize: '0.7rem',
      color: colorMode === 'dark' ? '#888' : '#666',
      marginRight: '0.5rem',
      transition: 'transform 0.2s',
    },
    cardMeta: {
      fontSize: '0.75rem',
      color: colorMode === 'dark' ? '#888' : '#999',
    },
    pathLink: {
      fontSize: '0.75rem',
      color: '#0078d4',
      cursor: 'pointer',
      fontFamily: 'monospace',
      backgroundColor: colorMode === 'dark' ? '#1e1e1e' : '#f0f0f0',
      padding: '0.1rem 0.4rem',
      borderRadius: '3px',
      display: 'inline-block',
      marginTop: '0.25rem',
    },
    cardBody: {
      padding: '0.75rem',
      fontSize: '0.85rem',
      fontFamily: 'monospace',
    },
    badge: (color) => ({
      display: 'inline-block',
      padding: '0.15rem 0.5rem',
      borderRadius: '10px',
      fontSize: '0.7rem',
      fontWeight: 'bold',
      backgroundColor: color,
      color: '#fff',
    }),
    statusBar: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0.25rem 1rem',
      backgroundColor: validationResult?.valid ? '#4caf50' : (validationResult ? '#f44336' : '#0078d4'),
      color: '#fff',
      fontSize: '0.8rem',
    },
  };

  if (loadError) {
    return <div className="alert alert--danger margin--lg">{loadError}</div>;
  }

  const errorCount = validationResult?.errors?.length || 0;

  return (
    <div style={styles.container}>
      {/* Toolbar */}
      <div style={styles.toolbar}>
        <div style={styles.toolbarGroup}>
          <span style={styles.toolbarLabel}>Schema:</span>
          {schemaVersions.map((v) => (
            <button
              key={v.value}
              onClick={() => setSelectedVersion(v.value)}
              style={styles.versionBtn(selectedVersion === v.value)}
              title={v.status}
            >
              {v.label}
            </button>
          ))}
        </div>

        <div style={{ borderLeft: `1px solid ${colorMode === 'dark' ? '#555' : '#ccc'}`, height: '20px' }} />

        <div style={styles.toolbarGroup}>
          <input
            type="file"
            ref={fileInputRef}
            onChange={handleFileUpload}
            accept=".json"
            style={{ display: 'none' }}
          />
          <button onClick={() => fileInputRef.current?.click()} style={styles.toolbarBtn}>
            Open File
          </button>
          <button onClick={() => setJsonInput(sampleJson[selectedVersion])} style={styles.toolbarBtn}>
            Load Sample
          </button>
          <button onClick={formatJson} style={styles.toolbarBtn}>
            Format
          </button>
        </div>

        <div style={{ borderLeft: `1px solid ${colorMode === 'dark' ? '#555' : '#ccc'}`, height: '20px' }} />

        <div style={styles.toolbarGroup}>
          <label style={{ ...styles.toolbarLabel, display: 'flex', alignItems: 'center', gap: '0.25rem', cursor: 'pointer' }}>
            <input
              type="checkbox"
              checked={autoValidate}
              onChange={(e) => setAutoValidate(e.target.checked)}
            />
            Auto-validate
          </label>
          {!autoValidate && (
            <button onClick={validateJson} style={{ ...styles.toolbarBtn, backgroundColor: '#0078d4', color: '#fff', border: 'none' }}>
              Validate
            </button>
          )}
        </div>
      </div>

      {/* Main Content */}
      <div style={styles.mainContent} ref={containerRef}>
        {/* Editor Pane */}
        <div style={styles.editorPane}>
          <div style={styles.editorHeader}>
            <span>morphir-ir.json</span>
            <span>{jsonInput.split('\n').length} lines</span>
          </div>
          <Editor
            height="100%"
            language="json"
            value={jsonInput}
            onChange={(value) => setJsonInput(value || '')}
            onMount={handleEditorDidMount}
            theme={colorMode === 'dark' ? 'vs-dark' : 'light'}
            options={{
              minimap: { enabled: true },
              lineNumbers: 'on',
              scrollBeyondLastLine: false,
              wordWrap: 'on',
              automaticLayout: true,
              fontSize: 14,
              folding: true,
              formatOnPaste: true,
              tabSize: 2,
              renderLineHighlight: 'all',
              bracketPairColorization: { enabled: true },
            }}
          />
        </div>

        {/* Draggable Splitter */}
        <div
          style={styles.splitter}
          onMouseDown={handleMouseDown}
        >
          <div style={styles.splitterHover} />
        </div>

        {/* Sidebar */}
        <div style={styles.sidebar}>
          <div style={styles.sidebarHeader}>
            <span>Validation Results</span>
            <span style={styles.badge(validationResult?.valid ? '#4caf50' : (errorCount > 0 ? '#f44336' : '#2196f3'))}>
              {validationResult?.valid ? 'VALID' : (errorCount > 0 ? `${errorCount} ISSUES` : 'READY')}
            </span>
          </div>

          <div style={styles.sidebarContent}>
            {!validationResult && (
              <div style={styles.card('info')}>
                <div style={styles.cardHeader} onClick={() => toggleCard('ready')}>
                  <span style={styles.cardTitle}>
                    <span style={{ ...styles.cardToggle, transform: isCardExpanded('ready') ? 'rotate(90deg)' : 'rotate(0deg)' }}>▶</span>
                    <span>ℹ️</span> Ready to Validate
                  </span>
                </div>
                {isCardExpanded('ready') && (
                  <div style={styles.cardBody}>
                    Enter or paste Morphir IR JSON in the editor. Validation runs automatically.
                  </div>
                )}
              </div>
            )}

            {validationResult?.valid && (
              <div style={styles.card('success')}>
                <div style={styles.cardHeader} onClick={() => toggleCard('success')}>
                  <span style={styles.cardTitle}>
                    <span style={{ ...styles.cardToggle, transform: isCardExpanded('success') ? 'rotate(90deg)' : 'rotate(0deg)' }}>▶</span>
                    <span>✅</span> Validation Passed
                  </span>
                  <span style={styles.cardMeta}>Schema {selectedVersion}</span>
                </div>
                {isCardExpanded('success') && (
                  <div style={styles.cardBody}>
                    Your JSON conforms to the Morphir IR {selectedVersion} schema.
                  </div>
                )}
              </div>
            )}

            {validationResult?.errors?.map((err, i) => (
              <div key={i} style={styles.card('error')}>
                <div style={styles.cardHeader} onClick={() => toggleCard(`error-${i}`)}>
                  <span style={styles.cardTitle}>
                    <span style={{ ...styles.cardToggle, transform: isCardExpanded(`error-${i}`) ? 'rotate(90deg)' : 'rotate(0deg)' }}>▶</span>
                    <span>❌</span>
                    {err.type === 'parse' ? 'Parse Error' :
                     err.type === 'schema' ? `Schema Error` : 'Error'}
                  </span>
                  <span style={styles.cardMeta}>
                    {err.line && `Line ${err.line}`}
                  </span>
                </div>
                {isCardExpanded(`error-${i}`) && (
                  <div style={styles.cardBody}>
                    {err.message}
                    {err.path && err.path !== '/' && (
                      <div style={{ marginTop: '0.5rem' }}>
                        <span
                          style={styles.pathLink}
                          onClick={(e) => { e.stopPropagation(); navigateToPath(err.path); }}
                          title="Click to highlight in editor"
                        >
                          {err.path}
                        </span>
                      </div>
                    )}
                    {err.keyword && (
                      <div style={{ marginTop: '0.5rem', fontSize: '0.75rem', color: colorMode === 'dark' ? '#888' : '#666' }}>
                        Rule: {err.keyword}
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}

            {/* Schema Info Card */}
            <div style={{ ...styles.card('info'), marginTop: '1rem' }}>
              <div style={styles.cardHeader} onClick={() => toggleCard('schema-info')}>
                <span style={styles.cardTitle}>
                  <span style={{ ...styles.cardToggle, transform: isCardExpanded('schema-info') ? 'rotate(90deg)' : 'rotate(0deg)' }}>▶</span>
                  <span>📋</span> Schema Info
                </span>
              </div>
              {isCardExpanded('schema-info') && (
                <div style={styles.cardBody}>
                  <div style={{ marginBottom: '0.5rem' }}>
                    <strong>Selected:</strong> Version {selectedVersion} ({schemaVersions.find(v => v.value === selectedVersion)?.status})
                  </div>
                  <div style={{ fontSize: '0.8rem' }}>
                    <a href={`/schemas/morphir-ir-${selectedVersion}.json`} target="_blank" rel="noopener">Download JSON</a>
                    {' | '}
                    <a href={`/schemas/morphir-ir-${selectedVersion}.yaml`} target="_blank" rel="noopener">Download YAML</a>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Status Bar */}
      <div style={styles.statusBar}>
        <span>
          {validationResult?.valid ? '✓ Valid' :
           errorCount > 0 ? `✗ ${errorCount} issue${errorCount > 1 ? 's' : ''} found` :
           'Ready'}
        </span>
        <span>Morphir IR Checker • {selectedVersion.toUpperCase()}</span>
      </div>
    </div>
  );
}

function IRChecker() {
  return (
    <Layout title="IR Checker" description="Validate Morphir IR JSON against official schemas" noFooter>
      <IRCheckerContent />
    </Layout>
  );
}

export default IRChecker;
