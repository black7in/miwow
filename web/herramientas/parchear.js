// Aplica parches de texto (Lua incrustado) sobre Wow.original.wasm y genera Wow.wasm.
// Uso: node herramientas/parchear.js   (desde web/)
//
// Objetivo (decision del usuario 2026-11-21): el cliente web debe ser IGUAL que el de PC. Nada de Last Havens a la
// vista: Glue (login, seleccion y creacion de personaje) ORIGINAL, sin sus funciones de servidor (FAQ, encuestas,
// creadores, canal "world", "Go in now"...). Lo propio de MiWow va en nuestro patch-4.MPQ, que cargan los dos clientes.
// Se conserva lo que es del cliente web en si: HUD tactil y de mando (solo actua con webTouch o mando), voz,
// compatibilidad, aviso de version nueva.
//
// Cada parche sustituye un texto por otro de IGUAL o MENOR longitud (se rellena con espacios, que en Lua no cuentan).
// Para DESACTIVAR un tramo de Lua entero se cambia su primera sentencia (completa, de una linea) por "do return end":
// el wasm lo sigue ejecutando pero sale en esa linea; el resto del tramo solo tiene que seguir compilando.
// "contexto" (opcional): texto que debe aparecer poco despues; sirve para elegir entre varias apariciones de "de".
// Referencia: los tramos extraidos en referencia/lua-lasthavens/ (node herramientas/extraer-lua.js).
const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', 'cliente');   // web/cliente
const ORIGINAL = path.join(DIR, 'Wow.original.wasm');
const SALIDA = path.join(DIR, 'Wow.wasm');

const FIN = 'do return end';
const desactivar = (nombre, de, contexto) => ({ nombre, de, a: FIN, contexto });

