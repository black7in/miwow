// Voz de MiWow (fase 1: voz de GRUPO en el cliente web). Ver docs/voz.md
//
// El audio va por LiveKit (SFU, WebRTC). Este modulo es el "hub" que une tres piezas sin que el jugador pueda
// hacerse pasar por otro:
//
//   worldserver (mod-miwow, MiWowVoice.cpp) --TCP 127.0.0.1 (enlace)--> aqui
//       TICKET <nonce> <guid> <nombre>   el modulo le manda al jugador "VOICE_TOKEN <nonce>" por el protocolo MIWOW
//       ROOM   <guid> <sala|vacio>       sala de voz que le toca (grupo nativo) o ninguna
//       CMD    <guid> <mic|speaker> 0/1  botones del juego (Lua -> MIWOW -> modulo -> aqui -> navegador)
//       GONE   <guid>                    logout
//   aqui --enlace--> worldserver
//       STATE  <guid> <voz 0/1> <en sala 0/1> <mic 0/1> <altavoz 0/1> <error>
//       SPEAK  <guid> 0/1
//
//   El tunel del juego (/tcp/, server.js) pasa por aqui: el "VOICE_TOKEN <nonce>" que el worldserver le manda a ESE
//   jugador viaja en claro (en 3.3.5 solo va cifrada la cabecera de cada paquete). Al verlo, la sesion del navegador
//   (cookie wsid) queda ligada a ese personaje. Un nonce solo vale si lo registro el modulo y se usa una vez.
//
//   navegador (public/voice/voice.js) --WS /voice-ws (cookie)--> aqui: recibe la sala y su token de LiveKit, manda
//   su estado y si esta hablando. El audio va del navegador a LiveKit (/livekit/* pasa por server.js).
'use strict';
const net = require('net');
const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

const DEFAULTS = {
  enabled: false,
  linkHost: '127.0.0.1',   // enlace con el worldserver (solo local)
  linkPort: 8091,
  linkSecret: '',          // igual que MiWow.Voice.LinkSecret en mod_miwow.conf
  livekitHost: '127.0.0.1', // LiveKit (señalizacion); /livekit/* se reenvia aqui
  livekitPort: 7880,
  livekitUrl: '',          // URL publica de LiveKit para el navegador; '' = la misma web + /livekit
  apiKey: '',              // claves de LiveKit (livekit.yaml "keys"); en local con --dev: devkey / secret
  apiSecret: '',
  tokenTtlSec: 6 * 3600,
};

const MARK = Buffer.from('VOICE_TOKEN\t');
const NONCE_LEN = 32;
const TICKET_TTL_MS = 5 * 60 * 1000;

