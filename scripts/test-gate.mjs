// Both entry points must surface a real failing moon test, including its diagnostic.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
mkdirSync(join(root, '_build'), { recursive: true });
const temp = mkdtempSync(join(root, '_build', 'gate-failure-'));
try {
  mkdirSync(join(temp, 'scripts'));
  for (const file of ['check-backends.sh', 'check-backends.ps1', 'check-backends.mjs']) {
    copyFileSync(join(root, 'scripts', file), join(temp, 'scripts', file));
  }
  writeFileSync(join(temp, 'moon.mod'), 'name = "test/gate"\nsource = "src"\n');
  for (const pkg of ['graph', 'manifest', 'ir', 'plan', 'wac_adapter', 'exec_plan', 'api', 'cli']) {
    mkdirSync(join(temp, 'src', pkg), { recursive: true });
    writeFileSync(join(temp, 'src', pkg, 'moon.pkg'), '');
  }
  writeFileSync(join(temp, 'src', 'manifest', 'failure_test.mbt'), 'test "gate sentinel" { fail("intentional gate failure sentinel") }\n');
  const bash = process.env.WEFT_TEST_BASH || 'bash';
  for (const [command, args] of [
    [bash, ['scripts/check-backends.sh']],
    ['pwsh', ['-NoProfile', '-File', 'scripts/check-backends.ps1']],
  ]) {
    const r = spawnSync(command, args, { cwd: temp, encoding: 'utf8' });
    if (r.error) throw r.error;
    const log = r.stdout + r.stderr;
    assert.notEqual(r.status, 0, `${command} swallowed the failure`);
    assert.match(log, /intentional gate failure sentinel/, log);
    assert.doesNotMatch(log, /== plan/, 'gate continued after failed tests');
    console.log(`OK: ${command} propagated failing moon test and preserved its diagnostic`);
  }
} finally {
  assert.ok(resolve(temp).startsWith(resolve(root, '_build') + (process.platform === 'win32' ? '\\' : '/')));
  rmSync(temp, { recursive: true, force: true });
}
