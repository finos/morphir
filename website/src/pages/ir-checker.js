import React from 'react';
import Layout from '@theme/Layout';
import Editor from '@monaco-editor/react';
import { useColorMode } from '@docusaurus/theme-common';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';

import {
  XRayPanel,
  ValidationSidebar,
  IRCheckerToolbar,
  createStyles,
  useJsonNavigation,
  schemaVersions,
  sampleJson,
} from '../components/ir-checker';

// Thresholds for large file handling
const LARGE_FILE_BYTES = 500 * 1024; // 500KB
const LARGE_FILE_LINES = 10000;
const VALIDATION_DEBOUNCE_MS = 300;

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
  const [showXRay, setShowXRay] = React.useState(false);
  const [xrayWidth, setXrayWidth] = React.useState(400);
  const [isDraggingXray, setIsDraggingXray] = React.useState(false);
  const [xrayExpandedNodes, setXrayExpandedNodes] = React.useState({});
  const [isValidating, setIsValidating] = React.useState(false);
  const [largeFileWarning, setLargeFileWarning] = React.useState(null);
  const { colorMode } = useColorMode();
  const fileInputRef = React.useRef(null);
  const editorRef = React.useRef(null);
  const containerRef = React.useRef(null);
  const validationTimeoutRef = React.useRef(null);

  const { navigateToPath } = useJsonNavigation(editorRef, jsonInput);

  // Check if current input is a large file
  const isLargeFile = React.useMemo(() => {
    const bytes = new Blob([jsonInput]).size;
    const lines = jsonInput.split('\n').length;
    return bytes > LARGE_FILE_BYTES || lines > LARGE_FILE_LINES;
  }, [jsonInput]);

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

  // Debounced auto-validate on input change
  React.useEffect(() => {
    if (validationTimeoutRef.current) {
      clearTimeout(validationTimeoutRef.current);
    }

    if (autoValidate && jsonInput && Object.keys(schemas).length > 0) {
      // Use longer debounce for large files
      const debounceMs = isLargeFile ? VALIDATION_DEBOUNCE_MS * 2 : VALIDATION_DEBOUNCE_MS;
      validationTimeoutRef.current = setTimeout(() => {
        validateJson();
      }, debounceMs);
    }

    return () => {
      if (validationTimeoutRef.current) {
        clearTimeout(validationTimeoutRef.current);
      }
    };
  }, [jsonInput, selectedVersion, schemas, autoValidate, isLargeFile]);

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

      const constrainedWidth = Math.max(200, Math.min(600, newWidth));
      setSidebarWidth(constrainedWidth);
    };

    const handleMouseUp = () => {
      setIsDragging(false);
    };

    if (isDragging) {
      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
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

  // XRay splitter handlers
  const handleXrayMouseDown = React.useCallback((e) => {
    e.preventDefault();
    setIsDraggingXray(true);
  }, []);

  React.useEffect(() => {
    const handleMouseMove = (e) => {
      if (!isDraggingXray || !containerRef.current) return;

      const containerRect = containerRef.current.getBoundingClientRect();
      const newWidth = containerRect.right - e.clientX - sidebarWidth - 12;

      const constrainedWidth = Math.max(200, Math.min(600, newWidth));
      setXrayWidth(constrainedWidth);
    };

    const handleMouseUp = () => {
      setIsDraggingXray(false);
    };

    if (isDraggingXray) {
      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
    }

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
    };
  }, [isDraggingXray, sidebarWidth]);

  const toggleXrayNode = (nodeId) => {
    setXrayExpandedNodes(prev => ({
      ...prev,
      [nodeId]: prev[nodeId] === undefined ? false : !prev[nodeId]
    }));
  };

  const expandAllXrayNodes = () => setXrayExpandedNodes({});

  const collapseAllXrayNodes = () => {
    if (!validationResult?.parsedJson) return;
    const collapsed = {};
    const collectPaths = (obj, path, depth = 0) => {
      // Limit depth for large files to prevent stack overflow
      if (depth > 50) return;
      if (obj && typeof obj === 'object') {
        collapsed[path] = false;
        if (Array.isArray(obj)) {
          obj.forEach((_, i) => collectPaths(obj[i], `${path}/${i}`, depth + 1));
        } else {
          Object.keys(obj).forEach(k => collectPaths(obj[k], `${path}/${k}`, depth + 1));
        }
      }
    };
    collectPaths(validationResult.parsedJson, 'root');
    setXrayExpandedNodes(collapsed);
  };

  const handleEditorDidMount = (editor, monaco) => {
    editorRef.current = editor;
  };

  const handleFileUpload = (event) => {
    const file = event.target.files[0];
    if (file) {
      // Check file size before reading
      if (file.size > 10 * 1024 * 1024) { // 10MB limit
        setLargeFileWarning('File is very large (>10MB). This may cause performance issues.');
      } else if (file.size > LARGE_FILE_BYTES) {
        setLargeFileWarning('Large file detected. Some features may be disabled for performance.');
      } else {
        setLargeFileWarning(null);
      }

      const reader = new FileReader();
      reader.onload = (e) => {
        // Clear XRay for large files to prevent crash
        if (file.size > LARGE_FILE_BYTES) {
          setShowXRay(false);
          setXrayExpandedNodes({});
        }
        setJsonInput(e.target.result);
      };
      reader.onerror = () => {
        setLoadError('Failed to read file');
      };
      reader.readAsText(file);
    }
    // Reset file input to allow re-selecting the same file
    event.target.value = '';
  };

  const validateJson = React.useCallback(() => {
    if (!jsonInput.trim()) {
      setValidationResult(null);
      return;
    }

    setIsValidating(true);

    // Use requestAnimationFrame to prevent UI blocking
    requestAnimationFrame(() => {
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
          setIsValidating(false);
          return;
        }

        const schema = schemas[selectedVersion];
        if (!schema) {
          setValidationResult({
            valid: false,
            errors: [{ type: 'system', message: `Schema for ${selectedVersion} not loaded yet` }],
            parsedJson,
          });
          setIsValidating(false);
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
      setIsValidating(false);
    });
  }, [jsonInput, schemas, selectedVersion]);

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

  const toggleCard = (cardId) => {
    setExpandedCards(prev => ({
      ...prev,
      [cardId]: !prev[cardId]
    }));
  };

  const expandAllCards = () => {
    const allCardIds = ['ready', 'success', 'schema-info'];
    if (validationResult?.errors) {
      validationResult.errors.forEach((_, i) => allCardIds.push(`error-${i}`));
    }
    const expanded = {};
    allCardIds.forEach(id => expanded[id] = true);
    setExpandedCards(expanded);
  };

  const collapseAllCards = () => {
    const allCardIds = ['ready', 'success', 'schema-info'];
    if (validationResult?.errors) {
      validationResult.errors.forEach((_, i) => allCardIds.push(`error-${i}`));
    }
    const collapsed = {};
    allCardIds.forEach(id => collapsed[id] = false);
    setExpandedCards(collapsed);
  };

  const handleToggleXRay = () => {
    if (!showXRay && isLargeFile) {
      // Warn user before enabling XRay for large files
      if (!window.confirm('XRay view may be slow for large files. Continue?')) {
        return;
      }
      // Collapse all nodes by default for large files
      collapseAllXrayNodes();
    }
    setShowXRay(!showXRay);
  };

  const styles = createStyles({
    colorMode,
    sidebarWidth,
    xrayWidth,
    isDragging,
    isDraggingXray,
    validationResult,
  });

  // Monaco editor options - optimized for large files
  const editorOptions = React.useMemo(() => {
    const baseOptions = {
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
    };

    if (isLargeFile) {
      // Performance optimizations for large files
      return {
        ...baseOptions,
        minimap: { enabled: false },
        renderLineHighlight: 'none',
        folding: false,
        wordWrap: 'off',
        bracketPairColorization: { enabled: false },
        matchBrackets: 'never',
        occurrencesHighlight: false,
        selectionHighlight: false,
        renderWhitespace: 'none',
        guides: { indentation: false },
        colorDecorators: false,
        links: false,
        quickSuggestions: false,
        suggestOnTriggerCharacters: false,
        acceptSuggestionOnEnter: 'off',
        tabCompletion: 'off',
        parameterHints: { enabled: false },
        hover: { enabled: false },
      };
    }

    return {
      ...baseOptions,
      minimap: { enabled: true },
    };
  }, [isLargeFile]);

  if (loadError) {
    return <div className="alert alert--danger margin--lg">{loadError}</div>;
  }

  const errorCount = validationResult?.errors?.length || 0;

  return (
    <div style={styles.container}>
      {/* Large file warning banner */}
      {(largeFileWarning || isLargeFile) && (
        <div style={{
          padding: '0.5rem 1rem',
          backgroundColor: colorMode === 'dark' ? '#4a3000' : '#fff3cd',
          color: colorMode === 'dark' ? '#ffc107' : '#856404',
          fontSize: '0.85rem',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          borderBottom: `1px solid ${colorMode === 'dark' ? '#665200' : '#ffeeba'}`,
        }}>
          <span>
            ⚠️ {largeFileWarning || 'Large file mode: Some features disabled for performance.'}
          </span>
          <button
            onClick={() => setLargeFileWarning(null)}
            style={{
              background: 'none',
              border: 'none',
              color: 'inherit',
              cursor: 'pointer',
              padding: '0 0.5rem',
            }}
          >
            ✕
          </button>
        </div>
      )}

      {/* Toolbar */}
      <IRCheckerToolbar
        selectedVersion={selectedVersion}
        onVersionChange={setSelectedVersion}
        onFileUpload={handleFileUpload}
        onLoadSample={setJsonInput}
        onFormat={formatJson}
        autoValidate={autoValidate}
        onAutoValidateChange={setAutoValidate}
        onValidate={validateJson}
        showXRay={showXRay}
        onToggleXRay={handleToggleXRay}
        styles={styles}
        colorMode={colorMode}
        fileInputRef={fileInputRef}
      />

      {/* Main Content */}
      <div style={styles.mainContent} ref={containerRef}>
        {/* Editor Pane */}
        <div style={styles.editorPane}>
          <div style={styles.editorHeader}>
            <span>morphir-ir.json {isLargeFile && '(large file)'}</span>
            <span>
              {jsonInput.split('\n').length} lines
              {isValidating && ' • Validating...'}
            </span>
          </div>
          <Editor
            height="100%"
            language="json"
            value={jsonInput}
            onChange={(value) => setJsonInput(value || '')}
            onMount={handleEditorDidMount}
            theme={colorMode === 'dark' ? 'vs-dark' : 'light'}
            options={editorOptions}
            loading={<div style={{ padding: '1rem' }}>Loading editor...</div>}
          />
        </div>

        {/* XRay Panel - between editor and validation results */}
        {showXRay && (
          <>
            <div
              style={styles.xraySplitter}
              onMouseDown={handleXrayMouseDown}
            />
            <XRayPanel
              colorMode={colorMode}
              parsedJson={validationResult?.parsedJson}
              jsonInput={jsonInput}
              expandedNodes={xrayExpandedNodes}
              toggleNode={toggleXrayNode}
              onSelectNode={navigateToPath}
              onExpandAll={expandAllXrayNodes}
              onCollapseAll={collapseAllXrayNodes}
              onClose={() => setShowXRay(false)}
              styles={styles}
              isLargeFile={isLargeFile}
            />
          </>
        )}

        {/* Draggable Splitter for Validation Results */}
        <div
          style={styles.splitter}
          onMouseDown={handleMouseDown}
        />

        {/* Validation Sidebar */}
        <ValidationSidebar
          validationResult={validationResult}
          selectedVersion={selectedVersion}
          expandedCards={expandedCards}
          onToggleCard={toggleCard}
          onExpandAll={expandAllCards}
          onCollapseAll={collapseAllCards}
          onNavigateToPath={navigateToPath}
          styles={styles}
          colorMode={colorMode}
        />
      </div>

      {/* Status Bar */}
      <div style={styles.statusBar}>
        <span>
          {isValidating ? '⏳ Validating...' :
           validationResult?.valid ? '✓ Valid' :
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
