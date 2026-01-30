import React from 'react';
import { XRayTreeNode } from './XRayTreeNode';

// Maximum depth to render for large files
const MAX_DEPTH_LARGE_FILE = 5;
const MAX_DEPTH_NORMAL = 50;

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
  isLargeFile = false,
}) {
  const maxDepth = isLargeFile ? MAX_DEPTH_LARGE_FILE : MAX_DEPTH_NORMAL;

  return (
    <div style={styles.xrayPanel}>
      <div style={styles.xrayHeader}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <span style={{ fontFamily: 'monospace' }}>⟨/⟩</span>
          <span>XRay View</span>
          {isLargeFile && (
            <span style={{
              fontSize: '0.7rem',
              padding: '0.1rem 0.4rem',
              backgroundColor: colorMode === 'dark' ? '#4a3000' : '#fff3cd',
              color: colorMode === 'dark' ? '#ffc107' : '#856404',
              borderRadius: '3px',
            }}>
              Limited
            </span>
          )}
        </div>
        <div style={{ display: 'flex', gap: '0.25rem' }}>
          {!isLargeFile && (
            <button
              style={styles.iconBtn}
              onClick={onExpandAll}
              title="Expand all"
            >
              <span>+</span>
            </button>
          )}
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
        {isLargeFile && (
          <div style={{
            padding: '0.5rem',
            marginBottom: '0.5rem',
            backgroundColor: colorMode === 'dark' ? '#2a2a00' : '#fffde7',
            borderRadius: '4px',
            fontSize: '0.8rem',
            color: colorMode === 'dark' ? '#ffd54f' : '#f57f17',
          }}>
            ⚠️ Large file: Tree depth limited to {maxDepth} levels
          </div>
        )}
        {parsedJson ? (
          <XRayTreeNode
            name="root"
            value={parsedJson}
            depth={0}
            maxDepth={maxDepth}
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
