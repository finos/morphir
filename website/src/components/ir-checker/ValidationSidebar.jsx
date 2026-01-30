import React from 'react';
import { ValidationCard, ErrorCard } from './ValidationCard';
import { schemaVersions } from './constants';

/**
 * Sidebar component displaying validation results
 */
export function ValidationSidebar({
  validationResult,
  selectedVersion,
  expandedCards,
  onToggleCard,
  onExpandAll,
  onCollapseAll,
  onNavigateToPath,
  styles,
  colorMode,
}) {
  const errorCount = validationResult?.errors?.length || 0;

  const isCardExpanded = (cardId) => {
    if (expandedCards[cardId] === undefined) {
      return cardId.startsWith('error-') || cardId === 'success' || cardId === 'ready';
    }
    return expandedCards[cardId];
  };

  return (
    <div style={styles.sidebar}>
      <div style={styles.sidebarHeader}>
        <div style={styles.sidebarHeaderLeft}>
          <span>Validation Results</span>
          <span style={styles.badge(validationResult?.valid ? '#4caf50' : (errorCount > 0 ? '#f44336' : '#2196f3'))}>
            {validationResult?.valid ? 'VALID' : (errorCount > 0 ? `${errorCount} ISSUES` : 'READY')}
          </span>
        </div>
        <div style={styles.sidebarHeaderButtons}>
          <button style={styles.iconBtn} onClick={onExpandAll} title="Expand all">
            <span>+</span>
          </button>
          <button style={styles.iconBtn} onClick={onCollapseAll} title="Collapse all">
            <span>−</span>
          </button>
        </div>
      </div>

      <div style={styles.sidebarContent}>
        {/* Ready state */}
        {!validationResult && (
          <ValidationCard
            id="ready"
            type="info"
            title="Ready to Validate"
            icon="ℹ️"
            isExpanded={isCardExpanded('ready')}
            onToggle={onToggleCard}
            styles={styles}
            colorMode={colorMode}
          >
            Enter or paste Morphir IR JSON in the editor. Validation runs automatically.
          </ValidationCard>
        )}

        {/* Success state */}
        {validationResult?.valid && (
          <ValidationCard
            id="success"
            type="success"
            title="Validation Passed"
            icon="✅"
            meta={`Schema ${selectedVersion}`}
            isExpanded={isCardExpanded('success')}
            onToggle={onToggleCard}
            styles={styles}
            colorMode={colorMode}
          >
            Your JSON conforms to the Morphir IR {selectedVersion} schema.
          </ValidationCard>
        )}

        {/* Error cards */}
        {validationResult?.errors?.map((err, i) => (
          <ErrorCard
            key={i}
            error={err}
            index={i}
            isExpanded={isCardExpanded(`error-${i}`)}
            onToggle={onToggleCard}
            onNavigateToPath={onNavigateToPath}
            styles={styles}
            colorMode={colorMode}
          />
        ))}

        {/* Schema Info Card */}
        <div style={{ ...styles.card('info'), marginTop: '1rem' }}>
          <div style={styles.cardHeader} onClick={() => onToggleCard('schema-info')}>
            <span style={styles.cardTitle}>
              <span style={{ ...styles.cardToggle, transform: isCardExpanded('schema-info') ? 'rotate(90deg)' : 'rotate(0deg)' }}>▶</span>
              <span>📋</span> Schema Info
            </span>
          </div>
          {isCardExpanded('schema-info') && (
            <div style={styles.cardBody}>
              <div style={{ marginBottom: '0.5rem' }}>
                <strong>Selected:</strong> Version {selectedVersion} ({schemaVersions.find(v => v.value === selectedVersion)?.status})
              </div>
              <div style={{ fontSize: '0.8rem' }}>
                <a href={`/schemas/morphir-ir-${selectedVersion}.json`} target="_blank" rel="noopener">Download JSON</a>
                {' | '}
                <a href={`/schemas/morphir-ir-${selectedVersion}.yaml`} target="_blank" rel="noopener">Download YAML</a>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default ValidationSidebar;
