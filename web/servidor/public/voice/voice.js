// Voz de MiWow en el navegador (fase 1: voz de grupo). Ver docs/voz.md y servidor/voice.js.
// Habla con server.js por /voice-ws: recibe la sala (grupo nativo) y su token de LiveKit, y los botones del juego
// (cmd mic/speaker); le manda el estado y si el jugador esta hablando. El juego (Lua) no ve este codigo: todo pasa
// por el servidor (Lua -> MIWOW -> worldserver -> server.js -> aqui y vuelta).
(function () {
  'use strict';
  const trace = (...a) => { if (/[?&]voz=1/.test(location.search)) console.log('[voz]', ...a); };

  // Preferencias del jugador (solo en este navegador)
  const PREFS_KEY = 'miwowVoice';
  let prefs = { mic: false, speaker: true };
  try { prefs = { ...prefs, ...JSON.parse(localStorage.getItem(PREFS_KEY) || '{}') }; } catch {}
  const savePrefs = () => { try { localStorage.setItem(PREFS_KEY, JSON.stringify({ mic: prefs.mic, speaker: prefs.speaker })); } catch {} };

  let ws = null, retry = 1000;
  let lk = null;           // window.LivekitClient (se carga al primer "hello")
  let room = null, roomName = null, joining = null;
  let err = '';
  let speaking = false;
  const audios = new Set(); // <audio> de los demas

  const send = msg => { if (ws && ws.readyState === 1) ws.send(JSON.stringify(msg)); };
  const inRoom = () => !!(room && room.state === 'connected');
  const report = () => send({ type: 'state', inRoom: inRoom(), mic: prefs.mic && inRoom(), speaker: prefs.speaker, err });

  function setSpeaking(on) {
    if (on === speaking) return;
    speaking = on;
    send({ type: 'speaking', on });
  }

  function loadLivekit() {
    if (window.LivekitClient) return Promise.resolve(window.LivekitClient);
    return new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = '/voice/livekit-client.js';
      s.onload = () => resolve(window.LivekitClient);
      s.onerror = () => reject(new Error('no carga livekit-client'));
      document.head.appendChild(s);
    });
  }

  function applySpeaker() {
    for (const a of audios) a.muted = !prefs.speaker;
  }

  // El navegador no deja sonar audio sin un toque/clic: se reintenta en el siguiente
  function unlockAudio() {
    if (!room || room.canPlaybackAudio) return;
    const go = () => { if (room) room.startAudio().catch(() => {}); };
    document.addEventListener('pointerdown', go, { once: true, capture: true });
    document.addEventListener('keydown', go, { once: true, capture: true });
  }

  async function applyMic() {
    if (!inRoom()) return;
    try {
      await room.localParticipant.setMicrophoneEnabled(prefs.mic);
      if (err === 'mic_denied' || err === 'mic_error') err = '';
    } catch (e) {
      trace('micro:', e && e.name, e && e.message);
      prefs.mic = false;
      err = e && (e.name === 'NotAllowedError' || e.name === 'SecurityError') ? 'mic_denied' : 'mic_error';
      try { await room.localParticipant.setMicrophoneEnabled(false); } catch {}
    }
    if (!prefs.mic) setSpeaking(false);
    report();
  }

  async function leaveRoom() {
    const r = room;
    room = null; roomName = null;
    setSpeaking(false);
    for (const a of audios) a.remove();
    audios.clear();
    if (r) { try { await r.disconnect(); } catch {} }
  }

  async function joinRoom(msg) {
    if (!lk) return;
    await leaveRoom();
    const r = new lk.Room({
      adaptiveStream: false,
      dynacast: false,
      audioCaptureDefaults: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
      publishDefaults: { dtx: true, red: true, audioPreset: lk.AudioPresets.speech },
    });
    room = r; roomName = msg.room;

    r.on(lk.RoomEvent.TrackSubscribed, (track) => {
      if (track.kind !== 'audio') return;
      const el = track.attach();
      el.muted = !prefs.speaker;
      el.style.display = 'none';
      document.body.appendChild(el);
      audios.add(el);
    });
    r.on(lk.RoomEvent.TrackUnsubscribed, (track) => {
      for (const el of track.detach()) { audios.delete(el); el.remove(); }
    });
    r.on(lk.RoomEvent.AudioPlaybackStatusChanged, () => { if (!r.canPlaybackAudio) unlockAudio(); });
    r.on(lk.RoomEvent.Disconnected, () => { if (room === r) { room = null; roomName = null; setSpeaking(false); report(); } });
    r.on(lk.RoomEvent.Reconnected, report);
    r.localParticipant.on(lk.ParticipantEvent.IsSpeakingChanged, (on) => setSpeaking(!!on && prefs.mic));

    // '' = la misma web (server.js reenvia /livekit/* a LiveKit)
    const url = msg.url || (location.origin.replace(/^http/, 'ws') + '/livekit');
    try {
      await r.connect(url, msg.token, { autoSubscribe: true });
      if (room !== r) { r.disconnect(); return; }
      err = '';
      trace('en la sala', msg.room);
      unlockAudio();
      await applyMic();
    } catch (e) {
      trace('no conecta:', e && e.message);
      if (room === r) { room = null; roomName = null; }
      err = 'connect';
    }
    report();
  }

  async function onRoom(msg) {
    // Cola: un cambio de sala espera a que termine el anterior
    const prev = joining || Promise.resolve();
    joining = prev.then(async () => {
      if (!msg.room) { await leaveRoom(); report(); return; }
      if (msg.room === roomName && inRoom()) return;
      await joinRoom(msg);
    }).catch(e => trace('sala:', e && e.message));
  }

  function onCmd(msg) {
    if (msg.what === 'mic') { prefs.mic = !!msg.on; savePrefs(); applyMic(); }
    else if (msg.what === 'speaker') { prefs.speaker = !!msg.on; savePrefs(); applySpeaker(); if (msg.on) unlockAudio(); report(); }
  }

  function connect() {
    ws = new WebSocket(location.origin.replace(/^http/, 'ws') + '/voice-ws');
    ws.onopen = () => { retry = 1000; trace('conectado'); };
    ws.onmessage = async (e) => {
      let msg; try { msg = JSON.parse(e.data); } catch { return; }
      if (msg.type === 'hello') {
        try { lk = await loadLivekit(); } catch (x) { trace(x.message); err = 'load'; }
        report();
      } else if (msg.type === 'room') {
        onRoom(msg);
      } else if (msg.type === 'cmd') {
        onCmd(msg);
      }
    };
    ws.onclose = () => {
      ws = null;
      leaveRoom();
      // Voz desactivada en el servidor (404) o caido: se reintenta sin prisa
      setTimeout(connect, retry);
      retry = Math.min(retry * 2, 60_000);
    };
    ws.onerror = () => {};
  }

  connect();
  window.addEventListener('pagehide', () => { if (room) room.disconnect(); });
})();
