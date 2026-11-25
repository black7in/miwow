// Servidor para el cliente web 3.3.5a de MiWow (Wow.wasm de Last Havens, con su permiso). Ver docs/cliente-web.md
// Sirve: página /play, Wow.js/Wow.wasm, manifest + MPQ por bloques, datos de usuario (WTF)
// y un proxy WebSocket -> TCP hacia NUESTRO authserver/worldserver.
//
// Uso:   node server.js                (lee config.json si existe; si no, valores por defecto)
//        CONFIG=/ruta/config.json node server.js
// Ver config.example.json para todas las opciones. Las variables de entorno WOW_* pisan el archivo.
'use strict';
const http = require('http');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const net = require('net');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

// ======================= Configuración =======================
const DEFAULTS = {
  host: '127.0.0.1',            // en el VPS: 127.0.0.1 detrás de Caddy/nginx
  port: 8080,
  clientDir: 'D:/Wow',          // cliente 3.3.5a original (NO usar Wow3.3.5a-Limpio: puede estar roto)
  locale: 'esES',
  realmlist: '127.0.0.1',       // lo que se escribe en Config.wtf (el cliente igual lo ignora)
  // Destinos permitidos del proxy: puerto pedido -> "host" o "host:puerto" real. La IP que pida el cliente
  // se IGNORA siempre (trae fija la de Last Havens); solo cuenta el puerto. Con "host:puerto" se traduce el puerto
  // (el cliente pide el authserver siempre en el 3724; p. ej. { "3724": "127.0.0.1:3725" }).
  tcpRoutes: { '3724': '127.0.0.1', '8085': '127.0.0.1' },
  webDir: '../cliente',         // carpeta con Wow.js y Wow.wasm (relativa a este archivo)
  userDir: 'userdata',          // userdata/<idSesión>/WTF/...
  theirManifest: '../cliente/game-manifest.txt',
  // Archivos del juego servidos desde otra ruta (pisan a los de clientDir): ruta del juego -> archivo (relativo a este).
  // P. ej. { "Data/patch-4.MPQ": "../../client/patches/web/patch-4.MPQ" } (en local se copia a clientDir con Instalar-Parche).
  extraFiles: {},
  gameIndex: '',                // archivo "tamaño<TAB>ruta" con la lista del juego (cliente en R2): así el VPS no necesita los MPQ
  trustProxy: false,            // true si hay Caddy/nginx delante (usa X-Forwarded-For)
  basicAuth: '',                // "usuario:clave" para cerrar el acceso en pruebas ('' = abierto)
  cookieSecret: '',             // '' = se genera y se guarda en .cookie-secret
  maxWsPerIp: 6,
  wsIdleTimeoutSec: 900,        // cierra túneles sin tráfico (el world envía pings, no salta jugando)
  maxUserdataMB: 20,            // tope por jugador en /userdata
  loadEstimateMB: 36,           // medido 2026-11-22: ~34 MB; descarga aproximada de la primera carga hasta el login (barra de progreso de /play)
  logRequests: false,
};

function loadConfig() {
  const file = process.env.CONFIG || path.join(__dirname, 'config.json');
  let cfg = { ...DEFAULTS };
  if (fs.existsSync(file)) cfg = { ...cfg, ...JSON.parse(fs.readFileSync(file, 'utf8')) };
  const env = (k, conv = String) => { const v = process.env['WOW_' + k.toUpperCase()]; if (v !== undefined) cfg[k] = conv(v); };
  env('host'); env('port', Number); env('clientDir'); env('locale'); env('basicAuth'); env('gameIndex');
  env('trustProxy', v => v === '1' || v === 'true'); env('maxWsPerIp', Number);
  const abs = p => path.resolve(__dirname, p);
  cfg.webDir = abs(cfg.webDir); cfg.userDir = abs(cfg.userDir); cfg.theirManifest = abs(cfg.theirManifest);
  if (cfg.gameIndex) cfg.gameIndex = abs(cfg.gameIndex);
  cfg.extraFiles = Object.fromEntries(Object.entries(cfg.extraFiles || {}).map(([rel, p]) => [rel, abs(p)]));
  if (!cfg.cookieSecret) {
    const sf = path.join(__dirname, '.cookie-secret');
    if (!fs.existsSync(sf)) fs.writeFileSync(sf, crypto.randomBytes(32).toString('hex'));
    cfg.cookieSecret = fs.readFileSync(sf, 'utf8').trim();
  }
  return cfg;
}
const CONFIG = loadConfig();
const log = (...a) => console.log(new Date().toISOString().replace('T', ' ').slice(0, 19), ...a);
let voice = null; // voz (voice.js): se crea al arrancar si config.voice.enabled

