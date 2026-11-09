// Whole CLI wall time: process startup + reads + decode + planning + JSON/write.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { createHash } from 'node:crypto';
import os from 'node:os';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repeats = Number(process.argv[2] ?? 3);
assert(Number.isInteger(repeats) && repeats >= 1 && repeats <= 20, 'repeats must be 1..20');
const output = join(root, '_build/benchmarks');
mkdirSync(output, {recursive:true});
const work = mkdtempSync(join(output, 'planner spaces '));
function run(command, args, cwd=root) {
  const start = performance.now();
  const result = spawnSync(command, args, {cwd, encoding:'utf8', timeout:120_000, maxBuffer:4*1024*1024});
  const elapsed = performance.now()-start;
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return {elapsed, stdout:result.stdout};
}
const targets = ['native', 'wasm-gc', 'js'];
const report = {
  schema_version:2, timestamp:new Date().toISOString(),
  commit:run('git',['rev-parse','HEAD']).stdout.trim(),
  benchmark_script_sha256:createHash('sha256').update(readFileSync(fileURLToPath(import.meta.url))).digest('hex'),
  profile_source_sha256:createHash('sha256').update(readFileSync(join(root,'src/tools/profile_planner/main.mbt'))).digest('hex'),
  build_profile:'debug',
  environment:{os:os.platform(), release:os.release(), arch:os.arch(), cpu:os.cpus()[0]?.model, node:process.version},
  toolchain:run('moon',['version','--all']).stdout.trim(),
  repeats, metric:'fresh process CLI wall milliseconds, including startup, file I/O, decode, plan and output; build/generation excluded',
  cases:[],
};
try {
  run('moon', ['run','src/tools/make_execution_fixtures','--target','native','--',work]);
  run('moon', ['run','src/tools/make_benchmark_fixtures','--target','native','--',work]);
  for (const target of targets) run('moon',['build','src/cli','src/tools/profile_planner','--target',target]);
  function cli(target, manifest, destination) {
    const artifact = join(root, '_build', target, 'debug/build/cli/cli');
    const command = target === 'native' ? artifact+'.exe' : target === 'js' ? process.execPath : 'moonrun';
    const prefix = target === 'native' ? [] : target === 'js' ? [artifact+'.js'] : [artifact+'.wasm','--'];
    return run(command, [...prefix,'plan',manifest,'--out',destination], work).elapsed;
  }
  for (const size of [100,1000]) for (const shape of ['chain','fanout','fanin']) {
    const name = i => `c${String(i).padStart(4,'0')}`;
    const components = Array.from({length:size}, (_,i)=>({
      name:name(i), path:shape === 'fanin' ? (i===size-1 ? `fanin-${size}.wasm` : 'source.wasm') : (i===0 ? 'source.wasm' : 'consumer.wasm'),
    }));
    const wires = Array.from({length:size-1}, (_,i)=>({
      from:shape === 'fanin' || shape === 'fanout' ? `${name(shape==='fanin'? i:0)}.inc` : `${name(i)}.${i===0?'inc':'run'}`,
      to:shape === 'fanin' ? `${name(size-1)}.in-${i}` : `${name(i+1)}.inc`,
    }));
    const manifest = join(work,'input.json'), destination = join(work,'plan.json');
    const body = {components, wires};
    writeFileSync(manifest,JSON.stringify(body));
    let golden;
    for (const target of targets) {
      cli(target,manifest,destination); // warm OS cache, fresh runtime each sample
      const bytes = readFileSync(destination);
      const plan = JSON.parse(bytes);
      assert.equal(plan.instances.length,size);
      assert.equal(plan.wires.length,size-1);
      const rank = new Map(plan.instances.map((v,i)=>[v.name,i]));
      assert.equal(rank.size,size);
      for (const w of wires) assert(rank.get(w.from.split('.')[0]) < rank.get(w.to.split('.')[0]));
      assert.deepEqual(plan.wires.map(w=>[w.from,w.to]).sort(), wires.map(w=>[w.from,w.to]).sort());
      if (golden) assert(bytes.equals(golden), `backend mismatch ${shape}/${size}/${target}`);
      else golden=bytes;
      const samples = Array.from({length:repeats}, ()=>{
        const elapsed=cli(target,manifest,destination);
        assert(readFileSync(destination).equals(golden), `sample mismatch ${shape}/${size}/${target}`);
        return elapsed;
      });
      const sorted = [...samples].sort((a,b)=>a-b);
      report.cases.push({shape,size,target,median_ms:sorted[Math.floor(sorted.length/2)], min_ms:sorted[0], samples_ms:samples,
        plan_bytes:bytes.length, sha256:createHash('sha256').update(bytes).digest('hex')});
      const artifact = join(root,'_build',target,'debug/build/tools/profile_planner/profile_planner');
      const command = target==='native' ? artifact+'.exe' : target==='js' ? process.execPath : 'moonrun';
      const prefix = target==='native' ? [] : target==='js' ? [artifact+'.js'] : [artifact+'.wasm','--'];
      const phase = run(command,[...prefix,manifest,destination,String(repeats)],work);
      const phaseSamples = phase.stdout.trim().split(/\r?\n/).map(line=>JSON.parse(line));
      assert.equal(phaseSamples.length,repeats);
      const phaseMedians = {};
      for (const key of ['parse_ms','decode_ms','plan_ms','json_ms','graph_probe_ms']) {
        const values=phaseSamples.map(sample=>sample[key]);
        assert(values.every(value=>Number.isFinite(value)&&value>=0), `invalid phase timer ${key}`);
        phaseMedians[key]=values.sort((a,b)=>a-b)[Math.floor(repeats/2)];
      }
      assert(readFileSync(destination).equals(golden), `profile differs from CLI ${shape}/${size}/${target}`);
      Object.assign(report.cases.at(-1),{phase_samples_ms:phaseSamples,phase_medians_ms:phaseMedians});
      console.log(`phases ${shape} ${size} ${target}: decode ${phaseMedians.decode_ms.toFixed(1)}, plan ${phaseMedians.plan_ms.toFixed(1)}, graph probe ${phaseMedians.graph_probe_ms.toFixed(1)} ms`);
      writeFileSync(manifest,JSON.stringify({components:[...components].reverse(),wires:[...wires].reverse()}));
      cli(target,manifest,destination);
      assert(readFileSync(destination).equals(golden), `permutation mismatch ${shape}/${size}/${target}`);
      writeFileSync(manifest,JSON.stringify(body));
      console.log(`${shape} ${size} ${target}: ${sorted[Math.floor(sorted.length/2)].toFixed(1)} ms`);
    }
  }
  writeFileSync(join(output,'latest.json'),JSON.stringify(report,null,2)+'\n');
  console.log('OK: 18 measured cases, phase/CLI byte parity, cross-backend bytes, wire coverage and reversed-input determinism');
} finally {
  // work is an mkdtemp child of the fixed workspace output directory.
  assert(dirname(work)===output);
  rmSync(work,{recursive:true,force:true});
}
