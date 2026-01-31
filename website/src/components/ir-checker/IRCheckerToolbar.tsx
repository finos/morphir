import React, { useState, useEffect } from 'react';
import { schemaVersions, sampleJson, validationModes } from './constants';
import type { IRCheckerStyles, SchemaVersionValue, ExampleManifestItem, ValidationMode } from './types';

interface IRCheckerToolbarProps {
  selectedVersion: SchemaVersionValue;
  onVersionChange: (version: SchemaVersionValue) => void;
  onFileUpload: (event: React.ChangeEvent<HTMLInputElement>) => void;
  onLoadSample: (text: string, isLarge?: boolean, exampleName?: string) => void;
  onLoadSampleStart?: () => void;
  onFormat: () => void;
  autoValidate: boolean;
  onAutoValidateChange: (checked: boolean) => void;
  onValidate: () => void;
  validationMode: ValidationMode;
  onValidationModeChange: (mode: ValidationMode) => void;
  showXRay: boolean;
  onToggleXRay: () => void;
  styles: IRCheckerStyles;
  colorMode: 'dark' | 'light';
  fileInputRef: React.RefObject<HTMLInputElement | null>;
}

/**
 * Toolbar component with schema selection, file operations, and view toggles
 * Examples are dynamically sourced from /ir/examples/<version>/index.json
 */
