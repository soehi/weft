import {chooseFile} from './files.mjs';
const $ = id => document.getElementById(id);
const worker = new Worker(new URL('./deployment-worker.mjs', import.meta.url), {type: 'module'});
let ready = false, revision = 0, sequence = 0, files = [], selected = new Map(), bundle = null;
const pending = new Map();
function invalidate() {
  revision++; bundle = null; $('success').hidden = true; $('diagnostic').hidden = true; $('empty').hidden = false;
  $('check').disabled = !ready; $('check').textContent = '检查并锁定输入 ↗';
}
function fail(d) {
  bundle = null; $('success').hidden = true; $('empty').hidden = true; $('diagnostic').hidden = false;
  const code = document.createElement('code'), message = document.createElement('p'), path = document.createElement('p');
  code.textContent = d.code; message.textContent = d.message;
  path.textContent = [d.component, ...(d.path || [])].filter(Boolean).join(' / ');
  $('diagnostic').replaceChildren(code, message, path); $('status').textContent = '请根据诊断修改输入后重新检查。';
}
worker.onmessage = ({data}) => {
  if (data.ready) { ready = true; $('check').disabled = false; $('status').textContent = '工具已就绪。选择本地文件或载入示例。'; return; }
  pending.get(data.id)?.(data.result); pending.delete(data.id);
};
worker.onerror = () => {
  ready = false; $('check').disabled = true;
  const result = {ok: false, diagnostic: {code: 'BROWSER_WORKER', message: '工具加载失败，请确认已构建并通过本地 HTTP 打开。'}};
  for (const resolve of pending.values()) resolve(result); pending.clear(); fail(result.diagnostic);
};
function seal(manifest, binaries) {
  const id = ++sequence;
  return new Promise(resolve => { pending.set(id, resolve); worker.postMessage({id, manifest, binaries}, binaries.map(([, buffer]) => buffer)); });
}
function components() { const m = JSON.parse($('manifest').value); return Array.isArray(m.components) ? m.components : []; }
function mapping() {
  selected = new Map(); $('mapping').replaceChildren();
  let entries; try { entries = components(); } catch { return; }
  entries.forEach((c, i) => {
    if (typeof c.name !== 'string' || typeof c.path !== 'string') return;
    const row = document.createElement('div'), label = document.createElement('label'), select = document.createElement('select');
    row.className = 'mapping-row'; label.htmlFor = `file-${i}`; label.textContent = `${c.name} ← ${c.path}`; select.id = label.htmlFor;
    const option = document.createElement('option'); option.value = '-1'; option.textContent = '请选择对应文件'; select.append(option);
    files.forEach((file, index) => { const item = document.createElement('option'); item.value = String(index); item.textContent = `${file.webkitRelativePath || file.name} · ${file.size} bytes [${index + 1}]`; select.append(item); });
    const match = chooseFile(c.path, files); selected.set(c.name, match); select.value = String(match);
    select.onchange = () => { invalidate(); selected.set(c.name, Number(select.value)); };
    row.append(label, select); $('mapping').append(row);
  });
}
$('manifest').oninput = () => { invalidate(); mapping(); };
$('manifest-file').onchange = async event => {
  invalidate(); const token = revision, file = event.target.files[0]; if (!file) return;
  $('manifest').value = ''; mapping();
  try {
    const text = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(await file.arrayBuffer());
    if (token !== revision) return; $('manifest').value = text; $('manifest-name').textContent = file.name; mapping();
  } catch { if (token === revision) fail({code: 'BROWSER_UTF8', message: '清单必须是合法 UTF-8 文件。'}); }
};
$('component-files').onchange = event => { invalidate(); files = Array.from(event.target.files); $('file-count').textContent = `${files.length} 个文件`; mapping(); };
$('check').onclick = async () => {
  invalidate(); const token = revision, manifest = $('manifest').value;
  $('check').disabled = true; $('status').textContent = '正在检查接口与组件内容…';
  try {
    // Preserve strict MoonBit duplicate-key and version checks before JS mapping.
    const preflight = await seal(manifest, []); if (token !== revision) return;
    if (!preflight.ok && preflight.diagnostic.code !== 'MISSING_BINARY') { fail(preflight.diagnostic); return; }
    const payload = [];
    for (const c of components()) {
      const index = selected.get(c.name) ?? -1;
      if (!files[index]) { fail({code: 'BROWSER_FILE_MISSING', component: c.name, message: '请选择对应组件；有同名文件时需要手动指定。'}); return; }
      payload.push([c.name, await files[index].arrayBuffer()]);
    }
    if (token !== revision) return;
    const result = await seal(manifest, payload); if (token !== revision) return;
    if (!result.ok) { fail(result.diagnostic); return; }
    bundle = result; const plan = JSON.parse(result.plan_json);
    $('empty').hidden = true; $('diagnostic').hidden = true; $('success').hidden = false;
    $('plan-json').textContent = result.plan_json; $('lock-json').textContent = result.lock_json;
    $('hash').textContent = `计划 SHA-256 / ${plan.plan_digest.value}`;
    $('instances').replaceChildren();
    for (const i of plan.instances) {
      const row = document.createElement('tr');
      for (const value of [i.order, i.id, `${i.digest} / ${i.length}`, i.imports.length]) { const cell = document.createElement('td'); cell.textContent = value; row.append(cell); }
      $('instances').append(row);
    }
    $('status').textContent = '计划已生成。请审核并保存计划与输入锁。';
  } catch (e) { if (token === revision) fail({code: 'BROWSER_INPUT', message: String(e)}); }
  finally { if (token === revision) $('check').disabled = !ready; }
};
function download(key, name) {
  if (!bundle) return;
  const url = URL.createObjectURL(new Blob([bundle[key]], {type: 'application/json;charset=utf-8'}));
  const link = document.createElement('a'); link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
$('download').onclick = () => download('plan_json', 'plan.json');
$('download-lock').onclick = () => download('lock_json', 'inputs.lock.json');
for (const button of document.querySelectorAll('[data-provider]')) button.onclick = async () => {
  invalidate(); const token = revision; $('status').textContent = '正在载入示例…';
  try {
    const response = await fetch('./examples/instances/chain.json'); if (!response.ok) throw new Error('示例清单读取失败');
    const value = await response.json(); value.components.find(c => c.name === 'source').path = button.dataset.provider + '.wasm';
    const loaded = await Promise.all([...new Set(value.components.map(c => c.path))].map(async path => {
      const result = await fetch('./examples/instances/' + path); if (!result.ok) throw new Error('示例组件读取失败');
      return new File([await result.arrayBuffer()], path);
    }));
    if (token !== revision) return;
    files = loaded; $('manifest').value = JSON.stringify(value, null, 2); $('manifest-name').textContent = '实例示例'; $('file-count').textContent = `${files.length} 个文件`; mapping();
    $('status').textContent = '示例已载入，点击检查并锁定输入。';
  } catch (e) { if (token === revision) fail({code: 'BROWSER_EXAMPLE', message: String(e)}); }
};
