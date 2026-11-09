// Fresh registry-only consumer. No moon.work, path overrides, or repository dependency.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, realpathSync, rmSync} from 'node:fs';
import {join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
mkdirSync(join(root,'_build/release'),{recursive:true});
const work=mkdtempSync(join(root,'_build','registry consumer '));
const version=process.argv[2]??'0.3.0';
assert(/^0\.3\.[01]$/.test(version),'unsupported acceptance version');
const env={...process.env,MOON_REGISTRY_API:'1'};
function run(args) {
  const r=spawnSync('moon',args,{cwd:work,env,encoding:'utf8',timeout:180000,maxBuffer:4*1024*1024});
  if(r.error) throw r.error;
  assert.equal(r.status,0,`${args.join(' ')}\n${r.stdout}\n${r.stderr}`);
  return r.stdout;
}
try {
  writeFileSync(join(work,'moon.mod'),`name = "acceptance/registry_consumer"\nimport { "soehi/weft@${version}" }\n`);
  writeFileSync(join(work,'moon.pkg'),'import { "soehi/weft/api" }\npkgtype(kind: "executable")\n');
  const blobs=['reader','filter','sink','wide-sink'].map((name,i)=>`let b${i} : Bytes = [${[...readFileSync(join(root,'examples',name+'.wasm'))].join(',')}]`).join('\n');
  const manifest=readFileSync(join(root,'examples/chain.json'),'utf8');
  const mismatch=JSON.stringify({components:[{name:'source',path:'r'},{name:'sink',path:'s'}],wires:[{from:'source.read',to:'sink.in'}]});
  writeFileSync(join(work,'main.mbt'),`fn main {
${blobs}
let text = ${JSON.stringify(manifest)}
let bins : Map[String,Bytes] = Map([("reader",b0),("filter",b1),("sink",b2)])
let success = match @api.compile(text,bins) { Ok(o) => o.json; Err(d) => abort(d.code+": "+d.message) }
match @api.compile(text,Map([])) { Err(d) => if d.code != "INPUT_MISSING_BINARY" { abort(d.code) }; Ok(_) => abort("missing binary succeeded") }
match @api.compile(${JSON.stringify(mismatch)},Map([("source",b0),("sink",b3)])) { Err(d) => if d.code != "PLAN_TYPE_MISMATCH" { abort(d.code+": "+d.message) }; Ok(_) => abort("type mismatch succeeded") }
println(success)
}
`);
  assert(!existsSync(join(work,'moon.work')));
  const expected=readFileSync(join(root,'docs/fixtures/plan-v0.2.0.json'));
  const results=[];
  for(const target of ['native','wasm-gc','js']) {
    run(['build','--target',target]);
    const output=Buffer.from(run(['run','.','--target',target]).replace(/\r?\n$/,''));
    assert(output.equals(expected),`registry plan differs: ${target}`);
    results.push({target,plan_sha256:createHash('sha256').update(output).digest('hex'),missing_binary:'INPUT_MISSING_BINARY',type_mismatch:'PLAN_TYPE_MISMATCH'});
    console.log(`OK: registry-only consumer ${target}, golden plan + two diagnostics`);
  }
  const dependency=join(work,'.mooncakes','soehi','weft');
  assert(realpathSync(dependency).startsWith(realpathSync(work)), 'dependency must resolve inside fresh registry cache');
  const module=readFileSync(join(dependency,'moon.mod'),'utf8');
  assert.match(module,/name = "soehi\/weft"/);
  assert(module.includes(`version = "${version}"`));
  writeFileSync(join(root,'_build/release/registry-install.json'),JSON.stringify({module:'soehi/weft',version,source:'public registry, HTTP metadata, no workspace/path override',results},null,2)+'\n');
} finally {
  assert(dirname(work)===join(root,'_build'));
  rmSync(work,{recursive:true,force:true});
}
