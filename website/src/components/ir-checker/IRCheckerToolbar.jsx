import React from 'react';
import { schemaVersions, sampleJson } from './constants';

/**
 * Toolbar component with schema selection, file operations, and view toggles
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
  const dividerStyle = {
    borderLeft: `1px solid ${colorMode === 'dark' ? '#555' : '#ccc'}`,
    height: '20px'
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
        <button onClick={() => onLoadSample(sampleJson[selectedVersion])} style={styles.toolbarBtn}>
          Load Sample
        </button>
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
    </div>
  );
}

export default IRCheckerToolbar;
