// Actual D2 commands plus independent Node SHA-256 recomputation. Mutations
// deliberately refresh self-checksums, so rejection must check invariants.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, rmSync} from 'node:fs';
import {join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = join(root, 'examples/instances');
mkdirSync(join(root, '_build'), {recursive: true});
const work = mkdtempSync(join(root, '_build', 'deployment 空格 '));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const planDigest = plan => { const {plan_digest, ...payload} = plan; return hash('weft:deployment-plan:v1\n' + JSON.stringify(payload)); };
const base = JSON.parse(readFileSync(join(fixtures, 'chain.json')));
let baseline;
try {
  for (const name of ['source', 'alternate', 'consumer', 'function-consumer']) copyFileSync(join(fixtures, name+'.wasm'), join(work, name+'.wasm'));
  const foreign = join(work, 'foreign'); mkdirSync(foreign);
  const input = join(work, 'input.json'), planFile = join(work, 'plan.json'), lockFile = join(work, 'lock.json');
  const goldenPlan = readFileSync(join(root, 'docs/fixtures/deployment-v0.4.0.json'));
  const goldenLock = readFileSync(join(root, 'docs/fixtures/input-lock-v0.1.0.json'));
  for (const target of ['native', 'wasm-gc', 'js']) {
    const build = spawnSync('moon', ['build', 'src/compose_cli', '--target', target], {cwd: root, encoding: 'utf8', timeout: 120000});
    if (build.error) throw build.error;
    assert.equal(build.status, 0, build.stderr);
    const artifact = join(root, '_build', target, 'debug/build/compose_cli/compose_cli');
    const executable = target === 'native' ? artifact+'.exe' : target === 'js' ? process.execPath : 'moonrun';
    const prefix = target === 'native' ? [] : target === 'js' ? [artifact+'.js'] : [artifact+'.wasm', '--'];
    let checks = 0;
    function run(args, status = 0, contains = '') {
      const r = spawnSync(executable, [...prefix, ...args], {cwd: foreign, encoding: 'utf8', timeout: 30000});
      if (r.error) throw r.error;
      assert.equal(r.status, status, `${target} ${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
      assert(r.stdout.includes(contains), r.stdout); checks++; return r;
    }
    function seal(value = base) {
      writeFileSync(input, JSON.stringify(value));
      run(['seal', input, '--out', planFile, '--lock', lockFile]);
      return {plan: readFileSync(planFile), lock: readFileSync(lockFile)};
    }
    function verify(status = 0, code = 'valid canonical') { run(['verify', planFile, '--lock', lockFile, '--inputs', input], status, code); }
    const original = seal();
    assert(original.plan.equals(goldenPlan)); assert(original.lock.equals(goldenLock));
    if (baseline) { assert(original.plan.equals(baseline.plan)); assert(original.lock.equals(baseline.lock)); } else baseline = original;
    verify();
    const plan = JSON.parse(original.plan), lock = JSON.parse(original.lock);
    assert.equal(plan.plan_digest.value, planDigest(plan));
    assert.equal(plan.lock_digest.value, hash('weft:input-lock:v1\n' + original.lock.toString('utf8')));
    for (const a of lock.artifacts) {
      const bytes = readFileSync(join(work, a.id+'.wasm'));
      assert.equal(a.digest, hash(bytes)); assert.equal(a.length, bytes.length);
    }
    assert.equal(hash('weft:type-signature:instance-sync-v1:v1\n{"tag":"scalar:u32","members":[]}'), '8af9aafb8305662baa02403c8bc7d4ec6119d679cf39dd40c12042d25ebe999b');
    function mutated(change, code) {
      const value = structuredClone(plan); change(value); value.plan_digest.value = planDigest(value);
      writeFileSync(planFile, JSON.stringify(value)); verify(1, code);
    }
    mutated(p => p.bindings[0].from.component = 'consumer', 'BINDING_INTENT_MISMATCH');
    mutated(p => p.bindings = [], 'BINDING_INTENT_MISMATCH');
    mutated(p => p.bindings.push(p.bindings[0]), 'BINDING_INTENT_MISMATCH');
    mutated(p => p.bindings[0].from_signature = '0'.repeat(64), 'TYPE_SIGNATURE_MISMATCH');
    mutated(p => p.bindings[0].to_signature = '0'.repeat(64), 'TYPE_SIGNATURE_MISMATCH');
    mutated(p => p.instances[1].imports = [], 'INVALID_INCOMING');
    mutated(p => p.instances[1].imports = [99], 'INVALID_INDEX');
    mutated(p => {p.instances.reverse(); p.instances.forEach((v, i) => v.order = i);}, 'INVALID_ORDER');
    mutated(p => p.operations.reverse(), 'INVALID_OPERATIONS');
    mutated(p => p.instances[0].digest = '0'.repeat(64), 'ARTIFACT_MISMATCH');
    writeFileSync(planFile, original.plan);
    const changed = structuredClone(base); changed.components.find(c => c.name === 'source').path = 'alternate.wasm';
    writeFileSync(input, JSON.stringify(changed)); verify(1, 'BINARY_DIGEST_MISMATCH');
    const alternate = seal(changed); verify(); assert(!alternate.plan.equals(original.plan));
    const reordering = structuredClone(base); reordering.components.reverse(); reordering.bindings.reverse();
    assert(seal(reordering).plan.equals(original.plan)); verify();
    writeFileSync(planFile, ' ' + original.plan); verify(2, 'valid noncanonical');
    writeFileSync(planFile, original.plan.toString().replace('"plan_version":', '"plan_version":"0.4.0","plan_version":')); verify(1, 'INVALID_JSON');
    writeFileSync(planFile, original.plan.toString().replaceAll('sha256', 'md5')); verify(1, 'UNSUPPORTED_PROTOCOL');
    for (const args of [
      ['seal', input, '--out', planFile, '--out', planFile],
      ['seal', input, '--out', planFile, '--lock', planFile],
      ['verify', planFile, '--lock', lockFile],
      ['verify', planFile, '--lock', lockFile, '--bogus', input],
    ]) run(args, 1);
    const fn = seal(JSON.parse(readFileSync(join(fixtures, 'function.json')))); verify();
    assert.equal(JSON.parse(fn.plan).bindings[0].from.member, 'inc');
    console.log(`OK: ${checks} deployment CLI checks (${target}), independent SHA-256 and byte parity`);
  }
} finally {
  assert.equal(dirname(work), join(root, '_build'));
  rmSync(work, {recursive: true, force: true});
}
