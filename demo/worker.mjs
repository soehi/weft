import { compile_json } from './planner.mjs';
self.onmessage = ({ data }) => {
  try {
    const bytes = Object.create(null);
    for (const [name, buffer] of data.binaries) bytes[name] = Array.from(new Uint8Array(buffer));
    const result = JSON.parse(compile_json(data.manifest, JSON.stringify(bytes)));
    self.postMessage({ id: data.id, result });
  } catch (e) {
    self.postMessage({ id: data.id, result: { ok: false, diagnostic: { code: 'BROWSER_WORKER', stage: 'browser', message: String(e), location: {}, related: [] } } });
  }
};
self.postMessage({ ready: true });
