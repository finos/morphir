import type { BuildConfig } from 'bun';

/** All handwritten JavaScript outputs pass Bun's checker before publication. */
export async function checkedBuild(config: BuildConfig) {
  return Bun.build({ target: 'browser', format: 'esm', env: 'disable', sourcemap: 'linked', ...config, check: true });
}
