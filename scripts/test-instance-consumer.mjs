// Independent module imports only the experimental in-memory composition API.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const output=join(root,'_build'); mkdirSync(output,{recursive:true});
const work=mkdtempSync(join(output,'instance api consumer '));
try {
  const version=readFileSync(join(root,'moon.mod'),'utf8').match(/^version = "([^"]+)"/m)[1];
  writeFileSync(join(work,'moon.mod'),`name = "acceptance/instance_consumer"\nimport { "soehi/weft@${version}" }\n`);
  writeFileSync(join(work,'moon.work'),'members = ["../..", "."]\n');
  writeFileSync(join(work,'moon.pkg'),'import { "soehi/weft/compose" }\npkgtype(kind: "executable")\n');
  const blobs=['source','consumer','wrong-type'].map((name,i)=>`let b${i} : Bytes = [${[...readFileSync(join(root,'examples/instances',name+'.wasm'))].join(',')}]`).join('\n');
  const text=readFileSync(join(root,'examples/instances/chain.json'),'utf8');
  writeFileSync(join(work,'main.mbt'),`fn main {
${blobs}
let text = ${JSON.stringify(text)}
let bins = Map([("source",b0),("consumer",b1)])
let result = match @compose.compile(text,bins) { Ok(o) => o.json; Err(d) => abort(d.code+": "+d.detail) }
match @compose.compile(text,Map([])) { Err(d) => if d.code != "MISSING_BINARY" { abort(d.code) }; Ok(_) => abort("missing input succeeded") }
match @compose.compile(text,Map([("source",b2),("consumer",b1)])) { Err(d) => if d.code != "TYPE_MISMATCH" { abort(d.code) }; Ok(_) => abort("mismatch succeeded") }
println(result)
}
`);
  const golden=readFileSync(join(root,'docs/fixtures/plan-instance-v0.3.0.json'),'utf8');
  for(const target of ['native','wasm-gc','js']) {
    const build=spawnSync('moon',['build','.','--target',target],{cwd:work,encoding:'utf8',timeout:180000});
    if(build.error) throw build.error;
    assert.equal(build.status,0,build.stderr);
    const run=spawnSync('moon',['run','.','--target',target],{cwd:work,encoding:'utf8',timeout:30000});
    if(run.error) throw run.error;
    assert.equal(run.status,0,run.stdout+run.stderr);
    assert.equal(run.stdout.replace(/\r?\n$/,''),golden);
    console.log(`OK: independent D1 memory API consumer (${target}), golden plan and two diagnostics`);
  }
} finally {
  assert.equal(dirname(work),output);
  rmSync(work,{recursive:true,force:true});
}