// ======================= Manifest =======================
// Usamos las mayúsculas de SU manifest cuando el archivo coincide (el VFS podría distinguirlas).
const theirCase = new Map();
try {
  for (const line of fs.readFileSync(CONFIG.theirManifest, 'utf8').split('\n')) {
    const p = line.split('\t')[1]; if (p) theirCase.set(p.trim().toLowerCase(), p.trim());
  }
} catch {}

// Archivos del juego (comunes a todos). Se recalcula si cambian los MPQ (comprobación cada 30 s).
let gameFiles = new Map(); // ruta minúsculas -> { name, abs, size, mtime }
let gameStamp = '';
let lastScan = 0;
function walk(rootAbs, rel, out) {
  const abs = path.join(rootAbs, rel);
  let st; try { st = fs.statSync(abs); } catch { return; }
  if (st.isFile()) {
    // Extensión .MPQ siempre en mayúsculas: el cliente busca "patch-?.MPQ" y el VFS podría distinguirlas.
    const name = theirCase.get(rel.toLowerCase()) || rel.replace(/\.mpq$/i, '.MPQ');
    out.set(rel.toLowerCase(), { name, abs, size: st.size, mtime: st.mtimeMs });
    return;
  }
  for (const e of fs.readdirSync(abs)) walk(rootAbs, rel + '/' + e, out);
}
function scanGame(force = false) {
  if (!force && Date.now() - lastScan < 30_000) return;
  lastScan = Date.now();
  const out = new Map();
  if (CONFIG.gameIndex) {
    // Lista fija (la genera subir-r2.ps1). Los archivos pueden no estar en este disco: los sirve R2.
    let txt; try { txt = fs.readFileSync(CONFIG.gameIndex, 'utf8'); } catch (e) { log('ERROR leyendo gameIndex', e.message); return; }
    for (const line of txt.split(/\r?\n/)) {
      const [sz, rel] = line.split('\t'); if (!rel) continue;
      const name = theirCase.get(rel.toLowerCase()) || rel.replace(/\.mpq$/i, '.MPQ');
      out.set(rel.toLowerCase(), { name, abs: path.join(CONFIG.clientDir, rel), size: +sz, mtime: 0 });
    }
    const stamp = txt.length + ':' + out.size;
    if (stamp !== gameStamp) { gameFiles = out; gameStamp = stamp; log(`juego (gameIndex): ${out.size} archivos`); }
    return;
  }
  const data = path.join(CONFIG.clientDir, 'Data');
  for (const e of fs.readdirSync(data, { withFileTypes: true })) {
    if (e.isFile() && /\.mpq$/i.test(e.name)) walk(CONFIG.clientDir, 'Data/' + e.name, out);
  }
  walk(CONFIG.clientDir, 'Data/' + CONFIG.locale, out);
  walk(CONFIG.clientDir, 'Interface', out);
  // Solo los addons de Blizzard (como en R2/VPS): los de terceros que haya en clientDir no se sirven.
  for (const k of [...out.keys()]) {
    if (k.startsWith('interface/addons/') && !k.startsWith('interface/addons/blizzard_')) out.delete(k);
  }
  for (const [rel, abs] of Object.entries(CONFIG.extraFiles)) {
    let st; try { st = fs.statSync(abs); } catch { log('AVISO: no existe', abs, '(extraFiles)'); continue; }
    const name = theirCase.get(rel.toLowerCase()) || rel.replace(/\.mpq$/i, '.MPQ');
    out.set(rel.toLowerCase(), { name, abs, size: st.size, mtime: st.mtimeMs });
  }
  const stamp = [...out.values()].map(f => f.name + f.size + f.mtime).join('|');
  if (stamp !== gameStamp) { gameFiles = out; gameStamp = stamp; log(`juego: ${out.size} archivos`); }
}

