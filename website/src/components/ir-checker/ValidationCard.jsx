import React from 'react';

/**
 * Collapsible card component for validation results
 */
export function ValidationCard({
  id,
  type,
  title,
  icon,
  meta,
  children,
  isExpanded,
  onToggle,
  styles,
  colorMode,
}) {
  return (
    <div style={styles.card(type)}>
      <div style={styles.cardHeader} onClick={() => onToggle(id)}>
        <span style={styles.cardTitle}>
          <span style={{
            ...styles.cardToggle,
            transform: isExpanded ? 'rotate(90deg)' : 'rotate(0deg)'
          }}>▶</span>
          <span>{icon}</span> {title}
        </span>
        {meta && <span style={styles.cardMeta}>{meta}</span>}
      </div>
      {isExpanded && (
        <div style={styles.cardBody}>
          {children}
        </div>
      )}
    </div>
  );
}

/**
 * Error card with clickable path
 */
export function ErrorCard({
  error,
  index,
  isExpanded,
  onToggle,
  onNavigateToPath,
  styles,
  colorMode,
}) {
  const title = error.type === 'parse' ? 'Parse Error' :
                error.type === 'schema' ? 'Schema Error' : 'Error';
  const meta = error.line ? `Line ${error.line}` : null;

  return (
    <ValidationCard
      id={`error-${index}`}
      type="error"
      title={title}
      icon="❌"
      meta={meta}
      isExpanded={isExpanded}
      onToggle={onToggle}
      styles={styles}
      colorMode={colorMode}
    >
      {error.message}
      {error.path && error.path !== '/' && (
        <div style={{ marginTop: '0.5rem' }}>
          <span
            style={styles.pathLink}
            onClick={(e) => { e.stopPropagation(); onNavigateToPath(error.path); }}
            title="Click to highlight in editor"
          >
            {error.path}
          </span>
        </div>
      )}
      {error.keyword && (
        <div style={{ marginTop: '0.5rem', fontSize: '0.75rem', color: colorMode === 'dark' ? '#888' : '#666' }}>
          Rule: {error.keyword}
        </div>
      )}
    </ValidationCard>
  );
}

export default ValidationCard;
