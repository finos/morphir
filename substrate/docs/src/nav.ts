/**
 * Docs sidebar navigation. Entries reference content-collection slugs
 * under `src/content/docs/` (without the leading slash). Sections with
 * `indent: 1` render with the indented treatment used for nested groups.
 */
export interface NavItem {
  slug: string;
  label: string;
}
export interface NavSection {
  name: string;
  items: NavItem[];
  indent?: 0 | 1;
}

export const NAV: NavSection[] = [
  {
    name: "Getting started",
    items: [
      { slug: "introduction", label: "Introduction" },
      { slug: "specs/vision", label: "Vision" },
      { slug: "getting-started", label: "Install & quickstart" },
    ],
  },
  {
    name: "Language",
    items: [{ slug: "specs/language", label: "Overview" }],
  },
  {
    name: "Concepts",
    indent: 1,
    items: [
      { slug: "specs/language/concepts/record", label: "Record" },
      { slug: "specs/language/concepts/choice", label: "Choice" },
      {
        slug: "specs/language/concepts/decision-table",
        label: "Decision Table",
      },
      { slug: "specs/language/concepts/operation", label: "Operation" },
      { slug: "specs/language/concepts/provenance", label: "Provenance" },
      { slug: "specs/language/concepts/type-class", label: "Type Class" },
    ],
  },
  {
    name: "Expressions",
    indent: 1,
    items: [
      { slug: "specs/language/expressions/boolean", label: "Boolean" },
      { slug: "specs/language/expressions/number", label: "Number" },
      { slug: "specs/language/expressions/ordering", label: "Ordering" },
      { slug: "specs/language/expressions/collection", label: "Collection" },
      { slug: "specs/language/expressions/string", label: "String" },
      { slug: "specs/language/expressions/date", label: "Date" },
    ],
  },
  {
    name: "Tools",
    items: [
      { slug: "specs/tools/cli", label: "CLI" },
      { slug: "specs/tools/packages", label: "Packages" },
    ],
  },
  {
    name: "Brand",
    items: [{ slug: "brand/design-system", label: "Design system" }],
  },
];