// Archivos del jugador: userdata/<sid>/WTF/...
function userFiles(sid) {
  const out = new Map();
  walk(userRoot(sid), 'WTF', out);
  return out;
}
function lookup(rel, sid) {
  const k = rel.toLowerCase();
  if (k.startsWith('wtf/')) return userFiles(sid).get(k) || null;
  if (k === `data/${CONFIG.locale.toLowerCase()}/realmlist.wtf`) {
    const abs = path.join(userRoot(sid), 'WTF', 'realmlist.wtf');
    try { const st = fs.statSync(abs); return { name: rel, abs, size: st.size, mtime: st.mtimeMs }; } catch { return null; }
  }
  return gameFiles.get(k) || null;
}

// ======================= Sesiones (cookie firmada) =======================
// Cada navegador recibe un id aleatorio firmado con HMAC: separa los WTF de cada jugador
// y sirve de "pase" para el proxy WebSocket (solo quien cargó /play puede abrir túneles).
const sign = id => crypto.createHmac('sha256', CONFIG.cookieSecret).update(id).digest('base64url').slice(0, 22);
const newSid = () => { const id = crypto.randomBytes(16).toString('hex'); return id + '.' + sign(id); };
function readSid(req) {
  const m = /(?:^|;\s*)wsid=([0-9a-f]{32})\.([\w-]{22})/.exec(req.headers.cookie || '');
  if (!m) return null;
  const good = Buffer.from(sign(m[1])), got = Buffer.from(m[2]);
  return good.length === got.length && crypto.timingSafeEqual(good, got) ? m[1] : null;
}
const userRoot = sid => path.join(CONFIG.userDir, sid);
function ensureWtf(sid) {
  const wtf = path.join(userRoot(sid), 'WTF');
  const cfg = path.join(wtf, 'Config.wtf');
  if (fs.existsSync(cfg)) return;
  fs.mkdirSync(wtf, { recursive: true });
  fs.writeFileSync(cfg, [
    `SET locale "${CONFIG.locale}"`,
    `SET realmList "${CONFIG.realmlist}"`,
    `SET portal "${CONFIG.realmlist}"`,
    `SET accounttype "LK"`,
    `SET gxWindow "1"`,
    `SET readTOS "1"`, `SET readEULA "1"`, `SET readTerminationWithoutNotice "1"`,
    `SET movie "0"`,
  ].join('\r\n') + '\r\n');
  fs.writeFileSync(path.join(wtf, 'realmlist.wtf'), `set realmlist ${CONFIG.realmlist}\r\n`);
}
function dirSize(dir) {
  let n = 0;
  try { for (const e of fs.readdirSync(dir, { withFileTypes: true })) n += e.isDirectory() ? dirSize(path.join(dir, e.name)) : fs.statSync(path.join(dir, e.name)).size; } catch {}
  return n;
}

// ======================= HTTP =======================
const ISOLATION = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'X-Content-Type-Options': 'nosniff',
};
// Políticas de caché:
const NO_STORE = 'no-store';                                 // datos de usuario, manifest
const REVALIDATE = 'no-cache';                               // Wow.js/wasm/play: siempre pregunta (ETag)
const IMMUTABLE = 'public, max-age=31536000, immutable';     // bloques: la URL lleva el tamaño + ?v=
const MIME = {
  '.js': 'text/javascript; charset=utf-8', '.wasm': 'application/wasm', '.html': 'text/html; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8', '.json': 'application/json', '.webmanifest': 'application/manifest+json',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2',
};
const IMMUTABLE_ASSET = 'public, max-age=604800';            // fuentes y marca de /play

