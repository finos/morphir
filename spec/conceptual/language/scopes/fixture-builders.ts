import type { ScopeInput } from "./types";

/** Clone supplied records without normalizing names or resolving references. */
export function constructInput(records: Omit<ScopeInput, "profile" | "declarationProfile">): ScopeInput {
  return structuredClone({
    ...records,
    profile: "morphir-scopes/0.1.0-draft.1",
    declarationProfile: "morphir-declarations/0.1.0-draft.1",
  });
}

type RecordList = "modelBindings" | "dependencies" | "sources" | "fragments" | "regions" | "symbols" | "imports" | "references";

/** Preserve authored order and deliberate invalid records across all lists. */
export function appendRecords(input: ScopeInput, additions: Partial<Pick<ScopeInput, RecordList>>): ScopeInput {
  return structuredClone({
    ...input,
    modelBindings: [...input.modelBindings, ...(additions.modelBindings ?? [])],
    dependencies: [...input.dependencies, ...(additions.dependencies ?? [])],
    sources: [...input.sources, ...(additions.sources ?? [])],
    fragments: [...input.fragments, ...(additions.fragments ?? [])],
    regions: [...input.regions, ...(additions.regions ?? [])],
    symbols: [...input.symbols, ...(additions.symbols ?? [])],
    imports: [...input.imports, ...(additions.imports ?? [])],
    references: [...input.references, ...(additions.references ?? [])],
  });
}
