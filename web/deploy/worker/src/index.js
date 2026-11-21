// Worker delante del cliente web:
//   - Lo pesado (MPQ por bloques / Range, Wow.js, Wow.wasm) sale de R2  -> no gasta tu conexion.
//   - Lo demas (/play, manifest, /userdata, /tcp WebSocket, WTF, realmlist...) va a tu PC (server.js) por el tunel.
// Claves en R2 (ver subir-r2.ps1):  game/<ruta en minuscula>,  web/Wow.js,  web/Wow.wasm
//
// Variables (wrangler.toml / secrets):
//   ORIGIN      URL del tunel, p.ej. https://xxxx.trycloudflare.com   (var; vacio si el Worker va en una ruta de tu dominio)
//   LOCALE      esES                                                  (var)
//   BASIC_AUTH  "usuario:clave", igual que en server.js; vacio = abierto (secret)

const ISOLATION = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'X-Content-Type-Options': 'nosniff',
};
const NO_STORE = 'no-store';
const REVALIDATE = 'no-cache';
const IMMUTABLE = 'public, max-age=31536000, immutable';
const BIN = 'application/octet-stream';

const text = (status, body = '', extra = {}) =>
  new Response(body, { status, headers: { ...ISOLATION, 'Cache-Control': NO_STORE, 'Content-Type': 'text/plain; charset=utf-8', ...extra } });

function authOk(req, env) {
  if (!env.BASIC_AUTH) return true;
  const m = /^Basic\s+(.+)$/i.exec(req.headers.get('Authorization') || '');
  if (!m) return false;
  let got; try { got = atob(m[1]); } catch { return false; }
  const want = env.BASIC_AUTH;
  if (got.length !== want.length) return false;
  let d = 0; for (let i = 0; i < want.length; i++) d |= got.charCodeAt(i) ^ want.charCodeAt(i);
  return d === 0;
}

const decodePath = p => p.split('/').map(decodeURIComponent).join('/');

// Rutas que NO estan en R2: archivos del jugador y su realmlist (los sirve server.js por sesion)
const isUserFile = (rel, env) => {
  const k = rel.toLowerCase();
  return k.startsWith('wtf/') || k === `data/${(env.LOCALE || 'esES').toLowerCase()}/realmlist.wtf`;
};

// Reenvio a tu PC (incluye el upgrade de WebSocket de /tcp/...)
async function toOrigin(req, env) {
  // Sin ORIGIN (Worker en una ruta de tu dominio, p.ej. wow.tudominio.com/*) se pide al mismo host:
  // Cloudflare lo manda directo a tu servidor (el Worker no se llama a si mismo).
  const url = new URL(req.url);
  const target = env.ORIGIN ? new URL(url.pathname + url.search, env.ORIGIN) : url;
  const headers = new Headers(req.headers);
  headers.set('X-Forwarded-For', req.headers.get('CF-Connecting-IP') || '');
  headers.set('X-Forwarded-Proto', 'https');
  try {
    return await fetch(target, { method: req.method, headers, body: req.body, redirect: 'manual' });
  } catch (e) {
    return text(502, 'tu PC no responde (tunel/server.js apagado?)');
  }
}

// Wow.js / Wow.wasm con ETag
async function serveWeb(req, env, name) {
  const obj = await env.BUCKET.get('web/' + name, { onlyIf: req.headers });
  if (!obj) return null;
  const headers = new Headers({ ...ISOLATION, 'Cache-Control': REVALIDATE, 'Content-Type': name.endsWith('.wasm') ? 'application/wasm' : 'text/javascript; charset=utf-8' });
  headers.set('ETag', obj.httpEtag);
  if (!('body' in obj)) return new Response(null, { status: 304, headers });
  headers.set('Content-Length', obj.size);
  return new Response(req.method === 'HEAD' ? null : obj.body, { status: 200, headers });
}