// Progreso de descarga por sesión (barra de carga de /play): bytes de datos del juego servidos.
// Solo ve lo que pasa por este servidor (en local/VPS; con R2 los bloques los sirve el Worker).
const progress = new Map(); // sid -> { bytes, files, t }
function countServed(sid, bytes) {
  const e = progress.get(sid) || { bytes: 0, files: 0, t: 0 };
  e.bytes += bytes; e.files++; e.t = Date.now();
  progress.set(sid, e);
}
setInterval(() => { const old = Date.now() - 3600_000; for (const [k, e] of progress) if (e.t < old) progress.delete(k); }, 600_000).unref();

function send(res, code, body = '', type = MIME['.txt'], extra = {}) {
  res.writeHead(code, { ...ISOLATION, 'Cache-Control': NO_STORE, 'Content-Type': type, ...extra });
  res.end(body);
}
// Archivo estático con ETag (para Wow.js, Wow.wasm, iconos...)
async function sendStatic(req, res, abs, cache = REVALIDATE, extra = {}) {
  let st; try { st = await fsp.stat(abs); } catch { return send(res, 404, 'not found'); }
  const etag = `"${st.size.toString(36)}-${Math.floor(st.mtimeMs).toString(36)}"`;
  const headers = { ...ISOLATION, 'Cache-Control': cache, ETag: etag, 'Content-Type': MIME[path.extname(abs)] || 'application/octet-stream', ...extra };
  if (req.headers['if-none-match'] === etag) { res.writeHead(304, headers); return res.end(); }
  res.writeHead(200, { ...headers, 'Content-Length': st.size });
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(abs).pipe(res);
}
// Trozo de archivo en streaming
function sendRange(res, code, abs, start, end, extra = {}) {
  const len = Math.max(0, end - start + 1);
  res.writeHead(code, { ...ISOLATION, 'Content-Type': 'application/octet-stream', 'Content-Length': len, ...extra });
  if (len === 0) return res.end();
  fs.createReadStream(abs, { start, end }).on('error', () => res.destroy()).pipe(res);
}
function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const c = []; let n = 0;
    req.on('data', d => { n += d.length; if (n > limit) { reject(new Error('demasiado grande')); req.destroy(); } else c.push(d); });
    req.on('end', () => resolve(Buffer.concat(c)));
    req.on('error', reject);
  });
}
const decodePath = p => p.split('/').map(decodeURIComponent).join('/');
// Detrás de Cloudflare la IP real viene en CF-Connecting-IP (Caddy sobrescribe X-Forwarded-For con la IP de Cloudflare)
const clientIp = req => (CONFIG.trustProxy && (req.headers['cf-connecting-ip'] || (req.headers['x-forwarded-for'] || '').split(',')[0].trim())) || req.socket.remoteAddress;

