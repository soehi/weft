import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, copyFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { compile_json } from '../demo/planner.mjs';
import { chooseFile } from '../demo/files.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const temp = mkdtempSync(join(root, '_build', 'demo-check-'));
const cases = { chain: null, diamond: null, cycle: 'PLAN_CYCLE', 'type-mismatch': 'PLAN_TYPE_MISMATCH', 'missing-import': 'PLAN_UNBOUND_IMPORT' };
try {
  for (const [name, code] of Object.entries(cases)) {
    const text = readFileSync(join(root, 'examples/browser', `${name}.json`), 'utf8');
    const m = JSON.parse(text), bytes = Object.create(null);
    for (const c of m.components) {
      bytes[c.name] = Array.from(readFileSync(join(root, 'examples', c.path)));
      copyFileSync(join(root, 'examples', c.path), join(temp, c.path));
    }
    const result = JSON.parse(compile_json(text, JSON.stringify(bytes)));
    assert.equal(result.ok, code === null);
    if (code) assert.equal(result.diagnostic.code, code);
    else {
      writeFileSync(join(temp, 'manifest.json'), text);
      const cli = spawnSync('moon', ['run', 'src/cli', '--target', 'js', '--', 'plan', join(temp, 'manifest.json'), '--out', join(temp, 'plan.json')], { cwd: root, stdio: 'inherit' });
      if (cli.error) throw cli.error;
      assert.equal(cli.status, 0);
      assert.ok(Buffer.from(result.plan_json).equals(readFileSync(join(temp, 'plan.json'))));
    }
    console.log(`OK: browser bridge ${name}`);
  }
  for (const data of ['null', '{', '{"a":[-1]}', '{"a":[256]}', '{"a":[1.5]}', '{"a":[],"a":[]}']) assert.equal(JSON.parse(compile_json('{"components":[]}', data)).diagnostic.code, 'BROWSER_INPUT');
  assert.equal(chooseFile('C:\\not-readable\\reader.wasm', [{ name: 'reader.wasm' }]), 0);
  assert.equal(chooseFile('x.wasm', [{ name: 'x.wasm' }, { name: 'x.wasm' }]), -1);
  assert.equal(chooseFile('a/x.wasm', [{ name: 'x.wasm', webkitRelativePath: 'a/x.wasm' }, { name: 'x.wasm', webkitRelativePath: 'b/x.wasm' }]), 0);
  console.log('OK: five real cases, CLI byte parity, bridge input and logical path ambiguity');
} finally {
  assert.ok(resolve(temp).startsWith(resolve(root, '_build') + (process.platform === 'win32' ? '\\' : '/')));
  rmSync(temp, { recursive: true, force: true });
}
