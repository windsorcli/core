#!/usr/bin/env node
/**
 * Compat shim. The implementation moved to sync-reference.mjs (which
 * materializes both kustomize and terraform). This file is kept so the
 * dynamic import in windsorcli.github.io/scripts/vendor-docs.mjs at the
 * `scripts/sync-kustomize-reference.mjs` path continues to resolve.
 */
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

import { syncIntoCoreRepo } from './sync-reference.mjs';

export {
  hasMarkdownUnder,
  materializeKustomizeReadmes,
  materializeTerraformReadmes,
  syncIntoCoreRepo,
} from './sync-reference.mjs';

const entryFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === entryFile) {
  syncIntoCoreRepo();
}
