/**
 * Shared types for the IR Checker components and validation.
 */

import type { CSSProperties } from 'react';

export type SchemaVersionValue = 'v1' | 'v2' | 'v3' | 'v4';

/** Validation mode controls how thorough the validation is */
export type ValidationMode = 'fast' | 'thorough';

export interface ValidationModeInfo {
  value: ValidationMode;
  label: string;
  description: string;
}

export interface SchemaVersion {
  value: SchemaVersionValue;
  label: string;
  file: string;
  status: string;
}

export type ValidationErrorType = 'parse' | 'schema' | 'system';

export interface ValidationError {
  type: ValidationErrorType;
  message: string;
  path?: string;
  line?: number | null;
  keyword?: string;
  params?: Record<string, unknown>;
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
  parsedJson: unknown;
  schemaVersion?: SchemaVersionValue;
}

/** Record of schema version -> JSON Schema object */
export type SchemasMap = Partial<Record<SchemaVersionValue, object>>;

/** Styles object returned by createStyles */
export interface IRCheckerStyles {
  container: CSSProperties;
  toolbar: CSSProperties;
  toolbarGroup: CSSProperties;
  toolbarLabel: CSSProperties;
  versionBtn: (isSelected: boolean) => CSSProperties;
  toolbarBtn: CSSProperties;
  mainContent: CSSProperties;
  editorPane: CSSProperties;
  splitter: CSSProperties;
  editorHeader: CSSProperties;
  sidebar: CSSProperties;
  sidebarHeader: CSSProperties;
  sidebarHeaderLeft: CSSProperties;
  sidebarHeaderButtons: CSSProperties;
  iconBtn: CSSProperties;
  sidebarContent: CSSProperties;
  card: (type: 'info' | 'success' | 'error') => CSSProperties;
  cardHeader: CSSProperties;
  cardTitle: CSSProperties;
  cardToggle: CSSProperties;
  cardMeta: CSSProperties;
  pathLink: CSSProperties;
  cardBody: CSSProperties;
  badge: (color: string) => CSSProperties;
  statusBar: CSSProperties;
  xrayPanel: CSSProperties;
  xrayHeader: CSSProperties;
  xrayContent: CSSProperties;
  xraySplitter: CSSProperties;
  xrayToggleBtn: (isActive: boolean) => CSSProperties;
}

export interface CreateStylesParams {
  colorMode: 'dark' | 'light';
  sidebarWidth: number;
  xrayWidth: number;
  isDragging: boolean;
  isDraggingXray: boolean;
  validationResult: ValidationResult | null;
}

/** Example item from manifest /ir/examples/<version>/index.json */
export interface ExampleManifestItem {
  id: string;
  label: string;
  file: string;
  description?: string;
  large?: boolean;
  sizeWarning?: string;
}

// --- Worker message types ---

export interface WorkerValidateMessage {
  type: 'validate';
  runId: number;
  jsonString: string;
  schema?: object;
  schemaUrl?: string;
  schemaVersion: SchemaVersionValue;
}

export interface WorkerResultMessage {
  type: 'result';
  runId: number;
  valid: boolean;
  errors: ValidationError[];
  parsedJson: unknown;
  schemaVersion: string | null;
}

export interface WorkerErrorMessage {
  type: 'error';
  runId: number;
  message: string;
}

export type WorkerOutMessage = WorkerResultMessage | WorkerErrorMessage;
