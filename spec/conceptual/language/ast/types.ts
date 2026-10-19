/** Syntax and authored fixture records, without a claim of semantic validity. */
export type Span = {
  sourceId: string;
  start: number;
  end: number;
  unit: "utf8-byte";
};

export type Node = { id: string; span: Span; critical?: string[] };

export type Source = { id: string; revision: string; text: string; critical?: string[] };

export type TypeExpression = Node & (
  | { kind: "named"; path: string[]; arguments: TypeExpression[] }
  | { kind: "variable"; name: string }
  | { kind: "unit" }
  | { kind: "tuple"; elements: TypeExpression[] }
  | { kind: "record"; fields: Field[] }
  | { kind: "function"; input: TypeExpression; output: TypeExpression }
  | { kind: "union"; members: TypeExpression[] }
);

export type Field = Node & { name: string; type: TypeExpression };
export type Parameter = Node & { name: string; type: TypeExpression };
export type TypeBinder = Node & { name: string; origin: "declared" | "implicit" };
export type Constructor = Node & { name: string; arguments: TypeExpression[] };

export type Declaration = Node & {
  name: string;
  typeParameters: TypeBinder[];
} & (
  | { kind: "alias"; value: TypeExpression }
  | { kind: "opaque-alias"; representation: TypeExpression }
  | {
    kind: "custom";
    constructors: Constructor[];
    constructorAccess: "module-policy" | "defining-module";
  }
  | { kind: "function-spec"; inputs: Parameter[]; output: TypeExpression }
);

export type Fragment = {
  profile: "morphir-declarations/0.1.0-draft.1";
  sources: Source[];
  declarations: Declaration[];
  critical?: string[];
};
