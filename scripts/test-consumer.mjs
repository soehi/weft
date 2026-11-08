// Compile/run an independent MoonBit module importing only the public API.
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cwd = resolve(root, 'examples/consumer');
const expected = '{"plan_version":"0.2.0","instances":[{"name":"empty","path":"logical/path.wasm","order":0,"incoming":[]}],"wires":[],"resources":{"max_memory_pages":null,"quota":null},"plan_hash":"31496a9d30ad1eaf"}';
for (const target of ['native', 'wasm-gc', 'js']) {
  const build = spawnSync('moon', ['build', '.', '--target', target], { cwd, stdio: 'inherit' });
  if (build.error) throw build.error;
  assert.equal(build.status, 0, `consumer build failed: ${target}`);
  const run = spawnSync('moon', ['run', '.', '--target', target], { cwd, encoding: 'utf8' });
  if (run.error) throw run.error;
  assert.equal(run.status, 0, run.stdout + run.stderr);
  assert.equal(run.stdout.replace(/\r?\n$/, ''), expected);
  console.log(`OK: independent memory-only consumer (${target})`);
}
