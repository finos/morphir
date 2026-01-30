import React from 'react';
import { XRayTreeNode } from './XRayTreeNode';

/**
 * XRay Panel component for displaying parsed JSON structure
 */
export function XRayPanel({
  colorMode,
  parsedJson,
  jsonInput,
  expandedNodes,
  toggleNode,
  onSelectNode,
  onExpandAll,
  onCollapseAll,
  onClose,
  styles,
}) {
  return (
    <div style={styles.xrayPanel}>
      <div style={styles.xrayHeader}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <span style={{ fontFamily: 'monospace' }}>⟨/⟩</span>
          <span>XRay View</span>
        </div>
        <div style={{ display: 'flex', gap: '0.25rem' }}>
          <button
            style={styles.iconBtn}
            onClick={onExpandAll}
            title="Expand all"
          >
            <span>+</span>
          </button>
          <button
            style={styles.iconBtn}
            onClick={onCollapseAll}
            title="Collapse all"
          >
            <span>−</span>
          </button>
          <button
            style={styles.iconBtn}
            onClick={onClose}
            title="Close XRay panel"
          >
            <span>✕</span>
          </button>
        </div>
      </div>
      <div style={styles.xrayContent}>
        {parsedJson ? (
          <XRayTreeNode
            name="root"
            value={parsedJson}
            depth={0}
            colorMode={colorMode}
            expandedNodes={expandedNodes}
            toggleNode={toggleNode}
            path="root"
            onSelectNode={onSelectNode}
          />
        ) : (
          <div style={{
            padding: '2rem',
            textAlign: 'center',
            color: colorMode === 'dark' ? '#888' : '#666',
            fontSize: '0.9rem'
          }}>
            {jsonInput?.trim() ? (
              <span>
                <span style={{ display: 'block', fontSize: '1.5rem', marginBottom: '0.5rem' }}>⚠️</span>
                Parse the JSON first to view the XRay structure
              </span>
            ) : (
              <span>
                <span style={{ display: 'block', fontSize: '1.5rem', marginBottom: '0.5rem' }}>📄</span>
                Enter Morphir IR JSON to see its structure
              </span>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export default XRayPanel;