module.exports = function createVoice(CONFIG, { log, readSid }) {
  const cfg = { ...DEFAULTS, ...(CONFIG.voice || {}) };
  if (!cfg.enabled) return null;
  if (!cfg.linkSecret || !cfg.apiKey || !cfg.apiSecret) {
    log('VOZ: desactivada (faltan voice.linkSecret / apiKey / apiSecret en config.json)');
    return null;
  }

  const tickets = new Map();  // nonce -> { guid, name, t }
  const seen = new Map();     // nonce visto en el tunel antes que su TICKET (llegan por sockets distintos) -> { sid, t }
  const players = new Map();  // guid -> { name, room }
  const sidGuid = new Map();  // sid -> guid
  const clients = new Map();  // sid -> Set(ws)
  let link = null;            // socket del worldserver (autenticado)

  // ======================= LiveKit: token JWT (HS256) =======================
  const b64u = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
  function makeToken(guid, name, room) {
    const now = Math.floor(Date.now() / 1000);
    const head = b64u({ alg: 'HS256', typ: 'JWT' });
    const body = b64u({
      iss: cfg.apiKey, sub: 'p' + guid, name, nbf: now - 10, exp: now + cfg.tokenTtlSec,
      // Solo microfono: nada de video, pantalla ni datos
      video: { room, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: false, canPublishSources: ['microphone'] },
    });
    const sig = crypto.createHmac('sha256', cfg.apiSecret).update(head + '.' + body).digest('base64url');
    return `${head}.${body}.${sig}`;
  }

  // ======================= Navegadores (/voice-ws) =======================
  const wss = new WebSocketServer({ noServer: true, maxPayload: 4096, perMessageDeflate: false });
  const sendWs = (ws, msg) => { if (ws.readyState === 1) ws.send(JSON.stringify(msg)); };
  const sidsOf = guid => [...sidGuid].filter(([, g]) => g === guid).map(([s]) => s);

  function roomMessage(sid) {
    const guid = sidGuid.get(sid);
    const p = guid && players.get(guid);
    if (!p || !p.room) return { type: 'room', room: null };
    return { type: 'room', room: p.room, name: p.name, url: cfg.livekitUrl, token: makeToken(guid, p.name, p.room) };
  }
  function pushRoom(sid) {
    const msg = roomMessage(sid);
    for (const ws of clients.get(sid) || []) sendWs(ws, msg);
  }
  // Estado agregado de las pestanas de una sesion (normalmente una)
  function reportState(sid) {
    const guid = sidGuid.get(sid);
    if (!guid) return;
    const set = clients.get(sid);
    const s = set && [...set].map(ws => ws.voiceState).find(Boolean);
    if (!s) return sendLink(['STATE', guid, 0, 0, 0, 0, '']);
    sendLink(['STATE', guid, 1, s.inRoom ? 1 : 0, s.mic ? 1 : 0, s.speaker ? 1 : 0, s.err || '']);
  }

  wss.on('connection', (ws, sid) => {
    if (!clients.has(sid)) clients.set(sid, new Set());
    clients.get(sid).add(ws);
    ws.voiceState = { inRoom: false, mic: false, speaker: true, err: '' };
    ws.speakTimes = [];
    sendWs(ws, { type: 'hello' });
    sendWs(ws, roomMessage(sid));
    reportState(sid);

    ws.on('message', data => {
      let m; try { m = JSON.parse(data.toString('utf8')); } catch { return; }
      const guid = sidGuid.get(sid);
      if (m.type === 'state') {
        ws.voiceState = { inRoom: !!m.inRoom, mic: !!m.mic, speaker: !!m.speaker, err: /^[a-z_]{0,32}$/.test(m.err || '') ? (m.err || '') : '' };
        reportState(sid);
      } else if (m.type === 'speaking' && guid) {
        // Tope: 10 cambios por segundo y pestana
        const now = Date.now();
        ws.speakTimes = ws.speakTimes.filter(t => now - t < 1000);
        if (ws.speakTimes.length >= 10) return;
        ws.speakTimes.push(now);
        sendLink(['SPEAK', guid, m.on ? 1 : 0]);
      }
    });
    ws.on('close', () => {
      const set = clients.get(sid);
      if (set) { set.delete(ws); if (!set.size) clients.delete(sid); }
      const guid = sidGuid.get(sid);
      if (guid) sendLink(['SPEAK', guid, 0]);
      reportState(sid);
    });
    ws.on('error', () => {});
  });

  // ======================= Enlace con el worldserver =======================
  function sendLink(fields) {
    if (link && !link.destroyed) link.write(fields.map(f => String(f).replace(/[\t\r\n]/g, ' ')).join('\t') + '\n');
  }

  function resetAll(why) {
    log('VOZ: sin enlace con el worldserver (' + why + '): todos fuera de sus salas');
    tickets.clear();
    seen.clear();
    players.clear();
    const sids = [...sidGuid.keys()];
    sidGuid.clear();
    for (const sid of sids) pushRoom(sid);
  }

  function onLinkLine(line) {
    const f = line.split('\t');
    switch (f[0]) {
      case 'TICKET': {
        const [, nonce, guid, name] = f;
        if (!/^[0-9a-f]{32}$/.test(nonce || '') || !(+guid > 0)) break;
        tickets.set(nonce, { guid: +guid, name: name || '', t: Date.now() });
        const early = seen.get(nonce);
        if (early) { seen.delete(nonce); bind(early.sid, nonce); }
        break;
      }
      case 'ROOM': {
        const guid = +f[1], room = f[2] || null;
        const p = players.get(guid);
        if (!p) { if (room) players.set(guid, { name: '', room }); break; }
        if (p.room === room) break;
        p.room = room;
        for (const sid of sidsOf(guid)) pushRoom(sid);
        break;
      }
      case 'CMD': {
        const guid = +f[1], what = f[2], on = f[3] === '1';
        if (what !== 'mic' && what !== 'speaker') break;
        for (const sid of sidsOf(guid)) for (const ws of clients.get(sid) || []) sendWs(ws, { type: 'cmd', what, on });
        break;
      }
      case 'GONE': {
        const guid = +f[1];
        players.delete(guid);
        for (const sid of sidsOf(guid)) { sidGuid.delete(sid); pushRoom(sid); }
        break;
      }
    }
  }

  const linkServer = net.createServer(sock => {
    sock.setNoDelay(true);
    sock.setEncoding('utf8');
    let buf = '', authed = false;
    const authTimer = setTimeout(() => { if (!authed) sock.destroy(); }, 5000);
    sock.on('data', d => {
      buf += d;
      if (buf.length > 1 << 20) { log('VOZ: enlace con demasiados datos sin fin de linea'); return sock.destroy(); }
      let i;
      while ((i = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, i).replace(/\r$/, ''); buf = buf.slice(i + 1);
        if (!authed) {
          const [op, secret] = line.split('\t');
          const a = Buffer.from(secret || ''), b = Buffer.from(cfg.linkSecret);
          if (op !== 'HELLO' || a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
            log('VOZ: enlace rechazado (clave incorrecta)');
            return sock.destroy();
          }
          authed = true; clearTimeout(authTimer);
          if (link) { link.destroy(); resetAll('nuevo enlace'); }
          link = sock;
          sock.write('WELCOME\n');
          log('VOZ: worldserver enlazado');
          continue;
        }
        onLinkLine(line);
      }
    });
    const gone = why => { clearTimeout(authTimer); if (link === sock) { link = null; resetAll(why); } };
    sock.on('close', () => gone('cerrado'));
    sock.on('error', e => gone(e.message));
  });
  linkServer.on('error', e => log(`VOZ: no se puede abrir el enlace en ${cfg.linkHost}:${cfg.linkPort} (${e.message}): sin voz`));
  linkServer.listen(cfg.linkPort, cfg.linkHost, () => log(`VOZ: enlace del worldserver en ${cfg.linkHost}:${cfg.linkPort}`));

  setInterval(() => {
    const old = Date.now() - TICKET_TTL_MS;
    for (const [k, t] of tickets) if (t.t < old) tickets.delete(k);
    for (const [k, t] of seen) if (t.t < Date.now() - 30_000) seen.delete(k);
  }, 60_000).unref();

  // ======================= Tunel del juego: ligar sesion <-> personaje =======================
  function bind(sid, nonce) {
    const t = tickets.get(nonce);
    if (!t) { if (seen.size < 10000) seen.set(nonce, { sid, t: Date.now() }); return; }
    tickets.delete(nonce);
    sidGuid.set(sid, t.guid);
    const p = players.get(t.guid);
    if (p) p.name = t.name; else players.set(t.guid, { name: t.name, room: null });
    log(`VOZ: sesion ${sid.slice(0, 8)} = ${t.name} (${t.guid})`);
    pushRoom(sid);
    reportState(sid);
  }

  // Cada trozo que el worldserver manda por el tunel; st = estado del tunel ({} al abrirlo)
  function sniff(st, sid, chunk) {
    const buf = st.tail ? Buffer.concat([st.tail, chunk]) : chunk;
    for (let i = buf.indexOf(MARK); i !== -1; i = buf.indexOf(MARK, i + 1)) {
      const at = i + MARK.length;
      if (at + NONCE_LEN > buf.length) break; // incompleto: sigue en la cola
      const nonce = buf.toString('latin1', at, at + NONCE_LEN);
      if (/^[0-9a-f]{32}$/.test(nonce)) bind(sid, nonce);
    }
    st.tail = Buffer.from(buf.subarray(Math.max(0, buf.length - (MARK.length + NONCE_LEN))));
  }

  // ======================= HTTP / WebSocket =======================
  // El "exports" del paquete no deja hacer require.resolve del UMD: ruta directa (version fija en package.json)
  const path = require('path');
  const LIVEKIT_JS = path.join(__dirname, 'node_modules', 'livekit-client', 'dist', 'livekit-client.umd.js');
  const VOICE_JS = path.join(__dirname, 'public', 'voice', 'voice.js');
  if (!require('fs').existsSync(LIVEKIT_JS)) log('VOZ: AVISO, falta ' + LIVEKIT_JS + ' (npm ci)');

  // /livekit/<resto> -> LiveKit /<resto> (peticion normal: /rtc/validate)
  function proxyHttp(req, res) {
    const up = http.request({
      host: cfg.livekitHost, port: cfg.livekitPort, method: req.method,
      path: req.url.slice('/livekit'.length) || '/', headers: { ...req.headers, host: `${cfg.livekitHost}:${cfg.livekitPort}` },
    }, r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
    up.on('error', () => { if (!res.headersSent) { res.writeHead(502); res.end('livekit no responde'); } else res.destroy(); });
    req.pipe(up);
  }
  // Upgrade de WebSocket hacia LiveKit: se reenvia la peticion en bruto y luego se cruzan los dos sockets
  function proxyUpgrade(req, sock, head) {
    const up = net.connect(cfg.livekitPort, cfg.livekitHost, () => {
      const lines = [`${req.method} ${req.url.slice('/livekit'.length) || '/'} HTTP/1.1`];
      for (let i = 0; i < req.rawHeaders.length; i += 2) {
        const k = req.rawHeaders[i];
        lines.push(`${k}: ${k.toLowerCase() === 'host' ? `${cfg.livekitHost}:${cfg.livekitPort}` : req.rawHeaders[i + 1]}`);
      }
      up.write(lines.join('\r\n') + '\r\n\r\n');
      if (head && head.length) up.write(head);
      up.pipe(sock); sock.pipe(up);
    });
    const close = () => { up.destroy(); sock.destroy(); };
    up.on('error', close); sock.on('error', close);
    up.on('close', close); sock.on('close', close);
  }

  return {
    sniff,

    // true si la peticion era de voz (ya respondida)
    handleHttp(req, res, p, sid, sendStatic) {
      if (p === '/voice/voice.js') { sendStatic(req, res, VOICE_JS); return true; }
      if (p === '/voice/livekit-client.js') { sendStatic(req, res, LIVEKIT_JS); return true; }
      if (p.startsWith('/livekit/')) { proxyHttp(req, res); return true; }
      return false;
    },

    // true si el upgrade era de voz (ya gestionado)
    handleUpgrade(req, sock, head) {
      const p = new URL(req.url, 'http://x').pathname;
      if (p !== '/voice-ws' && !p.startsWith('/livekit/')) return false;
      const sid = readSid(req);
      if (!sid) { sock.end('HTTP/1.1 403 Forbidden\r\n\r\n'); return true; }
      if (p === '/voice-ws') wss.handleUpgrade(req, sock, head, ws => wss.emit('connection', ws, sid));
      else proxyUpgrade(req, sock, head);
      return true;
    },

    close() { linkServer.close(); for (const c of wss.clients) c.terminate(); },
  };
};