function basicAuthOk(req) {
  if (!CONFIG.basicAuth) return true;
  const m = /^Basic (.+)$/.exec(req.headers.authorization || '');
  if (!m) return false;
  const a = Buffer.from(Buffer.from(m[1], 'base64').toString()), b = Buffer.from(CONFIG.basicAuth);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// ======================= Rutas =======================
const unknown = new Set();
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;
  if (CONFIG.logRequests) log(clientIp(req), req.method, req.url);
  try {
    // Recursos públicos (el navegador los pide sin credenciales para "Instalar app")
    if (p === '/manifest.webmanifest') return sendStatic(req, res, path.join(__dirname, 'public', 'manifest.webmanifest'));
    if (p.startsWith('/icons/') && /^\/icons\/[\w.-]+$/.test(p)) return sendStatic(req, res, path.join(__dirname, 'public', p));
    if (/^\/(fonts|brand)\/[\w.-]+$/.test(p)) return sendStatic(req, res, path.join(__dirname, 'public', p), IMMUTABLE_ASSET);
    if (p === '/healthz') return send(res, 200, 'ok');

    if (!basicAuthOk(req)) return send(res, 401, 'auth', MIME['.txt'], { 'WWW-Authenticate': 'Basic realm="WoW web (pruebas)"' });

    // Página: entrega cookie de sesión si no tiene una válida
    if (p === '/' || p === '/play') {
      let sid = readSid(req); const extra = {};
      if (!sid) {
        const c = newSid(); sid = c.split('.')[0];
        extra['Set-Cookie'] = `wsid=${c}; Path=/; Max-Age=31536000; HttpOnly; SameSite=Strict${req.headers['x-forwarded-proto'] === 'https' || req.socket.encrypted ? '; Secure' : ''}`;
        log('nueva sesión', sid.slice(0, 8), clientIp(req));
      }
      ensureWtf(sid);
      return sendStatic(req, res, path.join(__dirname, 'play.html'), NO_STORE, extra);
    }
    if (p === '/Wow.js' || p === '/Wow.wasm') return sendStatic(req, res, path.join(CONFIG.webDir, p.slice(1)));
    if (p === '/server-alert.txt') return sendStatic(req, res, path.join(__dirname, 'public', 'server-alert.txt'), NO_STORE);

    // A partir de aquí hace falta sesión
    const sid = readSid(req);
    if (!sid) return send(res, 403, 'sin sesión: abre /play');

    if (voice && voice.handleHttp(req, res, p, sid, sendStatic)) return;

    if (p === '/progress') {
      const e = progress.get(sid) || { bytes: 0, files: 0 };
      return send(res, 200, JSON.stringify({ bytes: e.bytes, files: e.files, estimate: CONFIG.loadEstimateMB * 1048576 }), MIME['.json']);
    }

    if (p === '/game-manifest.txt') {
      scanGame(); ensureWtf(sid);
      const all = new Map([...gameFiles, ...userFiles(sid)]);
      const rlKey = `data/${CONFIG.locale.toLowerCase()}/realmlist.wtf`;   // el del jugador, con SU tamaño
      const rl = lookup(`Data/${CONFIG.locale}/realmlist.wtf`, sid);
      if (rl) all.set(rlKey, { ...rl, name: (gameFiles.get(rlKey) || {}).name || `Data/${CONFIG.locale}/realmlist.wtf` });
      const body = [...all.values()].sort((a, b) => a.name.localeCompare(b.name)).map(f => `${f.size}\t${f.name}`).join('\n') + '\n';
      return send(res, 200, body);
    }

    // Archivo con Range
    if (p.startsWith('/game/')) {
      const rel = decodePath(p.slice(6)); const f = lookup(rel, sid);
      if (!f) { log('404 /game/', rel); return send(res, 404, 'not found'); }
      if (!fs.existsSync(f.abs)) return send(res, 404, 'no esta en este servidor (va por R2)');
      const user = rel.toLowerCase().startsWith('wtf/');
      const m = /bytes=(\d+)-(\d*)/.exec(req.headers.range || '');
      const cache = { 'Cache-Control': user ? NO_STORE : REVALIDATE, 'Accept-Ranges': 'bytes' };
      if (!m) return sendRange(res, 200, f.abs, 0, f.size - 1, cache);
      const start = +m[1], end = Math.min(m[2] ? +m[2] : f.size - 1, f.size - 1);
      if (start >= f.size) return send(res, 416, '', MIME['.txt'], { 'Content-Range': `bytes */${f.size}` });
      if (!user) countServed(sid, end - start + 1);
      return sendRange(res, 206, f.abs, start, end, { ...cache, 'Content-Range': `bytes ${start}-${end}/${f.size}` });
    }

    // Bloques: /blocks/<ruta>/<size>-<index>-<N>k.bin   (bundle-*.bin -> 404, el cliente cae a bloques)
    if (p.startsWith('/blocks/')) {
      const rest = decodePath(p.slice(8));
      const slash = rest.lastIndexOf('/');
      const rel = rest.slice(0, slash), leaf = rest.slice(slash + 1);
      const m = /^(\d+)-(\d+)-(\d+)k\.bin$/.exec(leaf);
      if (m) {
        const f = lookup(rel, sid);
        if (!f) { log('404 bloque:', rel); return send(res, 404, 'no file'); }
        if (!fs.existsSync(f.abs)) return send(res, 404, 'no esta en este servidor (va por R2)');
        const [size, idx, kb] = [+m[1], +m[2], +m[3]];
        if (kb < 1 || kb > 16384) return send(res, 400, 'bloque inválido');
        const user = rel.toLowerCase().startsWith('wtf/');
        // Si el tamaño pedido no coincide, el archivo cambió: no cachear esa respuesta.
        const cache = !user && size === f.size ? IMMUTABLE : NO_STORE;
        if (size !== f.size) log(`aviso: tamaño pedido ${size} != real ${f.size} en ${rel}`);
        const bs = kb * 1024, start = idx * bs, end = Math.min(start + bs, f.size) - 1;
        if (!user) countServed(sid, Math.max(0, end - start + 1));
        return sendRange(res, 200, f.abs, start, end, { 'Cache-Control': cache });
      }
      if (/^bundle-[0-9a-f]+\.bin$/.test(leaf)) return send(res, 404, 'no bundle');
    }

    // Datos de usuario (WTF, SavedVariables, macros...) — carpeta propia de cada sesión
    if (p.startsWith('/userdata/')) {
      const root = userRoot(sid);
      const rel = decodePath(p.slice(10));
      const abs = path.resolve(root, rel);
      if (!abs.startsWith(root + path.sep)) return send(res, 403);
      if (req.method === 'PUT') {
        const body = await readBody(req, CONFIG.maxUserdataMB * 1024 * 1024);
        if (dirSize(root) + body.length > CONFIG.maxUserdataMB * 1024 * 1024) { log('cuota llena', sid.slice(0, 8)); return send(res, 413, 'cuota'); }
        await fsp.mkdir(path.dirname(abs), { recursive: true });
        const tmp = abs + '.tmp-' + process.pid;           // escritura atómica
        await fsp.writeFile(tmp, body); await fsp.rename(tmp, abs);
        if (CONFIG.logRequests) log('guardado', sid.slice(0, 8), rel);
        return send(res, 200, 'ok');
      }
      if (req.method === 'DELETE') { await fsp.rm(abs, { force: true }); return send(res, 200, 'ok'); }
      return fs.existsSync(abs) && fs.statSync(abs).isFile() ? sendStatic(req, res, abs, NO_STORE) : send(res, 404);
    }

    if (p.startsWith('/account/')) { await readBody(req, 65536).catch(() => {}); return send(res, 404, ''); }
    // /stats/freeze: "caja negra" del cliente (sesion anterior que acabo sin pagehide: cuelgue, pestana matada,
    // contexto WebGL perdido). Se guarda en el log para diagnosticar; el resto de /stats se descarta.
    if (p === '/stats/freeze') {
      const body = await readBody(req, 65536).catch(() => null);
      if (body) log('FREEZE', clientIp(req), body.toString('utf8').slice(0, 4000));
      return send(res, 204);
    }
    if (p.startsWith('/stats/') || p.startsWith('/polls/')) { await readBody(req, 65536).catch(() => {}); return send(res, 204); }
    if (p === '/addons/library.txt') return send(res, 404);

    const k = req.method + ' ' + p;
    if (!unknown.has(k) && unknown.size < 500) { unknown.add(k); log('DESCONOCIDO', k); }
    send(res, 404, 'not found');
  } catch (e) {
    log('ERROR', p, e.message);
    if (!res.headersSent) send(res, 500, 'error'); else res.destroy();
  }
});