const PARCHES = [
  // --- Glue original (antes de entrar al mundo) ---
  // 04: su pantalla de login entera (logo y texto "Lasthavens", Discord, crear/gestionar cuenta, cuentas guardadas
  //     -con contrasenas en el navegador-, version tactil). Sustituye a los 9 parches sueltos que habia sobre ella.
  desactivar('login de Last Havens (04_WebLoginLayout)',
    'if not AccountLoginUI or WebAccountCreateButton then return end'),
  // Fuera de 04: abre su dialogo de registro al cargar el login (sin 04 ya no existe, pero por si acaso).
  { nombre: 'apertura automatica del registro',
    de: 'if WebAccountDialog_Show then WebAccountDialog_Show("create") end',
    a:  '' },
  // Pieza p_7061044 (Glue, pequena): cambia los enlaces de Blizzard de los textos LOGIN_/AUTH_/RESPONSE_/REALM_LIST_
  // por su Discord, y engancha su embudo de estadisticas (WebCharacterCreated) a SELECT_LAST_CHARACTER.
  { nombre: 'embudo de estadisticas al crear personaje',
    de: 'WebFunnelFrame:SetScript("OnEvent", WebCharacterCreated)',
    a:  '' },
  desactivar('enlaces de Blizzard -> su Discord en los textos del login',
    'local discord = "https://discord.gg/trnNKjY5Ca"'),
  // 01: seleccion de personaje tactil/mando (tarjetas propias).
  desactivar('seleccion de personaje tactil (01_WebCharCreatePad)',
    'if (GetCVar("webTouch") ~= "1" and not WebPadSeen()) or not WebTouchScreen then return end',
    'local root, panel = CharacterSelectUI'),
  // 03: creacion de personaje tactil/mando (las tablas de colores de antes del guard se quedan: no estorban).
  desactivar('creacion de personaje tactil (03_WebCharCreatePad)',
    'if (GetCVar("webTouch") ~= "1" and not WebPadSeen()) or not WebTouchScreen then return end',
    'local root = CharacterCreateFrame'),
  // 05: boton AddOns de la seleccion de personaje -> su catalogo de addons (/addons/library.txt) y DragonUI.
  desactivar('catalogo de addons en la seleccion de personaje (05_WebApplyDragonUI)',
    'if not CharacterSelectAddonsButton or WebAddOnLibraryButton then return end'),

  // --- Funciones de su servidor dentro del juego ---
  desactivar('casilla "Go in now" del buscador de mazmorras (09)', 'local GO_IN_NOW = "lh:now"'),
  desactivar('FAQ de Last Havens en la ayuda (10)', 'local CATEGORIES = { "The Realm", "Playing", "Getting Help" }'),
  desactivar('programa de creadores (16)', 'if LasthavensCreatorFrame then return end'),
  desactivar('encuestas (17)', 'if LasthavensPollFrame then return end'),
  // 30: dictado por voz (boton de micro tactil: voz -> texto del chat con el reconocimiento del navegador). Decision del
  //     usuario 2026-11-24: fuera. Sin el tramo el boton WebVoiceChatToggle sigue oculto (se crea con Hide) y su HUD
  //     no le reserva sitio (mira IsShown). La voz de MiWow es otra cosa (docs/voz.md).
  desactivar('dictado por voz (30_WebVoiceChatToggle)',
    'if GetCVar("webTouch") ~= "1" and not WebPadLayout() or not WebVoiceChatToggle then return end'),
  // 31: entrar solo al canal "world" al conectar (el filtro de entradas/salidas y el limite de 256 bytes se quedan).
  { nombre: 'unirse al canal world (31)',
    de: 'if GetChannelName(CHANNEL) == 0 then',
    a:  'if false then' },
  // Cabecera de la tecla "Interactuar con lo mas cercano" en el menu de teclas.
  { nombre: 'cabecera de teclas "Lasthavens"',
    de: 'BINDING_HEADER_LASTHAVENS = "Lasthavens"',
    a:  'BINDING_HEADER_LASTHAVENS = "Web"' },
  // 29: aviso de version nueva del cliente web (se queda, sin la marca y en espanol).
  { nombre: 'aviso de version nueva: texto',
    de: 'text = "A Lasthavens update is out. No need to reload now: you\'ll get it the next time you open the game."',
    a:  'text = "Hay una versión nueva del juego. No hace falta recargar: la tendrás al volver a abrirlo."' },
  { nombre: 'aviso de version nueva: botones',
    de: 'button1 = "Reload Now",\n    button2 = "Keep Playing",',
    a:  'button1 = "Recargar",\n    button2 = "Seguir",' },
];

const buf = fs.readFileSync(ORIGINAL);
let fallos = 0;
for (const p of PARCHES) {
  // Longitudes en BYTES: el Lua del cliente es UTF-8 (una vocal con tilde ocupa 2).
  const de = Buffer.from(p.de, 'utf8');
  const a = Buffer.from(p.a, 'utf8');
  if (a.length > de.length) throw new Error(`"${p.nombre}": el reemplazo es mas largo que el original (${a.length} > ${de.length} bytes)`);
  const hits = [];
  for (let i = buf.indexOf(de); i >= 0; i = buf.indexOf(de, i + 1)) hits.push(i);
  const ok = p.contexto
    ? hits.filter(i => { const j = buf.indexOf(Buffer.from(p.contexto, 'utf8'), i + de.length); return j > 0 && j - i < 400; })
    : hits;
  if (ok.length === 0) { console.log(`X ${p.nombre}: no encontrado`); fallos++; continue; }
  if (ok.length > 1) throw new Error(`"${p.nombre}": aparece ${ok.length} veces, no es seguro (anade "contexto")`);
  a.copy(buf, ok[0]);
  buf.fill(0x20, ok[0] + a.length, ok[0] + de.length);   // relleno con espacios
  console.log(`OK ${p.nombre}`);
}
new WebAssembly.Module(buf); // valida que sigue siendo un wasm correcto
fs.writeFileSync(SALIDA, buf);
console.log(`Escrito ${SALIDA} (${buf.length} bytes, wasm valido)${fallos ? `, ${fallos} parche(s) sin aplicar` : ''}`);