// /game/<rel> con Range
async function serveGame(req, env, rel) {
  const key = 'game/' + rel.toLowerCase();
  const head = await env.BUCKET.head(key);
  if (!head) return null;
  const size = head.size;
  const cache = { ...ISOLATION, 'Cache-Control': REVALIDATE, 'Accept-Ranges': 'bytes', 'Content-Type': BIN };
  const m = /bytes=(\d+)-(\d*)/.exec(req.headers.get('Range') || '');
  if (!m) {
    const obj = await env.BUCKET.get(key);
    return new Response(req.method === 'HEAD' ? null : obj.body, { status: 200, headers: { ...cache, 'Content-Length': String(size) } });
  }
  const start = +m[1];
  const end = Math.min(m[2] ? +m[2] : size - 1, size - 1);
  if (start >= size || end < start) return text(416, '', { 'Content-Range': `bytes */${size}` });
  const len = end - start + 1;
  const obj = await env.BUCKET.get(key, { range: { offset: start, length: len } });
  return new Response(req.method === 'HEAD' ? null : obj.body, {
    status: 206,
    headers: { ...cache, 'Content-Length': String(len), 'Content-Range': `bytes ${start}-${end}/${size}` },
  });
}

// /blocks/<rel>/<size>-<index>-<N>k.bin
async function serveBlock(req, env, rel, size, idx, kb) {
  if (kb < 1 || kb > 16384) return text(400, 'bloque invalido');
  const key = 'game/' + rel.toLowerCase();
  const bs = kb * 1024, start = idx * bs;
  if (start >= size) return text(416, 'fuera de rango');
  const len = Math.min(bs, size - start);
  const obj = await env.BUCKET.get(key, { range: { offset: start, length: len } });
  if (!obj) return null;
  // R2 tiene otra version (p.ej. parche actualizado en tu PC pero aun no subido): que lo sirva tu PC.
  if (obj.size !== size) {
    try { await obj.body.cancel(); } catch {}
    console.log('tamano distinto en R2, voy al origen:', key, obj.size, '!=', size);
    return null;
  }
  return new Response(req.method === 'HEAD' ? null : obj.body, {
    status: 200,
    headers: { ...ISOLATION, 'Cache-Control': IMMUTABLE, 'Content-Type': BIN, 'Content-Length': String(len) },
  });
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const p = url.pathname;

    if (!authOk(req, env)) {
      return text(401, 'auth', { 'WWW-Authenticate': 'Basic realm="WoW web (pruebas)"' });
    }

    const isRead = req.method === 'GET' || req.method === 'HEAD';
    const isWs = (req.headers.get('Upgrade') || '').toLowerCase() === 'websocket';

    if (isRead && !isWs) {
      try {
        let res = null;
        if (p === '/Wow.js' || p === '/Wow.wasm') {
          res = await serveWeb(req, env, p.slice(1));
        } else if (p.startsWith('/game/')) {
          const rel = decodePath(p.slice(6));
          if (!isUserFile(rel, env)) res = await serveGame(req, env, rel);
        } else if (p.startsWith('/blocks/')) {
          const rest = decodePath(p.slice(8));
          const slash = rest.lastIndexOf('/');
          const rel = rest.slice(0, slash), leaf = rest.slice(slash + 1);
          const m = /^(\d+)-(\d+)-(\d+)k\.bin$/.exec(leaf);
          if (m && !isUserFile(rel, env)) res = await serveBlock(req, env, rel, +m[1], +m[2], +m[3]);
          // bundle-*.bin: server.js responde 404 y el cliente cae a bloques
          else if (/^bundle-[0-9a-f]+\.bin$/.test(leaf)) return text(404, 'no bundle');
        }
        if (res) return res;
        // No esta en R2 (p.ej. un parche nuevo aun sin subir): lo sirve tu PC.
      } catch (e) {
        console.log('R2 error', p, e && e.message);
      }
    }
    return toOrigin(req, env);
  },
};