// ======================= WebSocket -> TCP =======================
// /tcp/<ip>/<puerto>?ticket=..&rx=..   La IP se ignora: el destino sale de tcpRoutes[puerto].
const wss = new WebSocketServer({ noServer: true, maxPayload: 1 << 20, perMessageDeflate: false });
const wsPerIp = new Map();
server.on('upgrade', (req, sock, head) => {
  if (voice && voice.handleUpgrade(req, sock, head)) return;
  const url = new URL(req.url, 'http://x');
  const ip = clientIp(req);
  const m = /^\/tcp\/(\d+\.\d+\.\d+\.\d+)\/(\d+)$/.exec(url.pathname);
  const route = m && CONFIG.tcpRoutes[m[2]];
  const rm = route && /^([^:]+)(?::(\d+))?$/.exec(String(route));
  const host = rm && rm[1];
  const reject = (code, why) => { log(`WS rechazado (${why})`, ip, req.url.split('?')[0]); sock.end(`HTTP/1.1 ${code}\r\n\r\n`); };
  if (!host) return reject('403 Forbidden', 'destino no permitido');
  if (!basicAuthOk(req) && !readSid(req)) return reject('401 Unauthorized', 'sin auth');
  if (!readSid(req)) return reject('403 Forbidden', 'sin sesión');
  if ((wsPerIp.get(ip) || 0) >= CONFIG.maxWsPerIp) return reject('429 Too Many Requests', 'demasiadas conexiones');

  wss.handleUpgrade(req, sock, head, ws => {
    const port = rm[2] ? +rm[2] : +m[2];
    wsPerIp.set(ip, (wsPerIp.get(ip) || 0) + 1);
    const tag = `${ip} -> ${host}:${port}${port !== +m[2] ? ` (puerto pedido ${m[2]})` : ''}`;
    log(`WS abierto ${tag} (pedía ${m[1]})`);
    const tcp = net.connect(port, host);
    tcp.setNoDelay(true);
    let up = 0, down = 0, closed = false;
    const sid = readSid(req), sniffState = {};
    let idle;
    const touch = () => { clearTimeout(idle); idle = setTimeout(() => close('inactivo'), CONFIG.wsIdleTimeoutSec * 1000); };
    touch();
    tcp.on('data', d => {
      down += d.length; touch();
      if (voice) voice.sniff(sniffState, sid, d);
      if (ws.readyState !== 1) return;
      ws.send(d);
      // Contrapresión: si el navegador va lento, pausamos el TCP
      if (ws.bufferedAmount > 4 << 20) { tcp.pause(); const t = setInterval(() => { if (ws.bufferedAmount < 1 << 20 || ws.readyState !== 1) { clearInterval(t); tcp.resume(); } }, 50); }
    });
    ws.on('message', (d, isBinary) => { if (!isBinary) return; up += d.length; touch(); tcp.write(d); });
    const close = why => {
      if (closed) return; closed = true; clearTimeout(idle);
      wsPerIp.set(ip, wsPerIp.get(ip) - 1); if (wsPerIp.get(ip) <= 0) wsPerIp.delete(ip);
      log(`WS cerrado ${tag} (${why}) subido=${up} bajado=${down}`);
      tcp.destroy(); ws.close();
    };
    tcp.on('error', e => close('tcp ' + e.message));
    tcp.on('close', () => close('tcp cerrado'));
    ws.on('close', () => close('ws cerrado'));
    ws.on('error', e => close('ws ' + e.message));
  });
});

// ======================= Arranque =======================
fs.mkdirSync(CONFIG.userDir, { recursive: true });
scanGame(true);
voice = require('./voice')(CONFIG, { log, readSid });
server.listen(CONFIG.port, CONFIG.host, () => {
  log(`Listo: http://${CONFIG.host === '0.0.0.0' ? 'localhost' : CONFIG.host}:${CONFIG.port}/play`);
  log(`proxy TCP: ${Object.entries(CONFIG.tcpRoutes).map(([p, h]) => `${p}->${h}`).join(', ')}  basicAuth=${CONFIG.basicAuth ? 'sí' : 'no'}  trustProxy=${CONFIG.trustProxy}`);
});
const stop = () => { log('apagando...'); server.close(); if (voice) voice.close(); for (const c of wss.clients) c.terminate(); setTimeout(() => process.exit(0), 2000).unref(); };
process.on('SIGINT', stop); process.on('SIGTERM', stop);
