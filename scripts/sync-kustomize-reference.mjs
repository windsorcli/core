#!/usr/bin/env node
/**
 * Materialize each kustomize stack README.md into docs/reference/kustomize/
 * for windsorcli.github.io ingest.
 *
 * Run from repo root: node scripts/sync-kustomize-reference.mjs
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

function walkReadmes(dir, acc = []) {
  for (const ent of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, ent.name);
    if (ent.isDirectory()) walkReadmes(p, acc);
    else if (ent.name === 'README.md') acc.push(p);
  }
  return acc;
}

function titleFromReadme(kRoot, readmePath) {
  const body = readFileSync(readmePath, 'utf8');
  const m = body.match(/^---\s*[\s\S]*?title:\s*(.+?)\s*$/m);
  if (m) return m[1].replace(/^["']|["']$/g, '').trim();
  const h1 = body.replace(/^---[\s\S]*?---\s*/, '').match(/^#\s+(.+)/m);
  if (h1) return h1[1].trim();
  const rel = relative(kRoot, dirname(readmePath));
  if (!rel || rel === '.') return 'Kustomize (overview)';
  const parts = rel.split(/[/\\]/);
  return parts[parts.length - 1].replace(/-/g, ' ');
}

function ensureFrontmatter(kRoot, srcPath, body) {
  if (body.trimStart().startsWith('---')) return body;
  const title = titleFromReadme(kRoot, srcPath);
  const rel = relative(kRoot, dirname(srcPath)) || '.';
  const desc = `Operator notes from kustomize/${rel} (generated; edit README in kustomize/).`;
  return `---\ntitle: ${JSON.stringify(title)}\ndescription: ${JSON.stringify(desc)}\n---\n\n${body}`;
}

function destPathForReadme(kRoot, outRoot, readmePath) {
  const parent = dirname(readmePath);
  const rel = relative(kRoot, parent);
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
      const p = join(d, ent.name);
      if (ent.isDirectory()) stack.push(p);
      else if (ent.name.endsWith('.md')) return true;
    }
  }
  return false;
}

/**
 * @param {string} kustomizeRoot absolute path to …/kustomize
 * @param {string} outputKustomizeDir absolute path to output tree (…/docs/reference/kustomize or vendored equivalent)
 * @returns {number} files written
 */
export function materializeKustomizeReadmes(kustomizeRoot, outputKustomizeDir) {
  if (!existsSync(kustomizeRoot)) return 0;

  mkdirSync(outputKustomizeDir, { recursive: true });
  const readmes = walkReadmes(kustomizeRoot);
  let n = 0;
  for (const readme of readmes) {
    const raw = readFileSync(readme, 'utf8');
    const out = destPathForReadme(kustomizeRoot, outputKustomizeDir, readme);
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, ensureFrontmatter(kustomizeRoot, readme, raw), 'utf8');
    n += 1;
  }
  return n;
}

/** Default: sync into this repo’s docs/reference/kustomize (destructive refresh). */
export function syncIntoCoreRepo(coreRepoRoot = join(__dirname, '..')) {
  const kRoot = join(coreRepoRoot, 'kustomize');
  const outRoot = join(coreRepoRoot, 'docs', 'reference', 'kustomize');

  if (!existsSync(kRoot)) {
    console.error('sync-kustomize-reference: no kustomize/ directory');
    process.exit(1);
  }

  rmSync(outRoot, { recursive: true, force: true });
  mkdirSync(outRoot, { recursive: true });

  const readmes = walkReadmes(kRoot);
  if (readmes.length === 0) {
    console.warn('sync-kustomize-reference: no README.md under kustomize/');
    return 0;
  }

  for (const readme of readmes) {
    const raw = readFileSync(readme, 'utf8');
    const out = destPathForReadme(kRoot, outRoot, readme);
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, ensureFrontmatter(kRoot, readme, raw), 'utf8');
    console.log(
      `sync-kustomize-reference: ${relative(coreRepoRoot, readme)} → ${relative(coreRepoRoot, out)}`,
    );
  }
  console.log(
    `sync-kustomize-reference: wrote ${readmes.length} file(s) under docs/reference/kustomize/`,
  );
  return readmes.length;
}

const entryFile = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === entryFile) {
  syncIntoCoreRepo();
}
