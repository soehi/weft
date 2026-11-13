// Actual portable CLI checks for the explicit D1 profile, separate from 0.2.0.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,copyFileSync,rmSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
mkdirSync(join(root,'_build'),{recursive:true});
const work=mkdtempSync(join(root,'_build','instance composition 空格 '));
const fixture=join(root,'examples/instances');
const base=JSON.parse(readFileSync(join(fixture,'chain.json'),'utf8'));
const golden=readFileSync(join(root,'docs/fixtures/plan-instance-v0.3.0.json'));
const targets=['native','wasm-gc','js'];
let goldenWac;
try {
  for(const name of ['source','alternate','consumer','missing','wrong-type','function-consumer']) copyFileSync(join(fixture,name+'.wasm'),join(work,name+'.wasm'));
  const foreign=join(work,'foreign cwd'); mkdirSync(foreign);
  const manifest=join(work,'input.json'), output=join(work,'plan.json');
  for(const target of targets) {
    const build=spawnSync('moon',['build','src/compose_cli','--target',target],{cwd:root,encoding:'utf8',timeout:120000});
    if(build.error) throw build.error;
    assert.equal(build.status,0,build.stderr);
    const artifact=join(root,'_build',target,'debug/build/compose_cli/compose_cli');
    // This locked MoonBit uses .exe for native artifacts on Linux as well.
    const executable=target==='native'?artifact+'.exe':target==='js'?process.execPath:'moonrun';
    const prefix=target==='native'?[]:target==='js'?[artifact+'.js']:[artifact+'.wasm','--'];
    let checks=0;
    function run(args,code=0,contains='') {
      const r=spawnSync(executable,[...prefix,...args],{cwd:foreign,encoding:'utf8',timeout:30000});
      if(r.error) throw r.error;
      assert.equal(r.status,code,`${target} ${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
      if(contains) assert(r.stdout.includes(contains),r.stdout);
      checks++;
      return r;
    }
    function plan(value=base) {
      writeFileSync(manifest,JSON.stringify(value));
      run(['plan',manifest,'--out',output]);
      return readFileSync(output);
    }
    assert(plan().equals(golden),`${target} golden instance plan differs`);
    const wac=join(work,'plan.wac'); run(['emit-wac',manifest,'--out',wac]);
    const bytes=readFileSync(wac);
    if(goldenWac) assert(bytes.equals(goldenWac),'WAC differs across backends'); else goldenWac=bytes;
    const reversed=structuredClone(base); reversed.components.reverse(); reversed.bindings.reverse();
    assert(plan(reversed).equals(golden),'declaration order changed plan');
    const alternate=structuredClone(base); alternate.components.find(c=>c.name==='source').path='alternate.wasm';
    const alt=JSON.parse(plan(alternate));
    assert.equal(alt.instances[0].path,'alternate.wasm');
    const functionInput=JSON.parse(readFileSync(join(fixture,'function.json'),'utf8'));
    const functionPlan=JSON.parse(plan(functionInput));
    assert.equal(functionPlan.bindings[0].kind,'function');
    assert.equal(functionPlan.bindings[0].from.member,'inc');
    run(['emit-wac',manifest,'--out',wac]);
    assert(readFileSync(wac,'utf8').includes('c-source["ops"]["inc"]'));
    function failure(value,code) {
      writeFileSync(manifest,typeof value==='string'?value:JSON.stringify(value));
      writeFileSync(output,'sentinel');
      run(['plan',manifest,'--out',output],1,code);
      assert.equal(readFileSync(output,'utf8'),'sentinel','failed compile overwrote output');
    }
    for(const [file,code,member] of [['missing','MISSING_MEMBER','twice'],['wrong-type','TYPE_MISMATCH','inc']]) {
      const value=structuredClone(base); value.components.find(c=>c.name==='source').path=file+'.wasm';
      failure(value,code);
      run(['plan',manifest],1,member);
    }
    const unbound=structuredClone(base); unbound.bindings=[]; failure(unbound,'UNBOUND_IMPORT');
    const duplicate=structuredClone(base); duplicate.bindings.push(duplicate.bindings[0]); failure(duplicate,'DUPLICATE_BINDING');
    const partial=structuredClone(base); partial.bindings[0].kind='function'; partial.bindings[0].from.member='inc'; partial.bindings[0].to.member='inc'; failure(partial,'PARTIAL_INSTANCE_BINDING');
    const mixed=structuredClone(base); mixed.bindings.push(partial.bindings[0]); failure(mixed,'MIXED_BINDING');
    const unknown=structuredClone(base); unknown.bindings[0].from.component='absent'; failure(unknown,'UNKNOWN_COMPONENT');
    const profile=structuredClone(base); profile.profile='unknown'; failure(profile,'UNSUPPORTED_PROFILE');
    const version=structuredClone(base); version.manifest_version='0.2.0'; failure(version,'UNSUPPORTED_MANIFEST_VERSION');
    const extra=structuredClone(base); extra.resources={quota:1}; failure(extra,'UNKNOWN_FIELD');
    failure('{"manifest_version":"0.3.0","manifest_version":"0.3.0"}','INVALID_JSON');
    const file=structuredClone(base); file.components[0].path='absent.wasm'; failure(file,'cannot read');
    writeFileSync(manifest,Buffer.from([0xc3,0x28])); run(['plan',manifest],1);
    run(['plan',manifest,'--bogus','file'],1);
    run(['plan',manifest,'--out',output,'--out',output],1);
    run(['plan',manifest,'--out'],1);
    // Names are opaque IDs in the pure profile; punctuation is never split.
    const names=structuredClone(base);
    for(const c of names.components) if(c.name==='source') c.name='source.with.dot';
    names.bindings[0].from.component='source.with.dot';
    assert.equal(JSON.parse(plan(names)).instances[0].name,'source.with.dot');
    run(['emit-wac',manifest],1,'WAC_UNREPRESENTABLE');
    console.log(`OK: ${checks} actual instance CLI checks (${target}), canonical bytes, WAC and rejection paths`);
  }
} finally {
  assert.equal(dirname(work),join(root,'_build'));
  rmSync(work,{recursive:true,force:true});
}
