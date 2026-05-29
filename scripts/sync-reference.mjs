#!/usr/bin/env node
/**
 * Materialize each kustomize and terraform README.md into docs/reference/
 * for windsorcli.github.io ingest.
 *
 * Run from repo root: node scripts/sync-reference.mjs
 *
 * Output layout:
 *   kustomize/<add-on>/README.md          → docs/reference/kustomize/<add-on>.md
 *   terraform/<category>/README.md        → docs/reference/terraform/<category>.md
 *   terraform/<category>/<module>/README  → docs/reference/terraform/<category>/<module>.md
 *
 * Also imported by windsorcli.github.io/scripts/vendor-docs.mjs (keep mapping logic in sync).
 */
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Skip dot-prefixed directories (.terraform/, .git/, .windsor/, etc.)
function walkReadmes(dir, acc = []) {
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    if (ent.name.startsWith('.')) continue;
    const p = join(dir, ent.name);
    if (ent.isDirectory()) walkReadmes(p, acc);
    else if (ent.name === 'README.md') acc.push(p);
  }
  return acc;
}

function titleFromReadme(srcRoot, readmePath, fallbackPrefix) {
  const body = readFileSync(readmePath, 'utf8');
  const m = body.match(/^---\s*[\s\S]*?title:\s*(.+?)\s*$/m);
  if (m) return m[1].replace(/^["']|["']$/g, '').trim();
  const h1 = body.replace(/^---[\s\S]*?---\s*/, '').match(/^#\s+(.+)/m);
  if (h1) return h1[1].trim();
  const rel = relative(srcRoot, dirname(readmePath));
  if (!rel || rel === '.') return `${fallbackPrefix} (overview)`;
  const parts = rel.split(/[/\\]/);
  return parts[parts.length - 1].replace(/-/g, ' ');
}

function ensureFrontmatter(srcRoot, srcPath, body, sourceLabel) {
  if (body.trimStart().startsWith('---')) return body;
  const title = titleFromReadme(srcRoot, srcPath, sourceLabel);
  const rel = relative(srcRoot, dirname(srcPath)) || '.';
  const desc = `Operator notes from ${sourceLabel.toLowerCase()}/${rel} (generated; edit README in ${sourceLabel.toLowerCase()}/).`;
  return `---\ntitle: ${JSON.stringify(title)}\ndescription: ${JSON.stringify(desc)}\n---\n\n${body}`;
}

function destPathForReadme(srcRoot, outRoot, readmePath) {
  const parent = dirname(readmePath);
  const rel = relative(srcRoot, parent);
  if (!rel || rel === '.') {
    return join(outRoot, 'index.md');
  }
  const segments = rel.split(/[/\\]/).filter(Boolean);
  const base = segments.pop();
  const sub = segments;
  return join(outRoot, ...sub, `${base}.md`);
}

export function hasMarkdownUnder(dir) {
  if (!existsSync(dir)) return false;
  const stack = [dir];
  while (stack.length) {
    const d = stack.pop();
    for (const ent of readdirSync(d, { withFileTypes: true })) {
      if (ent.name.startsWith('.')) continue;
      const p = join(d, ent.name);
      if (ent.isDirectory()) stack.push(p);
      else if (ent.name.endsWith('.md')) return true;
    }
  }
  return false;
}

/**
 * Generic materializer used by both kustomize and terraform syncs.
 * @param {string} srcRoot absolute path to source tree (e.g. .../kustomize, .../terraform)
 * @param {string} outRoot absolute path to output tree (e.g. .../docs/reference/kustomize)
 * @param {string} sourceLabel label for synthesized frontmatter ("Kustomize" / "Terraform")
 * @returns {number} files written
 */
function materializeReadmes(srcRoot, outRoot, sourceLabel) {
  if (!existsSync(srcRoot)) return 0;
  mkdirSync(outRoot, { recursive: true });
  const readmes = walkReadmes(srcRoot);
  let n = 0;
  for (const readme of readmes) {
    const raw = readFileSync(readme, 'utf8');
    const out = destPathForReadme(srcRoot, outRoot, readme);
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, ensureFrontmatter(srcRoot, readme, raw, sourceLabel), 'utf8');
    n += 1;
  }
  return n;
}

export function materializeKustomizeReadmes(kustomizeRoot, outputDir) {
  return materializeReadmes(kustomizeRoot, outputDir, 'Kustomize');
}

export function materializeTerraformReadmes(terraformRoot, outputDir) {
  return materializeReadmes(terraformRoot, outputDir, 'Terraform');
}

function syncTree(repoRoot, srcName, sourceLabel) {
  const srcRoot = join(repoRoot, srcName);
  const outRoot = join(repoRoot, 'docs', 'reference', srcName);

  if (!existsSync(srcRoot)) {
    console.error(`sync-reference: no ${srcName}/ directory`);
    return 0;
  }

  rmSync(outRoot, { recursive: true, force: true });
  mkdirSync(outRoot, { recursive: true });

  const readmes = walkReadmes(srcRoot);
  if (readmes.length === 0) {
    console.warn(`sync-reference: no README.md under ${srcName}/`);
    return 0;
  }

  for (const readme of readmes) {
    const raw = readFileSync(readme, 'utf8');
    const out = destPathForReadme(srcRoot, outRoot, readme);
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, ensureFrontmatter(srcRoot, readme, raw, sourceLabel), 'utf8');
    console.log(
      `sync-reference: ${relative(repoRoot, readme)} → ${relative(repoRoot, out)}`,
    );
  }
  console.log(
    `sync-reference: wrote ${readmes.length} file(s) under docs/reference/${srcName}/`,
  );
  return readmes.length;
}

/** Default: sync both kustomize/ and terraform/ into this repo's docs/reference/ tree. */
export function syncIntoCoreRepo(coreRepoRoot = join(__dirname, '..')) {
  const k = syncTree(coreRepoRoot, 'kustomize', 'Kustomize');
  const t = syncTree(coreRepoRoot, 'terraform', 'Terraform');
  return k + t;
}

const entryFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === entryFile) {
  syncIntoCoreRepo();
}
