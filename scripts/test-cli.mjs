// Exercise the actual executable from a foreign working directory.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, copyFileSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname, resolve, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const target = process.argv[2] || 'native';
const temp = mkdtempSync(join(root, '_build', 'weft CLI spaces-🧵-'));
const artifact = join(root, '_build', target, 'debug', 'build', 'cli', 'cli');
const command = target === 'native' ? artifact + '.exe' : target === 'js' ? process.execPath : 'moonrun';
const prefix = target === 'native' ? [] : target === 'js' ? [artifact + '.js'] : [artifact + '.wasm', '--'];
let count = 0;
function cli(args, ok = true) {
  const r = spawnSync(command, [...prefix, ...args], { cwd: temp, encoding: 'utf8' });
  if (r.error) throw r.error;
  assert.equal(r.status, ok ? 0 : 1, `${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
  count++;
  return r.stdout;
}
try {
  assert.equal(cli(['--version']).trim(), 'weft 0.3.0 (plan 0.2.0)');
  mkdirSync(join(temp, 'components'));
  mkdirSync(join(temp, 'output files'));
  copyFileSync(join(root, 'examples', 'reader.wasm'), join(temp, 'components', 'custom reader.wasm'));
  writeFileSync(join(temp, 'source.wac'), 'package app:main; let r = new ns:reader@1.0.0 {}; export r as "reader";');
  const dep = 'ns:reader@1.0.0=components/custom reader.wasm';
  cli(['convert', 'source.wac', '--dep', dep, '--out', 'output files/manifest.json']);
  const converted = readFileSync(join(temp, 'output files', 'manifest.json'), 'utf8');
  const m = JSON.parse(converted);
  assert.ok(isAbsolute(m.components[0].path));
  assert.equal(readFileSync(m.components[0].path).compare(readFileSync(join(root, 'examples', 'reader.wasm'))), 0);
  const plan = JSON.parse(cli(['plan', 'output files/manifest.json']));
  assert.equal(plan.instances[0].name, 'reader');
  const stdout = JSON.parse(cli(['convert', 'source.wac', '--dep', dep]));
  assert.deepEqual(stdout, m);
  cli(['convert', 'source.wac', '--dep', `ns:reader@1.0.0=${join(temp, 'components', 'custom reader.wasm')}`]);
  cli(['plan', join(root, 'examples', 'chain.json')]);
  assert.match(cli(['emit-wac', join(root, 'examples', 'chain.json')], false), /cannot preserve resource limits/);
  const plain = JSON.parse(readFileSync(join(root, 'examples', 'chain.json'), 'utf8'));
  delete plain.resources;
  plain.components.reverse();
  writeFileSync(join(temp, 'plain.json'), JSON.stringify(plain));
  cli(['emit-wac', 'plain.json', '--out', 'output files/chain.wac']);
  cli(['convert', 'output files/chain.wac',
    '--dep', `weft:reader=${join(root, 'examples', 'reader.wasm')}`,
    '--dep', `weft:filter=${join(root, 'examples', 'filter.wasm')}`,
    '--dep', `weft:sink=${join(root, 'examples', 'sink.wasm')}`,
    '--out', 'output files/roundtrip.json']);
  cli(['plan', 'output files/roundtrip.json']);
  // Complete-plan checks must fail at the actual CLI boundary as well.
  const chain = JSON.parse(readFileSync(join(root, 'examples', 'chain.json'), 'utf8'));
  for (const c of chain.components) c.path = join(root, 'examples', c.path);
  const incomplete = structuredClone(chain);
  incomplete.wires = incomplete.wires.filter(w => w.to !== 'sink.in');
  writeFileSync(join(temp, 'unbound.json'), JSON.stringify(incomplete));
  assert.match(cli(['plan', 'unbound.json'], false), /unbound import `sink.in`/);
  const duplicate = structuredClone(chain);
  duplicate.wires.push(duplicate.wires[0]);
  writeFileSync(join(temp, 'duplicate.json'), JSON.stringify(duplicate));
  assert.match(cli(['plan', 'duplicate.json'], false), /duplicate binding/);
  // Artifact contract: UTF-8, no BOM or trailing newline; stdout is a transport line.
  cli(['plan', join(root, 'examples', 'chain.json'), '--out', 'current-plan.json']);
  const artifactBytes = readFileSync(join(temp, 'current-plan.json'));
  assert.ok(!artifactBytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])));
  assert.equal(artifactBytes.at(-1), 0x7d);
  assert.equal(JSON.parse(artifactBytes).plan_version, '0.2.0');
  writeFileSync(join(temp, 'bad-utf8.json'), Buffer.from([0x7b, 0xff, 0x7d]));
  cli(['plan', 'bad-utf8.json'], false);
  writeFileSync(join(temp, 'bom.json'), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('{"components":[]}')]));
  cli(['plan', 'bom.json'], false);
  const invalid = [
    ['--version', 'extra'], ['unknown'], ['unknown', 'plan', 'x'], ['plan'], ['plan', 'x', 'extra'],
    ['plan', 'x', '--unknown'], ['plan', 'x', '--out'], ['plan', 'x', '--out', '--out'],
    ['plan', 'x', '--out', 'a', '--out', 'b'], ['plan', 'x', '--dep', 'ns:p=x'],
    ['convert', 'source.wac', '--dep'], ['convert', 'source.wac', '--dep', 'broken'],
    ['convert', 'source.wac', '--dep', 'ns:p='], ['convert', 'source.wac', '--dep', 'ns:p@=x'],
    ['convert', 'source.wac', '--dep', dep, '--dep', dep], ['help', 'extra'],
    ['run', join(root, 'examples', 'chain.json')],
  ];
  for (const args of invalid) assert.match(cli(args, false), /error:/);
  assert.match(cli(['run', 'nonexistent.json'], false), /unsupported/);
  console.log(`OK: ${count} CLI checks (${target}), including convert → plan from a foreign directory`);
} finally {
  rmSync(temp, { recursive: true, force: true });
}
