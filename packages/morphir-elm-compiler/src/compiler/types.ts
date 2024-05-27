import { z } from "zod";
const parseDataUrl = require("data-urls");

export const DataUrl = z
  .string()
  .trim()
  .transform((val, ctx) => {
    const parsed = parseDataUrl(val);
    if (parsed == null) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Not a valid data url",
      });
      return z.NEVER;
    }
    return parsed;
  });

export type DataUrl = z.infer<typeof DataUrl>;

export const FileUrl = z
  .string()
  .trim()
  .url()
  .transform((val, ctx) => {
    if (!val.startsWith("file:")) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Not a valid file url",
      });
      return z.NEVER;
    }
    return new URL(val);
  });
export type FileUrl = z.infer<typeof FileUrl>;

const Includes = z.array(z.string()).optional();
export type Includes = z.infer<typeof Includes>;

const ElmCompilerOptions = z.object({
  projectDir: z.string(),
  output: z.string(),
  typesOnly: z.boolean(),
  indentJson: z.boolean(),
  include: Includes,
});

export type ElmCompilerOptions = z.infer<typeof ElmCompilerOptions>;

const DependencySettings = z.union([DataUrl, FileUrl, z.string().trim()]);
export type DependencySettings = z.infer<typeof DependencySettings>;

const Dependencies = z.array(DependencySettings).default([]);
export type Dependencies = z.infer<typeof Dependencies>;

export const DependencyConfig = z.object({
  dependencies: Dependencies,
  localDependencies: z.array(z.string()).default([]),
  includes: z.array(z.string()).default([]),
});

export type DependencyConfig = z.infer<typeof DependencyConfig>;

const VirtualFile = z.object({
  path: z.string(),
  content: z.string(),
});

export type VirtualFile = z.infer<typeof VirtualFile>;

const MorphirProjectManifest = z.object({
  name: z.string(),
  sourceDirectory: z.string(),
  dependencies: z.array(z.string()).optional(),
  localDependencies: z.array(z.string()).optional(),
  exposedModules: z.array(z.string()).optional().default([]),
});

export type MorphirProjectManifest = z.infer<typeof MorphirProjectManifest>;

export function parseIncludes(data: unknown) {
  return Includes.parse(data);
}
