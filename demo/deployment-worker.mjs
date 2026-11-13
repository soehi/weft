import {seal_json} from './deployment-planner.mjs';
self.onmessage = ({data}) => {
  try {
    const bytes = Object.create(null);
    for (const [id, buffer] of data.binaries) bytes[id] = Array.from(new Uint8Array(buffer));
    self.postMessage({id: data.id, result: JSON.parse(seal_json(data.manifest, JSON.stringify(bytes)))});
  } catch (e) {
    self.postMessage({id: data.id, result: {ok: false, diagnostic: {code: 'BROWSER_INPUT', message: String(e)}}});
  }
};
self.postMessage({ready: true});
