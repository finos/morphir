import type { Declaration, Fragment, Source } from "./types";

/** Construct authored test data without resolving or validating declarations. */
export function constructFragment(sources: Source[], declarations: Declaration[]): Fragment {
  return structuredClone({ profile: "morphir-declarations/0.1.0-draft.1", sources, declarations });
}

/** Preserve authored order and deliberate duplicate IDs, without inference. */
export function appendDeclarations(fragment: Fragment, additions: Declaration[]): Fragment {
  return structuredClone({ ...fragment, declarations: [...fragment.declarations, ...additions] });
}
