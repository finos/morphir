import React from 'react';
import Layout from '@theme/Layout';
import Editor from '@monaco-editor/react';
import { useColorMode } from '@docusaurus/theme-common';
import { Effect } from 'effect';
import { useHistory, useLocation } from '@docusaurus/router';
import useBaseUrl from '@docusaurus/useBaseUrl';

import {
  XRayPanel,
  ValidationSidebar,
  IRCheckerToolbar,
  createStyles,
  useJsonNavigation,
  schemaVersions,
  sampleJson,
} from '../components/ir-checker';
import type { ValidationResult, SchemasMap, SchemaVersionValue, ValidationMode } from '../components/ir-checker';
import { runValidationEffect } from '../lib/validationEffect';

const LARGE_FILE_BYTES = 500 * 1024; // 500KB
const LARGE_FILE_LINES = 10000;
const VALIDATION_DEBOUNCE_MS = 300;

function IRCheckerContent(): React.ReactElement {
  const location = useLocation();
  const history = useHistory();
  const baseUrl = useBaseUrl('/ir-checker');
  const staticWorkerUrl = useBaseUrl('validation-inline.worker.js');

  const pathParts = location.pathname.split('/').filter(Boolean);
  const urlVersion = pathParts[pathParts.indexOf('ir-checker') + 1] as string | undefined;
  const initialVersion: SchemaVersionValue = schemaVersions.some(v => v.value === urlVersion) ? (urlVersion as SchemaVersionValue) : 'v4';

  const [selectedVersion, setSelectedVersion] = React.useState<SchemaVersionValue>(initialVersion);
  const schemaFileForVersion = schemaVersions.find((v) => v.value === selectedVersion)?.file ?? 'morphir-ir-v4.json';
  const schemaPath = useBaseUrl('schemas/' + schemaFileForVersion);
  const schemaUrl =
    typeof window !== 'undefined' && schemaPath
      ? window.location.origin + (schemaPath.startsWith('/') ? schemaPath : '/' + schemaPath)
      : undefined;
  const [jsonInput, setJsonInput] = React.useState<string>(sampleJson[initialVersion] ?? sampleJson.v4);
  const [validationResult, setValidationResult] = React.useState<ValidationResult | null>(null);
  const [schemas, setSchemas] = React.useState<SchemasMap>({});
  const [loadError, setLoadError] = React.useState<string | null>(null);
  const [autoValidate, setAutoValidate] = React.useState(true);
  const [sidebarWidth, setSidebarWidth] = React.useState(350);
  const [isDragging, setIsDragging] = React.useState(false);
  const [expandedCards, setExpandedCards] = React.useState<Record<string, boolean>>({});
  const [showXRay, setShowXRay] = React.useState(false);
  const [xrayWidth, setXrayWidth] = React.useState(400);
  const [isDraggingXray, setIsDraggingXray] = React.useState(false);
  const [xrayExpandedNodes, setXrayExpandedNodes] = React.useState<Record<string, boolean>>({});
  const [isValidating, setIsValidating] = React.useState(false);
  const [largeFileWarning, setLargeFileWarning] = React.useState<string | null>(null);
  const [isLoadingContent, setIsLoadingContent] = React.useState(false);
  const [loadedExampleName, setLoadedExampleName] = React.useState<string | null>(null);
  const [validationMode, setValidationMode] = React.useState<ValidationMode>('fast');
  const { colorMode } = useColorMode() as { colorMode: 'dark' | 'light' };
  const fileInputRef = React.useRef<HTMLInputElement>(null);
  const editorRef = React.useRef<unknown>(null);
  const containerRef = React.useRef<HTMLDivElement>(null);
  const validationTimeoutRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const validationIdRef = React.useRef(0);
  const workerRef = React.useRef<Worker | null>(null);
  const workerSupportedRef = React.useRef<boolean | null>(null);

  const { navigateToPath } = useJsonNavigation(editorRef as React.RefObject<unknown>, jsonInput);

  const isLargeFile = React.useMemo(() => {
    const bytes = new Blob([jsonInput]).size;
    const lines = jsonInput.split('\n').length;
    return bytes > LARGE_FILE_BYTES || lines > LARGE_FILE_LINES;
  }, [jsonInput]);

  React.useEffect(() => {
    const loadSchemas = async (): Promise<void> => {
      try {
        const loadedSchemas: SchemasMap = {};
        for (const version of schemaVersions) {
          const response = await fetch(`/schemas/${version.file}`);
          if (response.ok) {
            loadedSchemas[version.value] = (await response.json()) as object;
          }
        }
        setSchemas(loadedSchemas);
      } catch (err) {
        setLoadError(`Failed to load schemas: ${err instanceof Error ? err.message : String(err)}`);
      }
    };
    loadSchemas();
  }, []);

  const handleVersionChange = (newVersion: SchemaVersionValue): void => {
    setSelectedVersion(newVersion);
    history.push(`${baseUrl}/${newVersion}`);
  };

  React.useEffect(() => {
    const pathParts = location.pathname.split('/').filter(Boolean);
    const currentVersion = pathParts[pathParts.indexOf('ir-checker') + 1];

    if (currentVersion) {
      if (schemaVersions.some(v => v.value === currentVersion)) {
        if (currentVersion !== selectedVersion) {
          setSelectedVersion(currentVersion as SchemaVersionValue);
        }
      } else {
        history.replace(`${baseUrl}/v4`);
      }
    } else {
      history.replace(`${baseUrl}/v4`);
    }
  }, [location.pathname, baseUrl, history, selectedVersion]);

  const getValidationWorker = React.useCallback((): Worker | null => {
    if (workerSupportedRef.current === false) return null;
    if (workerRef.current) return workerRef.current;
    try {
      if (typeof Worker === 'undefined') return null;
      // Always use the bundled static worker (Ajv is included via esbuild bundle).
      // The webpack worker approach has issues with ES module syntax in classic workers.
      // Run `npm run build:worker` in website/ to rebuild if needed.
      try {
        // Construct absolute URL for the worker
        const workerAbsoluteUrl = new URL(staticWorkerUrl, window.location.origin).href;
        workerRef.current = new Worker(workerAbsoluteUrl);
        workerSupportedRef.current = true;
        return workerRef.current;
      } catch (err) {
        // Static worker failed to load; fall through to main-thread validation
        console.warn('[IR Checker] Static worker failed to load:', err);
        workerSupportedRef.current = false;
        return null;
      }
    } catch {
      workerSupportedRef.current = false;
      return null;
    }
  }, [staticWorkerUrl]);

  // Eagerly create worker on mount so it's ready when user clicks Validate
  React.useEffect(() => {
    getValidationWorker();
  }, [getValidationWorker]);

  const validateJson = React.useCallback(() => {
    if (!jsonInput.trim()) {
      setValidationResult(null);
      return;
    }

    const runId = ++validationIdRef.current;
    setIsValidating(true);

    const schema = schemas[selectedVersion];
    if (!schema) {
      setValidationResult({
        valid: false,
        errors: [{ type: 'system', message: `Schema for ${selectedVersion} not loaded yet` }],
        parsedJson: null,
      });
      setIsValidating(false);
      return;
    }

    const worker = getValidationWorker();
    const program = runValidationEffect(
      worker,
      jsonInput,
      schema,
      selectedVersion,
      runId,
      validationMode,
      schemaUrl
    );

    // Double defer (rAF + setTimeout twice) so the UI can paint "Validating..." before validation runs on the main thread.
    const run = (): void => {
      Effect.runPromise(program)
        .then((result) => {
          if (runId !== validationIdRef.current) return;
          const apply = (): void => {
            setValidationResult(result);
            setIsValidating(false);
          };
          if (typeof requestIdleCallback !== 'undefined') {
            requestIdleCallback(apply, { timeout: 50 });
          } else {
            setTimeout(apply, 0);
          }
        })
        .catch((err) => {
          if (runId !== validationIdRef.current) return;
          setValidationResult({
            valid: false,
            errors: [
              {
                type: 'system',
                message: err instanceof Error ? err.message : 'Validation failed unexpectedly.',
              },
            ],
            parsedJson: null,
          });
          setIsValidating(false);
        });
    };
    const scheduleRun = (): void => {
      if (typeof requestAnimationFrame !== 'undefined') {
        requestAnimationFrame(() => setTimeout(run, 0));
      } else {
        setTimeout(run, 0);
      }
    };
    if (typeof requestAnimationFrame !== 'undefined') {
      requestAnimationFrame(() => setTimeout(scheduleRun, 0));
    } else {
      setTimeout(run, 0);
    }
  }, [jsonInput, schemas, selectedVersion, getValidationWorker, validationMode, schemaUrl]);

  React.useEffect(() => {
    if (validationTimeoutRef.current) {
      clearTimeout(validationTimeoutRef.current);
    }

    if (isLoadingContent) {
      return;
    }

    if (autoValidate && jsonInput && Object.keys(schemas).length > 0) {
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
  }, [jsonInput, selectedVersion, schemas, autoValidate, isLargeFile, isLoadingContent, validateJson]);

  const handleMouseDown = React.useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  React.useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!isDragging || !containerRef.current) return;
      const containerRect = containerRef.current.getBoundingClientRect();
      const newWidth = containerRect.right - e.clientX;
      const constrainedWidth = Math.max(200, Math.min(600, newWidth));
      setSidebarWidth(constrainedWidth);
    };

    const handleMouseUp = () => setIsDragging(false);

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

  const handleXrayMouseDown = React.useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    setIsDraggingXray(true);
  }, []);

  React.useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!isDraggingXray || !containerRef.current) return;
      const containerRect = containerRef.current.getBoundingClientRect();
      const newWidth = containerRect.right - e.clientX - sidebarWidth - 12;
      const constrainedWidth = Math.max(200, Math.min(600, newWidth));
      setXrayWidth(constrainedWidth);
    };

    const handleMouseUp = () => setIsDraggingXray(false);

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

  const toggleXrayNode = (nodeId: string): void => {
    setXrayExpandedNodes(prev => ({
      ...prev,
      [nodeId]: prev[nodeId] === undefined ? false : !prev[nodeId]
    }));
  };

  const expandAllXrayNodes = (): void => setXrayExpandedNodes({});

  const collapseAllXrayNodes = (): void => {
    if (validationResult?.parsedJson == null) return;
    const collapsed: Record<string, boolean> = {};
    const collectPaths = (obj: unknown, path: string, depth = 0): void => {
      if (depth > 50) return;
      if (obj != null && typeof obj === 'object') {
        collapsed[path] = false;
        if (Array.isArray(obj)) {
          obj.forEach((_, i) => collectPaths(obj[i], `${path}/${i}`, depth + 1));
        } else {
          Object.keys(obj).forEach(k => collectPaths((obj as Record<string, unknown>)[k], `${path}/${k}`, depth + 1));
        }
      }
    };
    collectPaths(validationResult.parsedJson, 'root');
    setXrayExpandedNodes(collapsed);
  };

  const handleEditorDidMount = (editor: unknown): void => {
    (editorRef as React.MutableRefObject<unknown>).current = editor;
  };

  const handleFileUpload = (event: React.ChangeEvent<HTMLInputElement>): void => {
    const file = event.target.files?.[0];
    if (file) {
      // Clear example name since user is loading their own file
      setLoadedExampleName(null);

      if (file.size > 10 * 1024 * 1024) {
        setLargeFileWarning('File is very large (>10MB). This may cause performance issues.');
      } else if (file.size > LARGE_FILE_BYTES) {
        setLargeFileWarning('Large file detected. Some features may be disabled for performance.');
      } else {
        setLargeFileWarning(null);
      }

      const reader = new FileReader();
      reader.onload = (e) => {
        const result = e.target?.result;
        if (typeof result === 'string') {
          if (file.size > LARGE_FILE_BYTES) {
            setShowXRay(false);
            setXrayExpandedNodes({});
          }
          setJsonInput(result);
        }
      };
      reader.onerror = () => setLoadError('Failed to read file');
      reader.readAsText(file);
    }
    event.target.value = '';
  };

  React.useEffect(() => {
    return () => {
      if (workerRef.current) {
        workerRef.current.terminate();
        workerRef.current = null;
      }
    };
  }, []);

  const formatJson = (): void => {
    try {
      const parsed = JSON.parse(jsonInput);
      setJsonInput(JSON.stringify(parsed, null, 2));
    } catch {
      // Can't format invalid JSON
    }
  };

  const toggleCard = (cardId: string): void => {
    setExpandedCards(prev => ({ ...prev, [cardId]: !prev[cardId] }));
  };

  const expandAllCards = (): void => {
    const allCardIds = ['ready', 'success', 'schema-info'];
    if (validationResult?.errors) {
      validationResult.errors.forEach((_, i) => allCardIds.push(`error-${i}`));
    }
    const expanded: Record<string, boolean> = {};
    allCardIds.forEach(id => { expanded[id] = true; });
    setExpandedCards(expanded);
  };

  const collapseAllCards = (): void => {
    const allCardIds = ['ready', 'success', 'schema-info'];
    if (validationResult?.errors) {
      validationResult.errors.forEach((_, i) => allCardIds.push(`error-${i}`));
    }
    const collapsed: Record<string, boolean> = {};
    allCardIds.forEach(id => { collapsed[id] = false; });
    setExpandedCards(collapsed);
  };

  const handleToggleXRay = (): void => {
    if (!showXRay && isLargeFile) {
      if (!window.confirm('XRay view may be slow for large files. Continue?')) return;
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

  const editorOptions = React.useMemo(() => {
    const baseOptions = {
      lineNumbers: 'on' as const,
      scrollBeyondLastLine: false,
      wordWrap: 'on' as const,
      automaticLayout: true,
      fontSize: 14,
      folding: true,
      formatOnPaste: true,
      tabSize: 2,
      renderLineHighlight: 'all' as const,
      bracketPairColorization: { enabled: true },
      largeFileOptimizations: true,
      maxTokenizationLineLength: 20000,
    };

    if (isLargeFile) {
      return {
        ...baseOptions,
        minimap: { enabled: false },
        renderLineHighlight: 'none' as const,
        folding: false,
        wordWrap: 'off' as const,
        bracketPairColorization: { enabled: false },
        matchBrackets: 'never' as const,
        occurrencesHighlight: 'off' as const,
        selectionHighlight: false,
        renderWhitespace: 'none' as const,
        guides: { indentation: false, bracketPairs: false, highlightActiveBracketPair: false },
        colorDecorators: false,
        links: false,
        quickSuggestions: false,
        suggestOnTriggerCharacters: false,
        acceptSuggestionOnEnter: 'off' as const,
        tabCompletion: 'off' as const,
        parameterHints: { enabled: false },
        hover: { enabled: false },
        maxTokenizationLineLength: 5000,
        stopRenderingLineAfter: 10000,
      };
    }

    return { ...baseOptions, minimap: { enabled: true } };
  }, [isLargeFile]);

  if (loadError) {
    return <div className="alert alert--danger margin--lg">{loadError}</div>;
  }

  const errorCount = validationResult?.errors?.length ?? 0;

  return (
    <div style={styles.container}>
      {(largeFileWarning != null || isLargeFile) && (
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
          <span>⚠️ {largeFileWarning ?? 'Large file mode: Some features disabled for performance.'}</span>
          <button
            onClick={() => setLargeFileWarning(null)}
            style={{ background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', padding: '0 0.5rem' }}
          >✕</button>
        </div>
      )}

      <IRCheckerToolbar
        selectedVersion={selectedVersion}
        onVersionChange={handleVersionChange}
        onFileUpload={handleFileUpload}
        onLoadSampleStart={() => setIsLoadingContent(true)}
        onLoadSample={(text, isLarge, exampleName) => {
          // Track the loaded example name
          setLoadedExampleName(exampleName ?? null);

          if (isLarge !== undefined) {
            setAutoValidate(false);
            setShowXRay(false);
            setLargeFileWarning(
              isLarge
                ? 'Large example loaded. Auto-validation disabled. Click "Validate" when ready.'
                : 'Example loaded. Auto-validation disabled. Click "Validate" to check against schema.'
            );
            const runAfterYield = typeof requestAnimationFrame !== 'undefined'
              ? (fn: () => void) => requestAnimationFrame(() => requestAnimationFrame(fn))
              : (fn: () => void) => setTimeout(fn, 0);
            runAfterYield(() => {
              setJsonInput(text);
              runAfterYield(() => setIsLoadingContent(false));
            });
          } else {
            setJsonInput(text);
          }
        }}
        loadedExampleName={loadedExampleName}
        onFormat={formatJson}
        autoValidate={autoValidate}
        onAutoValidateChange={setAutoValidate}
        onValidate={validateJson}
        validationMode={validationMode}
        onValidationModeChange={setValidationMode}
        showXRay={showXRay}
        onToggleXRay={handleToggleXRay}
        styles={styles}
        colorMode={colorMode}
        fileInputRef={fileInputRef}
      />

      <div style={styles.mainContent} ref={containerRef}>
        <div style={styles.editorPane}>
          <div style={styles.editorHeader}>
            <span>
              morphir-ir.json
              {loadedExampleName && <span style={{ fontStyle: 'italic', opacity: 0.8 }}> — {loadedExampleName}</span>}
              {isLargeFile && ' (large file)'}
              {isLoadingContent && ' • Loading…'}
            </span>
            <span>
              {isLoadingContent ? 'Loading content…' : (
                <>{jsonInput.split('\n').length} lines{isValidating && ' • Validating...'}</>
              )}
            </span>
          </div>
          <Editor
            height="100%"
            language="json"
            value={jsonInput}
            onChange={(value) => setJsonInput(value ?? '')}
            onMount={handleEditorDidMount}
            theme={colorMode === 'dark' ? 'vs-dark' : 'light'}
            options={editorOptions}
            loading={<div style={{ padding: '1rem' }}>Loading editor...</div>}
          />
        </div>

        {showXRay && (
          <>
            <div style={styles.xraySplitter} onMouseDown={handleXrayMouseDown} />
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

        <div style={styles.splitter} onMouseDown={handleMouseDown} />

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

      <div style={styles.statusBar}>
        <span>
          {isLoadingContent ? '⏳ Loading content…' :
            isValidating ? '⏳ Validating...' :
              validationResult?.valid ? '✓ Valid' :
                errorCount > 0 ? `✗ ${errorCount} issue${errorCount > 1 ? 's' : ''} found` : 'Ready'}
        </span>
        <span>
          {loadedExampleName && <span style={{ opacity: 0.7 }}>{loadedExampleName} • </span>}
          Morphir IR Checker • {selectedVersion.toUpperCase()}
        </span>
      </div>
    </div>
  );
}

function IRChecker(): React.ReactElement {
  return (
    <Layout title="IR Checker" description="Validate Morphir IR JSON against official schemas" noFooter>
      <IRCheckerContent />
    </Layout>
  );
}

export default IRChecker;
