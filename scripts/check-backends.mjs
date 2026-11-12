// Shared gate: preserve raw diagnostics and each command's exit status.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
mkdirSync(join(root, '_build'), { recursive: true });
const out = mkdtempSync(join(root, '_build', 'weft-gate-'));
function run(command, args) {
  const r = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (r.error) throw r.error;
  if (r.status !== 0) throw Object.assign(new Error(`${command} failed (${r.status ?? r.signal})`), { status: r.status || 1 });
}
try {
  const targets = ['native', 'wasm-gc', 'js'];
  for (const target of targets) {
    console.log(`== test (${target}) ==`);
    run('moon', ['test', 'src/graph', 'src/manifest', 'src/ir', 'src/plan', 'src/wac_adapter', 'src/exec_plan', 'src/api', 'src/cli', '--target', target]);
    console.log(`== D0 feasibility probes (${target}) ==`);
    run('moon', ['test', 'src/probes/instance', 'src/probes/digest', '--target', target]);
  }
  run('moon', ['run', 'src/tools/make_fixtures', '--target', 'native', '--', 'examples']);
  for (const target of targets) {
    console.log(`== plan (${target}) ==`);
    run('moon', ['run', 'src/cli', '--target', target, '--', 'plan', 'examples/chain.json', '--out', join(out, `${target}.json`)]);
    run('moon', ['run', 'src/cli', '--target', target, '--', 'plan', 'examples/format.json', '--out', join(out, `format-${target}.json`)]);
    run('node', ['scripts/test-cli.mjs', target]);
  }
  const golden = readFileSync(join(out, 'native.json'));
  if (!golden.equals(readFileSync(join(root, 'docs', 'fixtures', 'plan-v0.2.0.json')))) throw new Error('v0.2.0 golden artifact differs');
  for (const target of targets.slice(1)) {
    if (!golden.equals(readFileSync(join(out, `${target}.json`)))) throw new Error(`plan differs: ${target}`);
  }
  const formatGolden = readFileSync(join(root, 'docs', 'fixtures', 'format-plan-v0.2.0.json'));
  for (const target of targets) {
    if (!formatGolden.equals(readFileSync(join(out, `format-${target}.json`)))) throw new Error(`format golden differs: ${target}`);
  }
  run('node', ['scripts/test-consumer.mjs']);
  console.log('OK: all three backends produced byte-identical plans, including Unicode/escaping/integer boundaries');
} catch (e) {
  console.error(e.message);
  process.exitCode = e.status || 1;
} finally {
  rmSync(out, { recursive: true, force: true });
}
