import React from 'react';
import { morphirNodeTypes } from './constants';

/**
 * Recursive tree node component for displaying JSON structure in XRay view
 */
export function XRayTreeNode({
  name,
  value,
  depth = 0,
  colorMode,
  expandedNodes,
  toggleNode,
  path,
  onSelectNode
}) {
  const nodeId = path;
  const isExpanded = expandedNodes[nodeId] !== false; // Default to expanded
  const hasChildren = value !== null && typeof value === 'object' && Object.keys(value).length > 0;
  const isArray = Array.isArray(value);

  // Determine node type and color
  const getNodeStyle = () => {
    if (value === null) return { bg: '#f5f5f5', label: 'null' };
    if (typeof value === 'string') return { bg: '#e3f2fd', label: 'String' };
    if (typeof value === 'number') return { bg: '#fff3e0', label: 'Number' };
    if (typeof value === 'boolean') return { bg: '#fce4ec', label: 'Boolean' };
    if (isArray) return { bg: '#e8f5e9', label: `Array[${value.length}]` };

    // Check for Morphir IR specific patterns
    const keys = Object.keys(value);
    if (keys.length === 1) {
      const key = keys[0];
      if (morphirNodeTypes.includes(key)) {
        return { bg: '#e1bee7', label: key };
      }
    }
    return { bg: '#f3e5f5', label: 'Object' };
  };

  const nodeStyle = getNodeStyle();
  const indent = depth * 16;

  const baseStyle = {
    fontFamily: 'monospace',
    fontSize: '0.8rem',
    marginLeft: `${indent}px`,
    marginBottom: '2px',
  };

  const getDarkBgColor = (lightBg) => {
    const colorMap = {
      '#e3f2fd': '#1e3a5f',
      '#fff3e0': '#4a3000',
      '#fce4ec': '#4a1a2c',
      '#e8f5e9': '#1a3a1f',
      '#e1bee7': '#3a1a4a',
      '#f3e5f5': '#2a1a3a',
      '#f5f5f5': '#2a2a2a',
    };
    return colorMap[lightBg] || '#2a2a2a';
  };

  const headerStyle = {
    display: 'flex',
    alignItems: 'center',
    padding: '2px 6px',
    backgroundColor: colorMode === 'dark' ? getDarkBgColor(nodeStyle.bg) : nodeStyle.bg,
    borderRadius: '3px',
    cursor: 'pointer',
    borderLeft: `3px solid ${colorMode === 'dark' ? '#666' : '#999'}`,
  };

  const labelStyle = {
    color: colorMode === 'dark' ? '#aaa' : '#666',
    fontSize: '0.7rem',
    marginLeft: '8px',
  };

  const renderValue = () => {
    if (value === null) return <span style={{ color: '#999' }}>null</span>;
    if (typeof value === 'string') return <span style={{ color: colorMode === 'dark' ? '#98c379' : '#22863a' }}>"{value}"</span>;
    if (typeof value === 'number') return <span style={{ color: colorMode === 'dark' ? '#d19a66' : '#005cc5' }}>{value}</span>;
    if (typeof value === 'boolean') return <span style={{ color: colorMode === 'dark' ? '#56b6c2' : '#d73a49' }}>{value.toString()}</span>;
    return null;
  };

  const toggleIcon = hasChildren ? (isExpanded ? '▼' : '▶') : '•';

  // Convert internal path to JSON path format (remove 'root' prefix)
  const getJsonPath = () => {
    const jsonPath = path.replace(/^root/, '').replace(/\/(\d+)/g, '/$1');
    return jsonPath || '/';
  };

  const handleClick = (e) => {
    // If clicking on the toggle icon area, just toggle expand/collapse
    if (hasChildren && e.target.closest('.xray-toggle')) {
      toggleNode(nodeId);
      return;
    }
    // Otherwise, navigate to the node in the editor
    onSelectNode && onSelectNode(getJsonPath());
  };

  const handleDoubleClick = () => {
    // Double-click toggles expand/collapse for nodes with children
    if (hasChildren) {
      toggleNode(nodeId);
    }
  };

  return (
    <div style={baseStyle}>
      <div
        style={headerStyle}
        onClick={handleClick}
        onDoubleClick={handleDoubleClick}
        title="Click to highlight in editor, double-click to expand/collapse"
      >
        <span
          className="xray-toggle"
          style={{ width: '12px', color: colorMode === 'dark' ? '#888' : '#666', fontSize: '0.7rem' }}
          onClick={(e) => { e.stopPropagation(); hasChildren && toggleNode(nodeId); }}
        >
          {toggleIcon}
        </span>
        {name && (
          <span style={{ fontWeight: 'bold', color: colorMode === 'dark' ? '#61afef' : '#0366d6', marginRight: '4px' }}>
            {name}:
          </span>
        )}
        {!hasChildren && renderValue()}
        {hasChildren && <span style={labelStyle}>{nodeStyle.label}</span>}
      </div>
      {hasChildren && isExpanded && (
        <div>
          {isArray ? (
            value.map((item, index) => (
              <XRayTreeNode
                key={index}
                name={`[${index}]`}
                value={item}
                depth={depth + 1}
                colorMode={colorMode}
                expandedNodes={expandedNodes}
                toggleNode={toggleNode}
                path={`${path}/${index}`}
                onSelectNode={onSelectNode}
              />
            ))
          ) : (
            Object.entries(value).map(([key, val]) => (
              <XRayTreeNode
                key={key}
                name={key}
                value={val}
                depth={depth + 1}
                colorMode={colorMode}
                expandedNodes={expandedNodes}
                toggleNode={toggleNode}
                path={`${path}/${key}`}
                onSelectNode={onSelectNode}
              />
            ))
          )}
        </div>
      )}
    </div>
  );
}

export default XRayTreeNode;
