import React, { useState, useEffect } from 'react';
import { schemaVersions, sampleJson } from './constants';

/**
 * Toolbar component with schema selection, file operations, and view toggles
 * Examples are dynamically sourced from /ir/examples/<version>/index.json
 */
export function IRCheckerToolbar({
  selectedVersion,
  onVersionChange,
  onFileUpload,
  onLoadSample,
  onFormat,
  autoValidate,
  onAutoValidateChange,
  onValidate,
  showXRay,
  onToggleXRay,
  styles,
  colorMode,
  fileInputRef,
}) {
  const [showExampleDropdown, setShowExampleDropdown] = useState(false);
  const [loadingExample, setLoadingExample] = useState(null);
  const [availableExamples, setAvailableExamples] = useState([]);
  const [loadingManifest, setLoadingManifest] = useState(false);

  // Fetch available examples when version changes
  useEffect(() => {
    const fetchExamples = async () => {
      setLoadingManifest(true);
      try {
        const response = await fetch(`/ir/examples/${selectedVersion}/index.json`);
        if (response.ok) {
          const manifest = await response.json();
          setAvailableExamples(manifest.examples || []);
        } else {
          // No manifest found, clear examples
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

  const dividerStyle = {
    borderLeft: `1px solid ${colorMode === 'dark' ? '#555' : '#ccc'}`,
    height: '20px'
  };

  const dropdownStyle = {
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

  const dropdownItemStyle = {
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

  const handleLoadInlineSample = () => {
    setShowExampleDropdown(false);
    onLoadSample(sampleJson[selectedVersion]);
  };

  const handleLoadExample = async (example) => {
    setShowExampleDropdown(false);
    setLoadingExample(example.id);
    try {
      const response = await fetch(`/ir/examples/${selectedVersion}/${example.file}`);
      if (!response.ok) throw new Error(`Failed to load ${example.file}`);
      const text = await response.text();
      onLoadSample(text);
    } catch (error) {
      console.error('Failed to load example:', error);
      alert(`Failed to load example: ${error.message}`);
    } finally {
      setLoadingExample(null);
    }
  };

  return (
    <div style={styles.toolbar}>
      {/* Schema Version Selection */}
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

      {/* File Operations */}
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

        {/* Example Dropdown - sourced from /ir/examples/<version>/ */}
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
            {loadingExample ? 'Loading...' : 'Load Example'}
            <span style={{ fontSize: '0.6rem' }}>▼</span>
          </button>

          {showExampleDropdown && (
            <div style={dropdownStyle}>
              {/* Always available: inline empty library */}
              <button
                style={dropdownItemStyle}
                onClick={handleLoadInlineSample}
                onMouseEnter={(e) => e.target.style.backgroundColor = colorMode === 'dark' ? '#404040' : '#f0f0f0'}
                onMouseLeave={(e) => e.target.style.backgroundColor = 'transparent'}
              >
                Empty Library
              </button>

              {/* Separator if we have examples */}
              {availableExamples.length > 0 && (
                <div style={{
                  borderTop: `1px solid ${colorMode === 'dark' ? '#555' : '#ddd'}`,
                  margin: '4px 0',
                }} />
              )}

              {/* Examples from manifest */}
              {availableExamples.map((example) => (
                <button
                  key={example.id}
                  style={dropdownItemStyle}
                  onClick={() => handleLoadExample(example)}
                  onMouseEnter={(e) => e.target.style.backgroundColor = colorMode === 'dark' ? '#404040' : '#f0f0f0'}
                  onMouseLeave={(e) => e.target.style.backgroundColor = 'transparent'}
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

      {/* Validation Controls */}
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
      </div>

      <div style={dividerStyle} />

      {/* View Toggles */}
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

      {/* Click outside to close dropdown */}
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

