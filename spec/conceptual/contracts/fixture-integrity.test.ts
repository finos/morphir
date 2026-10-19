import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";

// Integrity of an independently authored reference corpus, not a contract checker.
// No expected outcome here is computed by evaluating a clause. The checks below
// verify that the authored records are complete, resolved and coherent.
const bytes = (path: string) => readFileSync(new URL(path, import.meta.url));
const json = (path: string) => JSON.parse(bytes(path).toString("utf8"));
const sha256 = (data: string | Uint8Array) => createHash("sha256").update(data).digest("hex");

const OUTCOMES = ["satisfied", "violated", "not_applicable", "invalid", "inconclusive", "unsupported", "execution-error"];
const CLAUSE_KINDS = ["refinement", "invariant", "precondition", "postcondition", "frame"];
const INT_LEXEME = /^(0|-?[1-9][0-9]*)$/;

describe("typed contracts reference corpus integrity", () => {
  test("the contract, corpus, environment and byte inventory are published together", () => {
    for (const path of ["contract.html", "cases.json", "environment.json", "assets.json"])
      expect(existsSync(new URL(path, import.meta.url)), path).toBe(true);
  });

  test("reviewed bytes match the complete inventory and all JSON parses", () => {
    const manifest = json("assets.json");
    expect(manifest.assets.map((asset: any) => asset.path).sort()).toEqual(["cases.json", "contract.html", "environment.json"]);
    for (const asset of manifest.assets) {
      const data = bytes(asset.path);
      expect(data.byteLength, asset.path).toBe(asset.bytes);
      expect(sha256(data), asset.path).toBe(asset.sha256);
      if (asset.path.endsWith(".json")) JSON.parse(data.toString("utf8"));
    }
  });

  test("the environment defines one coherent contract and clause graph", () => {
    const environment = json("environment.json");
    const corpus = json("cases.json");
    expect(corpus.profile).toBe("morphir-contracts/0.1.0-draft.1");
    expect(corpus.status).toBe("reference-only");
    expect(environment.profile).toBe(corpus.profile);
    expect(environment.recordVersion).toBe("0.1.0-draft.1");
    expect(environment.model).toEqual({ id: "urn:example:model:rentals", revision: "m1" });
    for (const [key, contract] of Object.entries<any>(environment.contracts)) {
      expect(contract.operation.inputs.length, key).toBeGreaterThan(0);
      for (const clauseKey of contract.clauses) {
        expect(Object.hasOwn(environment.clauses, clauseKey), `${key}: ${clauseKey}`).toBe(true);
        expect(environment.clauses[clauseKey].contract, `${key}: ${clauseKey}`).toBe(key);
      }
      for (const input of contract.operation.inputs)
        expect(Object.hasOwn(environment.types, input.type), `${key}: ${input.type}`).toBe(true);
      expect(Object.hasOwn(environment.types, contract.operation.result), `${key}: result`).toBe(true);
    }
    for (const [key, clause] of Object.entries<any>(environment.clauses)) {
      expect(CLAUSE_KINDS, key).toContain(clause.kind);
      expect(clause.id.startsWith("urn:example:contracts:clause:"), key).toBe(true);
      expect(clause.text.length, key).toBeGreaterThan(0);
      for (const binder of clause.binders) {
        expect(["self", "argument", "result"], `${key}: ${binder.name}`).toContain(binder.role);
        expect(Object.hasOwn(environment.types, binder.type), `${key}: ${binder.type}`).toBe(true);
      }
      // Every resultValue use is declared as the match payload binder with its payload type.
      if (JSON.stringify(clause.expression).includes('"resultValue"')) {
        expect(clause.matchBinder, key).toEqual({ name: "resultValue", role: "constructor-payload", type: "loan" });
      }
      if (clause.kind === "refinement") expect(Object.hasOwn(environment.types, clause.subjectType), key).toBe(true);
      if (clause.kind === "invariant") expect(Object.hasOwn(environment.types, clause.subjectType), key).toBe(true);
    }
    for (const [key, clause] of Object.entries<any>(environment.clauses)) {
      if (clause.contract) expect(environment.contracts[clause.contract].clauses, key).toContain(key);
    }
    for (const [key, type] of Object.entries<any>(environment.types)) {
      if (type.kind === "refined") expect(environment.clauses[type.refinementClause].kind, key).toBe("refinement");
      if (type.invariantClause) expect(environment.clauses[type.invariantClause].kind, key).toBe("invariant");
    }
    for (const code of Object.keys(environment.diagnostics)) expect(code.startsWith("contracts."), code).toBe(true);
  });

  test("cases have unique identities, resolved references and coherent expected observations", () => {
    const corpus = json("cases.json");
    const environment = json(corpus.environment);
    const ids = new Set<string>();
    expect(corpus.cases.length).toBe(42);
    for (const item of corpus.cases) {
      expect(ids.has(item.id), item.id).toBe(false);
      ids.add(item.id);
      expect(item.description.length, item.id).toBeGreaterThan(0);
      expect(OUTCOMES, item.id).toContain(item.expected.outcome);
      expect("candidateType" in item.input, item.id).toBe(false);
      if (item.input.mode === "supplied-result") {
        expect(Object.hasOwn(environment.contracts, item.input.contract), item.id).toBe(true);
      } else if (item.input.mode === "typed-value") {
        // An unknown type is a defined slot only for the unsupported case.
        if (item.expected.outcome === "unsupported")
          expect(Object.hasOwn(environment.types, item.input.type), item.id).toBe(false);
        else expect(Object.hasOwn(environment.types, item.input.type), item.id).toBe(true);
        expect("value" in item.input, item.id).toBe(true);
      } else {
        throw new Error(`${item.id}: unknown mode ${item.input.mode}`);
      }
      for (const clause of item.expected.clauses) {
        expect(Object.hasOwn(environment.clauses, clause.clause), `${item.id}: ${clause.clause}`).toBe(true);
        expect(OUTCOMES, `${item.id}: ${clause.clause}`).toContain(clause.observation);
      }
      // Context must resolve exactly, unless the case expects a revision failure.
      const codesPre = (item.expected.diagnostics ?? []).map((d: any) => d.code);
      if (!codesPre.includes("contracts.revision_unavailable")) {
        expect(item.input.context.model).toEqual(environment.model);
        if (item.input.contract) expect(item.input.context.contractRevision).toBe(environment.contracts[item.input.contract].revision);
      }
      // A supplied-result case stopped before postconditions says so.
      if (item.input.mode === "supplied-result" && !["satisfied", "violated"].includes(item.expected.outcome))
        expect(item.expected.postconditionsEvaluated).toBe(false);
      if (item.input.mode === "typed-value" && environment.types[item.input.type]) {
        const type = environment.types[item.input.type];
        const clauseKey = type.refinementClause ?? type.invariantClause;
        if (clauseKey) expect(item.expected.clauses.map((c: any) => c.clause)).toEqual([clauseKey]);
      }
      // Diagnostic paths resolve as RFC 6901 pointers into the case input:
      // present for a rejected value, absent for a missing one.
      const resolvePointer = (pointer: string): boolean => {
        if (pointer === "") return true;
        let value: unknown = item.input;
        for (const raw of pointer.slice(1).split("/")) {
          const key = raw.replaceAll("~1", "/").replaceAll("~0", "~");
          if (value === null || typeof value !== "object" || !Object.hasOwn(value, key)) return false;
          value = (value as Record<string, unknown>)[key];
        }
        return true;
      };
      for (const diagnostic of item.expected.diagnostics ?? []) {
        if (diagnostic.code === "contracts.invalid_input") expect(resolvePointer(diagnostic.path)).toBe(true);
        if (diagnostic.code === "contracts.missing_input" || diagnostic.code === "contracts.missing_result")
          expect(resolvePointer(diagnostic.path)).toBe(false);
      }
      const codes = (item.expected.diagnostics ?? []).map((d: any) => d.code);
      for (const diagnostic of item.expected.diagnostics ?? []) {
        expect(Object.hasOwn(environment.diagnostics, diagnostic.code), `${item.id}: ${diagnostic.code}`).toBe(true);
        expect(diagnostic.path === "" || diagnostic.path.startsWith("/"), `${item.id}: ${diagnostic.path}`).toBe(true);
      }
      // Authored coherence per outcome, not a clause evaluation.
      const observations = item.expected.clauses.map((clause: any) => clause.observation);
      const clauseKeys = item.expected.clauses.map((clause: any) => clause.clause).sort();
      const contractClauses = item.input.contract ? [...environment.contracts[item.input.contract].clauses].sort() : [];
      const preClauses = contractClauses.filter((k: string) => environment.clauses[k].kind === "precondition");
      switch (item.expected.outcome) {
        case "satisfied":
        case "violated": {
          expect(observations.every((o: string) => o === "satisfied" || o === "violated")).toBe(true);
          if (item.input.mode === "supplied-result") expect(clauseKeys).toEqual(contractClauses);
          if (item.expected.outcome === "satisfied") expect(observations.every((o: string) => o === "satisfied")).toBe(true);
          if (item.expected.outcome === "violated") expect(observations).toContain("violated");
          break;
        }
        case "not_applicable":
          expect(item.expected.postconditionsEvaluated).toBe(false);
          expect(clauseKeys).toEqual(preClauses);
          expect(observations.every((o: string) => o === "not_applicable")).toBe(true);
          break;
        case "invalid":
          expect(codes).toContain("contracts.invalid_input");
          // A clause evaluated before the failed admission can be retained: a satisfied
          // precondition, or the refinement/invariant that rejected the value.
          for (const clause of item.expected.clauses) {
            const kind = environment.clauses[clause.clause].kind;
            if (kind === "precondition") expect(clause.observation).toBe("satisfied");
            else expect(clause.observation).toBe("invalid");
          }
          if ("postconditionsEvaluated" in item.expected) expect(item.expected.postconditionsEvaluated).toBe(false);
          break;
        case "inconclusive":
          expect(codes.some((c: string) => ["contracts.missing_input", "contracts.missing_result", "contracts.revision_unavailable"].includes(c))).toBe(true);
          expect(item.expected.clauses).toEqual([]);
          break;
        case "unsupported":
          expect(codes.some((c: string) => c === "contracts.unsupported_semantics" || c === "contracts.unsupported_type")).toBe(true);
          expect(observations.every((o: string) => o === "unsupported")).toBe(true);
          break;
        case "execution-error": {
          expect(item.expected.detail?.kind).toBe("exhaustion");
          expect(codes).toContain("contracts.execution_exhausted");
          expect(item.expected.diagnostics.find((d: any) => d.code === "contracts.execution_exhausted")?.path)
            .toBe(`/budget/${item.expected.detail.limit}`);
          break;
        }
      }
    }
    // Coverage groups are exact indexes, computed from the cases themselves.
    const byOutcome = new Map<string, string[]>();
    for (const item of corpus.cases) byOutcome.set(item.expected.outcome, [...(byOutcome.get(item.expected.outcome) ?? []), item.id]);
    for (const outcome of OUTCOMES) expect(corpus.coverage[outcome], outcome).toEqual(byOutcome.get(outcome));
    expect(corpus.coverage["supplied-result"]).toEqual(corpus.cases.filter((c: any) => c.input.mode === "supplied-result").map((c: any) => c.id));
    expect(corpus.coverage.frame).toEqual(
      corpus.cases.filter((c: any) => c.expected.clauses.some((cl: any) => cl.clause === "return-frame")).map((c: any) => c.id),
    );
    expect(Object.keys(corpus.coverage).sort()).toEqual([...OUTCOMES, "exact-int", "frame", "supplied-result"].sort());
    for (const outcome of OUTCOMES) expect(byOutcome.get(outcome)?.length ?? 0, outcome).toBeGreaterThan(0);
    // exact-int: precision-sensitive cases (satisfied or violated) that use a 16+ digit lexeme.
    const hasLargeLexeme = (value: unknown): boolean =>
      (typeof value === "string" && /^-?[0-9]{16,}$/.test(value)) ||
      (value !== null && typeof value === "object" && Object.values(value).some(hasLargeLexeme));
    expect(corpus.coverage["exact-int"]).toEqual(
      corpus.cases
        .filter((c: any) => ["satisfied", "violated"].includes(c.expected.outcome) && hasLargeLexeme(c.input))
        .map((c: any) => c.id),
    );
  });

  test("every Int position holds a canonical lexeme or belongs to an invalid case", () => {
    const corpus = json("cases.json");
    const environment = json("environment.json");
    // Walk typed value positions using the environment type inventory.
    const badLexemes: string[] = [];
    const checkValue = (value: unknown, typeKey: string, at: string): void => {
      const type = environment.types[typeKey];
      if (!type) return;
      if (typeKey === "int" || type.kind === "refined") {
        if (typeof value === "string" && !INT_LEXEME.test(value)) badLexemes.push(at);
        if (typeof value !== "string" && value !== undefined) badLexemes.push(at);
        return;
      }
      if (type.kind === "record" && value && typeof value === "object") {
        for (const [field, fieldType] of Object.entries<string>(type.fields)) checkValue((value as any)[field], fieldType, `${at}/${field}`);
        return;
      }
      if (type.kind === "custom" && value && typeof value === "object") {
        // Exactly one member: its name is the constructor, its value is the payload (or null).
        const names = Object.keys(value as object);
        if (names.length === 1 && Object.hasOwn(type.constructors, names[0]!)) {
          const payload = type.constructors[names[0]!];
          if (payload) checkValue((value as any)[names[0]!], payload, `${at}/${names[0]}`);
        }
      }
    };
    for (const item of corpus.cases) {
      const before = badLexemes.length;
      if (item.input.mode === "supplied-result" && item.input.contract && environment.contracts[item.input.contract]) {
        const contract = environment.contracts[item.input.contract];
        for (const input of contract.operation.inputs) checkValue(item.input.inputs?.[input.name], input.type, `${item.id}/inputs/${input.name}`);
        if ("candidate" in item.input) checkValue(item.input.candidate, contract.operation.result, `${item.id}/candidate`);
      }
      if (item.input.mode === "typed-value") checkValue(item.input.value, item.input.type, `${item.id}/value`);
      // A malformed lexeme is allowed only where admission rejects it (invalid), or
      // where an earlier phase stops the check before that value is admitted:
      // a false precondition, or admission exhaustion in the inputs (candidate slot only).
      const fresh = badLexemes.slice(before);
      if (fresh.length > 0 && item.expected.outcome !== "invalid")
        expect(
          (item.expected.outcome === "not_applicable" || item.expected.outcome === "execution-error") &&
            fresh.every((at) => at.endsWith("/candidate")),
        ).toBe(true);
    }
    expect(badLexemes.length).toBeGreaterThan(0);
    expect(corpus.cases.find((c: any) => c.id === "contracts-0014").input.inputs.loan.outstanding).toBe("123456789012345678901234567890");
    expect(corpus.cases.find((c: any) => c.id === "contracts-0015").input.inputs.outstanding).toBe("9007199254740993");
  });

  test("the published HTML retains the template head and links every section", () => {
    const html = bytes("contract.html").toString("utf8");
    const head = html.match(/<head>[\s\S]*?<\/head>/)?.[0] ?? "";
    expect(sha256(head)).toBe("c9c790b80f3bfed935849f5c58a628baa1d7d0f80034459242e624528825f7da");
    const rendered = html.replace(/<!--[\s\S]*?-->/g, "");
    const ids = [...rendered.matchAll(/<section id="([^"]+)"/g)].map((match) => match[1]);
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
    const toc = rendered.match(/<nav class="toc"[^>]*>([\s\S]*?)<\/nav>/)?.[1] ?? "";
    for (const id of ids) expect(toc).toContain(`href="#${id}"`);
  });
});
