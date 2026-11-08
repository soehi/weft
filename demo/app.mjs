import { chooseFile } from './files.mjs';
const $ = id => document.getElementById(id);
const worker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
let ready = false, revision = 0, sequence = 0, files = [], selected = new Map(), canonical = null;
const pending = new Map();
const localError = (code, message, component) => ({ code, stage: 'browser', message, location: { component }, related: [] });
function clearResult() { canonical = null; $('success').hidden = true; $('diagnostic').hidden = true; $('empty').hidden = false; }
function invalidate() { revision++; clearResult(); $('check').disabled = !ready; $('check').textContent = '检查并生成计划 ↗'; }
function showError(d) {
  clearResult(); $('empty').hidden = true; $('diagnostic').hidden = false;
  const heading = document.createElement('h3'); heading.textContent = '暂时无法生成计划';
  const code = document.createElement('code'); code.textContent = d.code;
  const message = document.createElement('p'); message.textContent = d.message;
  const where = document.createElement('p'); where.textContent = [d.location?.component, d.location?.port, d.location?.field].filter(Boolean).join(' / ');
  const detail = document.createElement('p'); detail.textContent = d.detail || '';
  $('diagnostic').replaceChildren(heading, code, message, where, detail);
  $('status').textContent = '请根据诊断修改输入后重新检查。';
}
worker.onmessage = ({ data }) => {
  if (data.ready) { ready = true; $('check').disabled = false; $('status').textContent = '规划器已就绪。选择文件或载入示例。'; return; }
  pending.get(data.id)?.(data.result); pending.delete(data.id);
};
worker.onerror = () => { ready = false; $('check').disabled = true; showError(localError('BROWSER_WORKER', '规划器加载失败，请确认已构建 demo 并通过本地 HTTP 服务打开。')); for (const resolve of pending.values()) resolve({ ok: false, diagnostic: localError('BROWSER_WORKER', '规划器不可用') }); pending.clear(); };
function compile(manifest, binaries) {
  const id = ++sequence;
  return new Promise(resolve => { pending.set(id, resolve); worker.postMessage({ id, manifest, binaries }, binaries.map(([, buffer]) => buffer)); });
}
function components() { const value = JSON.parse($('manifest').value); return Array.isArray(value.components) ? value.components : []; }
function renderMapping() {
  selected = new Map(); $('mapping').replaceChildren();
  let comps; try { comps = components(); } catch { return; }
  comps.forEach((c, index) => {
    if (typeof c.name !== 'string' || typeof c.path !== 'string') return;
    const row = document.createElement('div'); row.className = 'mapping-row';
    const label = document.createElement('label'); label.htmlFor = `file-${index}`; label.textContent = `${c.name} ← ${c.path}`;
    const select = document.createElement('select'); select.id = label.htmlFor;
    const none = document.createElement('option'); none.value = '-1'; none.textContent = '请选择对应文件'; select.append(none);
    files.forEach((f, i) => { const option = document.createElement('option'); option.value = String(i); option.textContent = `${f.webkitRelativePath || f.name} · ${f.size} bytes [${i + 1}]`; select.append(option); });
    const match = chooseFile(c.path, files); select.value = String(match); selected.set(c.name, match);
    select.onchange = () => { invalidate(); selected.set(c.name, Number(select.value)); $('status').textContent = '文件对应关系已更新。'; };
    row.append(label, select); $('mapping').append(row);
  });
}
$('manifest').addEventListener('input', () => { invalidate(); renderMapping(); $('status').textContent = '清单已修改，请重新检查。'; });
$('manifest-file').onchange = async event => {
  invalidate(); const token = revision; const file = event.target.files[0]; if (!file) return; $('manifest').value = ''; $('manifest-name').textContent = file.name; renderMapping();
  try { const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(await file.arrayBuffer()); if (token !== revision) return; $('manifest').value = text; $('manifest-name').textContent = file.name; renderMapping(); $('status').textContent = '清单已载入，请选择组件文件。'; }
  catch { if (token === revision) showError(localError('BROWSER_UTF8', '清单必须是合法 UTF-8 文件。')); }
};
$('component-files').onchange = event => { invalidate(); files = Array.from(event.target.files); $('file-count').textContent = `${files.length} 个文件`; renderMapping(); $('status').textContent = '组件文件已选择，请确认对应关系。'; };
$('check').onclick = async () => {
  invalidate(); const token = revision; const manifest = $('manifest').value; $('check').disabled = true; $('check').textContent = '正在检查…'; $('status').textContent = '正在本地解析组件并编译计划…';
  try {
    // MoonBit validates the original text first, preserving duplicate-key diagnostics.
    const preflight = await compile(manifest, []);
    if (token !== revision) return;
    if (!preflight.ok && preflight.diagnostic.code !== 'INPUT_MISSING_BINARY') { showError(preflight.diagnostic); return; }
    const payload = [];
    for (const c of components()) {
      const i = selected.get(c.name) ?? -1;
      if (!files[i]) { showError(localError('BROWSER_FILE_MISSING', `请为组件 ${c.name} 选择文件；有同名文件时需要手动指定。`, c.name)); return; }
      payload.push([c.name, await files[i].arrayBuffer()]);
    }
    if (token !== revision) return;
    const result = await compile(manifest, payload);
    if (token !== revision) return;
    if (result.ok) showPlan(result.plan_json); else showError(result.diagnostic);
  } catch (e) { if (token === revision) showError(localError('BROWSER_INPUT', String(e))); }
  finally { if (token === revision) { $('check').disabled = !ready; $('check').textContent = '检查并生成计划 ↗'; } }
};
const NS = 'http://www.w3.org/2000/svg';
function svgElement(tag, attrs, text) { const e = document.createElementNS(NS, tag); for (const [key, value] of Object.entries(attrs)) e.setAttribute(key, value); if (text !== undefined) e.textContent = text; return e; }
function showPlan(json) {
  canonical = json; const plan = JSON.parse(json); $('empty').hidden = true; $('diagnostic').hidden = true; $('success').hidden = false;
  $('status').textContent = `规划通过：${plan.instances.length} 个实例，${plan.wires.length} 条连线。`;
  $('hash').textContent = `FNV-1a 64 / ${plan.plan_hash}`; $('plan-json').textContent = json;
  $('instances').replaceChildren();
  for (const instance of plan.instances) { const tr = document.createElement('tr'); for (const value of [instance.order, instance.name, instance.path, instance.incoming.length]) { const td = document.createElement('td'); td.textContent = value; tr.append(td); } $('instances').append(tr); }
  // Presentation positions follow the plan's actual instance order; no graph sorting here.
  const width = Math.max(440, plan.instances.length * 205 + 40), height = Math.max(235, plan.wires.length * 22 + 140);
  const graph = $('graph'); graph.replaceChildren(); graph.setAttribute('viewBox', `0 0 ${width} ${height}`); graph.style.width = `${width}px`;
  const defs = svgElement('defs', {}), marker = svgElement('marker', { id: 'arrow', viewBox: '0 0 10 10', refX: 9, refY: 5, markerWidth: 5, markerHeight: 5, orient: 'auto-start-reverse' }); marker.append(svgElement('path', { d: 'M 0 0 L 10 5 L 0 10 z', fill: '#78907c' })); defs.append(marker); graph.append(defs);
  const positions = new Map(plan.instances.map((n, i) => [n.name, 110 + i * 205])); const y = height - 60;
  plan.wires.forEach((w, i) => {
    const source = w.from.slice(0, w.from.indexOf('.')), target = w.to.slice(0, w.to.indexOf('.'));
    const x1 = positions.get(source), x2 = positions.get(target), top = 30 + i * 20;
    graph.append(svgElement('path', { d: `M ${x1} ${y - 22} C ${x1} ${top}, ${x2} ${top}, ${x2} ${y - 22}`, class: 'edge', 'marker-end': 'url(#arrow)' }));
    const label = svgElement('text', { x: (x1 + x2) / 2, y: top + 8, 'text-anchor': 'middle', class: 'edge-text' }, `${w.from} → ${w.to}`); graph.append(label);
  });
  plan.instances.forEach((n, i) => { const x = positions.get(n.name); const group = svgElement('g', { 'data-component': n.name }); group.append(svgElement('title', {}, n.name), svgElement('rect', { x: x - 80, y: y - 22, width: 160, height: 44, rx: 3, class: 'node-box' }), svgElement('text', { x, y: y + 5, 'text-anchor': 'middle', class: 'node-text', 'font-size': Math.max(9, Math.min(13, 150 / Math.max(n.name.length, 1))) }, `${i} / ${n.name}`)); graph.append(group); });
}
$('download').onclick = () => { if (!canonical) return; const url = URL.createObjectURL(new Blob([canonical], { type: 'application/json;charset=utf-8' })); const a = document.createElement('a'); a.href = url; a.download = 'plan.json'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); };
for (const button of document.querySelectorAll('[data-case]')) button.onclick = async () => {
  invalidate(); const token = revision; $('status').textContent = '正在载入本地示例…';
  try {
    const response = await fetch(`./examples/${button.dataset.case}.json`); if (!response.ok) throw new Error('示例清单读取失败');
    const text = await response.text(), m = JSON.parse(text);
    const paths = [...new Set(m.components.map(c => c.path))];
    const loaded = await Promise.all(paths.map(async path => { const r = await fetch(`./examples/${path}`); if (!r.ok) throw new Error(`示例组件读取失败：${path}`); return new File([await r.arrayBuffer()], path); }));
    if (token !== revision) return;
    $('manifest').value = text; files = loaded; $('manifest-name').textContent = `${button.textContent}示例`; $('file-count').textContent = `${files.length} 个文件`; $('manifest-file').value = ''; $('component-files').value = ''; renderMapping(); $('status').textContent = '示例已载入，点击检查以查看真实结果。';
  } catch (e) { if (token === revision) showError(localError('BROWSER_EXAMPLE', String(e))); }
};
