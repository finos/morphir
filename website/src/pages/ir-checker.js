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
  const { colorMode } = useColorMode();
  const fileInputRef = React.useRef(null);
  const editorRef = React.useRef(null);
  const containerRef = React.useRef(null);

  const { navigateToPath } = useJsonNavigation(editorRef, jsonInput);

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
    const collectPaths = (obj, path) => {
      if (obj && typeof obj === 'object') {
        collapsed[path] = false;
        if (Array.isArray(obj)) {
          obj.forEach((_, i) => collectPaths(obj[i], `${path}/${i}`));
        } else {
          Object.keys(obj).forEach(k => collectPaths(obj[k], `${path}/${k}`));
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

  const styles = createStyles({
    colorMode,
    sidebarWidth,
    xrayWidth,
    isDragging,
    isDraggingXray,
    validationResult,
  });

  if (loadError) {
    return <div className="alert alert--danger margin--lg">{loadError}</div>;
  }

  const errorCount = validationResult?.errors?.length || 0;

  return (
    <div style={styles.container}>
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
        onToggleXRay={() => setShowXRay(!showXRay)}
        styles={styles}
        colorMode={colorMode}
        fileInputRef={fileInputRef}
      />

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
