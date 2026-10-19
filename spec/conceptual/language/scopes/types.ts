import type { Fragment, Source, Span } from "../ast/types";

/** Authored fixture facts, not validated scopes or resolver results. */
export type Selector =
  | { kind: "type"; name: string }
  | { kind: "value"; name: string }
  | { kind: "constructor"; typeName: string; name: string };

export type Category =
  | { category: "type" }
  | { category: "value" }
  | { category: "constructor"; ownerTypeId: string };

export type Entry = { kind: "region" | "import" | "symbol" | "reference"; id: string };

export type Region = {
  id: string;
  sourceId: string;
  span: Span;
  entries: Entry[];
  critical?: string[];
} & (
  | { kind: "file"; form: "file"; name: []; parentId?: never }
  | { kind: "namespace"; form: "header" | "block"; name: string[]; parentId: string }
  | { kind: "model"; form: "block"; name: [string]; parentId: string }
  | { kind: "module"; form: "header" | "block"; name: string[]; parentId: string; exports: Selector[] }
);

export type SyntaxEntry = { kind: "region" | "import" | "declaration"; id: string };
type WithSyntaxEntries<R> = R extends Region ? Omit<R, "entries"> & { entries: SyntaxEntry[] } : never;
export type SyntaxRegion = WithSyntaxEntries<Region>;

export type SyntaxDeclaration = {
  moduleRegionId: string;
  fragmentId: string;
  nodeId: string;
} & (
  | { category: "type" | "value"; ownerNodeId?: never }
  | { category: "constructor"; ownerNodeId: string }
);

export type SyntaxOutline = {
  profile: "morphir-scopes/0.1.0-draft.1";
  sources: Source[];
  regions: SyntaxRegion[];
  fragments: { id: string; fragment: Fragment }[];
  imports: ScopeImport[];
  declarations: SyntaxDeclaration[];
};

export type ScopeSymbol = {
  id: string;
  moduleRegionId: string;
  name: string;
  canonicalName: string;
  declaration: { fragmentId: string; nodeId: string };
  links: unknown[];
  provenance: unknown[];
  critical?: string[];
} & Category;

export type DependencySymbol = {
  id: string;
  moduleName: string;
  name: string;
  canonicalName: string;
  visibility: "public" | "private";
  links: unknown[];
  provenance: unknown[];
  critical?: string[];
} & Category;

export type Dependency = {
  slot: string;
  resolvedNodeId: string;
  packageName: string;
  revision: string;
  exportTable: { path: string; moduleName: string }[];
  symbols: DependencySymbol[];
  critical?: string[];
};

export type ScopeImport = {
  id: string;
  regionId: string;
  span: Span;
  target:
    | { kind: "unit"; path: string[] }
    | { kind: "dependency"; slot: string; exportPath: string; authoredPath?: string[] };
  mode:
    | { kind: "qualified"; alias: string }
    | { kind: "selected"; selectors: Selector[] };
  critical?: string[];
};

export type LocalBinder = { id: string; name: string; category: "type" | "value" };

export type ScopeReference = {
  id: string;
  regionId: string;
  span: Span;
  path: string[];
  localBinders: LocalBinder[];
  critical?: string[];
} & Category;

export type ModelBinding = {
  regionId: string;
  model: { id: string; revision: string; qualifiedName?: string[]; metadata: unknown };
};

export type TypeEnvironment = {
  namedTypes: { id: string; path: string[]; arity: number; visibility: "public" | "private" }[];
};

export type ScopeInput = {
  profile: "morphir-scopes/0.1.0-draft.1";
  declarationProfile: "morphir-declarations/0.1.0-draft.1";
  context: {
    unitId: string;
    packageName: string;
    sourceSet: string[];
    model: { id: string; revision: string; qualifiedName?: string[]; metadata: unknown };
  };
  modelBindings: ModelBinding[];
  typeEnvironment: TypeEnvironment;
  dependencies: Dependency[];
  sources: Source[];
  fragments: { id: string; fragment: Fragment }[];
  regions: Region[];
  symbols: ScopeSymbol[];
  imports: ScopeImport[];
  references: ScopeReference[];
  critical?: string[];
};

/** Independently authored observations; fixture builders never derive these. */
export type BindingObservation =
  | { kind: "binder"; binderId: string; name: string; category: "type" | "value" }
  | ({
    kind: "symbol";
    symbolId: string;
    binding:
      | { kind: "unit"; unitId: string }
      | { kind: "dependency"; slot: string; resolvedNodeId: string; revision: string };
    packageName: string;
    moduleName: string;
    canonicalName: string;
    links: unknown[];
    provenance: unknown[];
  } & Category);