export function IRCheckerToolbar({
  selectedVersion,
  onVersionChange,
  onFileUpload,
  onLoadSample,
  onLoadSampleStart,
  onFormat,
  autoValidate,
  onAutoValidateChange,
  onValidate,
  validationMode,
  onValidationModeChange,
  showXRay,
  onToggleXRay,
  styles,
  colorMode,
  fileInputRef,
}: IRCheckerToolbarProps): React.ReactElement {
  const [showExampleDropdown, setShowExampleDropdown] = useState(false);
  const [loadingExample, setLoadingExample] = useState<string | null>(null);
  const [availableExamples, setAvailableExamples] = useState<ExampleManifestItem[]>([]);
  const [loadingManifest, setLoadingManifest] = useState(false);

  useEffect(() => {
    const fetchExamples = async (): Promise<void> => {
      setLoadingManifest(true);
      try {
        const response = await fetch(`/ir/examples/${selectedVersion}/index.json`);
        if (response.ok) {
          const manifest = await response.json() as { examples?: ExampleManifestItem[] };
          setAvailableExamples(manifest.examples ?? []);
        } else {
          setAvailableExamples([]);
        }
      } catch (error) {
        console.warn(`No example manifest found for ${selectedVersion}:`, error);
        setAvailableExamples([]);
      } finally {
        setLoadingManifest(false);
      }
    };

    fetchExamples();
  }, [selectedVersion]);

  const dividerStyle: React.CSSProperties = {
    borderLeft: `1px solid ${colorMode === 'dark' ? '#555' : '#ccc'}`,
    height: '20px'
  };

  const dropdownStyle: React.CSSProperties = {
    position: 'absolute',
    top: '100%',
    left: 0,
    marginTop: '4px',
    backgroundColor: colorMode === 'dark' ? '#2d2d2d' : '#fff',
    border: `1px solid ${colorMode === 'dark' ? '#555' : '#ccc'}`,
    borderRadius: '4px',
    boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
    zIndex: 1000,
    minWidth: '200px',
  };

  const dropdownItemStyle: React.CSSProperties = {
    display: 'block',
    width: '100%',
    padding: '8px 12px',
    border: 'none',
    background: 'none',
    textAlign: 'left',
    cursor: 'pointer',
    color: colorMode === 'dark' ? '#fff' : '#333',
    fontSize: '0.875rem',
  };

  const handleLoadInlineSample = (): void => {
    setShowExampleDropdown(false);
    const sample = sampleJson[selectedVersion];
    if (sample != null) {
      onLoadSample(sample, false, 'Empty Library');
    }
  };

  const handleLoadExample = async (example: ExampleManifestItem): Promise<void> => {
    setShowExampleDropdown(false);

    if (example.large) {
      const proceed = window.confirm(
        `⚠️ Large File Warning\n\n` +
        `This example is ${example.sizeWarning ?? 'very large'}.\n\n` +
        `Loading it may:\n` +
        `• Take several seconds\n` +
        `• Disable auto-validation\n` +
        `• Disable XRay view\n` +
        `• Reduce editor features\n\n` +
        `Continue loading?`
      );
      if (!proceed) return;
    }

    onLoadSampleStart?.();
    setLoadingExample(example.id);
    try {
      const response = await fetch(`/ir/examples/${selectedVersion}/${example.file}`);
      if (!response.ok) throw new Error(`Failed to load ${example.file}`);
      const text = await response.text();
      onLoadSample(text, example.large ?? false, example.label);
    } catch (error) {
      console.error('Failed to load example:', error);
      alert(`Failed to load example: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      setLoadingExample(null);
    }
  };

  return (
    <div style={styles.toolbar}>
      <div style={styles.toolbarGroup}>
        <span style={styles.toolbarLabel}>Schema:</span>
        {schemaVersions.map((v) => (
          <button
            key={v.value}
            onClick={() => onVersionChange(v.value)}
            style={styles.versionBtn(selectedVersion === v.value)}
            title={v.status}
          >
            {v.label}
          </button>
        ))}
      </div>

      <div style={dividerStyle} />

      <div style={styles.toolbarGroup}>
        <input
          type="file"
          ref={fileInputRef}
          onChange={onFileUpload}
          accept=".json"
          style={{ display: 'none' }}
        />
        <button onClick={() => fileInputRef.current?.click()} style={styles.toolbarBtn}>
          Open File
        </button>

        <div style={{ position: 'relative' }}>
          <button
            onClick={() => setShowExampleDropdown(!showExampleDropdown)}
            style={{
              ...styles.toolbarBtn,
              display: 'flex',
              alignItems: 'center',
              gap: '4px',
            }}
            disabled={loadingExample !== null || loadingManifest}
          >
            {loadingExample != null ? 'Loading...' : 'Load Example'}
            <span style={{ fontSize: '0.6rem' }}>▼</span>
          </button>

          {showExampleDropdown && (
            <div style={dropdownStyle}>
              <button
                style={dropdownItemStyle}
                onClick={handleLoadInlineSample}
                onMouseEnter={(e) => { (e.target as HTMLElement).style.backgroundColor = colorMode === 'dark' ? '#404040' : '#f0f0f0'; }}
                onMouseLeave={(e) => { (e.target as HTMLElement).style.backgroundColor = 'transparent'; }}
              >
                Empty Library
              </button>

              {availableExamples.length > 0 && (
                <div style={{
                  borderTop: `1px solid ${colorMode === 'dark' ? '#555' : '#ddd'}`,
                  margin: '4px 0',
                }} />
              )}

              {availableExamples.map((example) => (
                <button
                  key={example.id}
                  style={dropdownItemStyle}
                  onClick={() => handleLoadExample(example)}
                  onMouseEnter={(e) => { (e.target as HTMLElement).style.backgroundColor = colorMode === 'dark' ? '#404040' : '#f0f0f0'; }}
                  onMouseLeave={(e) => { (e.target as HTMLElement).style.backgroundColor = 'transparent'; }}
                  title={example.description}
                >
                  {example.label}
                </button>
              ))}
            </div>
          )}
        </div>

        <button onClick={onFormat} style={styles.toolbarBtn}>
          Format
        </button>
      </div>

      <div style={dividerStyle} />

      <div style={styles.toolbarGroup}>
        <label style={{ ...styles.toolbarLabel, display: 'flex', alignItems: 'center', gap: '0.25rem', cursor: 'pointer' }}>
          <input
            type="checkbox"
            checked={autoValidate}
            onChange={(e) => onAutoValidateChange(e.target.checked)}
          />
          Auto-validate
        </label>
        {!autoValidate && (
          <button onClick={onValidate} style={{ ...styles.toolbarBtn, backgroundColor: '#0078d4', color: '#fff', border: 'none' }}>
            Validate
          </button>
        )}
        <select
          value={validationMode}
          onChange={(e) => onValidationModeChange(e.target.value as ValidationMode)}
          style={{
            ...styles.toolbarBtn,
            padding: '0.25rem 0.5rem',
            cursor: 'pointer',
          }}
          title={validationModes.find(m => m.value === validationMode)?.description}
        >
          {validationModes.map((mode) => (
            <option key={mode.value} value={mode.value}>
              {mode.label}
            </option>
          ))}
        </select>
      </div>

      <div style={dividerStyle} />

      <div style={styles.toolbarGroup}>
        <button
          onClick={onToggleXRay}
          style={styles.xrayToggleBtn(showXRay)}
          title="Toggle XRay View - Show parsed IR structure"
        >
          <span style={{ fontFamily: 'monospace' }}>⟨/⟩</span>
          XRay
        </button>
      </div>

      {showExampleDropdown && (
        <div
          style={{ position: 'fixed', inset: 0, zIndex: 999 }}
          onClick={() => setShowExampleDropdown(false)}
        />
      )}
    </div>
  );
}

export default IRCheckerToolbar;
