/** Test-data construction, not a conceptual validator or an IRUnit codec. */
type Records = {
  sources: unknown[];
  entities: unknown[];
  relationships: unknown[];
  capabilities: unknown[];
};

/** Preserve authored order and deliberate invalid records, including duplicate IDs. */
export function appendRecords<G extends Records>(
  graph: G,
  additions: Partial<Pick<G, keyof Records>>,
): G {
  return structuredClone({
    ...graph,
    sources: [...graph.sources, ...(additions.sources ?? [])],
    entities: [...graph.entities, ...(additions.entities ?? [])],
    relationships: [...graph.relationships, ...(additions.relationships ?? [])],
    capabilities: [...graph.capabilities, ...(additions.capabilities ?? [])],
  });
}

/**
 * Describe how a test adapter should construct the existing rich carrier.
 * All declarations and dependency closure come from the fixture author.
 * Ion-only data is supplied separately as literal assets by the case manifest.
 */
export function checkpointRecipe<G, M>(
  graph: G,
  context: {
    unitId: string;
    packageName: string;
    modules: M;
    dependencies?: Record<string, unknown>;
    provenance?: Record<string, unknown>[];
  },
) {
  return structuredClone({
    unitId: context.unitId,
    ir: {
      formatVersion: 4,
      distribution: {
        Specs: {
          packageName: context.packageName,
          dependencies: context.dependencies ?? {},
          spec: { modules: context.modules },
        },
      },
    },
    metadata: [{ nodeId: `unit:${context.unitId}`, data: graph }],
    annotations: ["morphir_pipeline"],
    provenance: context.provenance ?? [],
  });
}
