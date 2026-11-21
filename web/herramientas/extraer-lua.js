// Extrae a archivos legibles el Lua que Last Havens lleva incrustado como texto dentro de Wow.wasm
// (interfaz tactil, mando, login/seleccion de personaje, DragonUI, encuestas...). Solo para LEERLO:
// el cliente lo ejecuta desde el wasm, no desde estos archivos.
//
// Uso:   node herramientas/extraer-lua.js [wasm] [carpeta-salida]
//        (por defecto cliente/Wow.original.wasm -> referencia/lua-lasthavens/)
//
// Como: el Lua esta en la seccion de datos como cadenas de texto terminadas en NUL. Se cogen los tramos de
// texto de >= 800 bytes que contienen "function" y "end". El wasm no guarda que nombre de archivo
// (WebTouch.lua...) corresponde a cada tramo: el nombre de salida se adivina por los globales que define.
// Los espacios de relleno al final de linea (los parches de igual longitud los dejan) se quitan.
'use strict';
const fs = require('fs');
const path = require('path');

const raiz = path.join(__dirname, '..');
const wasm = path.resolve(process.argv[2] || path.join(raiz, 'cliente', 'Wow.original.wasm'));
const salida = path.resolve(process.argv[3] || path.join(raiz, 'referencia', 'lua-lasthavens'));
const MIN = 800;

const b = fs.readFileSync(wasm);
const tramos = [];
let ini = -1;
for (let i = 0; i <= b.length; i++) {
  const c = i < b.length ? b[i] : 0;
  const texto = (c >= 0x20 && c < 0x7f) || c === 9 || c === 10 || c === 13 || c >= 0x80;
  if (texto) { if (ini < 0) ini = i; continue; }
  if (ini >= 0 && i - ini >= MIN) {
    const t = b.toString('latin1', ini, i);
    if (/\bfunction\b/.test(t) && /\bend\b/.test(t)) tramos.push({ off: ini, len: i - ini, t });
  }
  ini = -1;
}

// Nombre: el global con prefijo Web*/Lasthavens* mas repetido del tramo; si no hay, la primera funcion.
function adivinar(t) {
  const cuenta = new Map();
  for (const m of t.matchAll(/\b((?:Web|Lasthavens)[A-Z]\w+)/g)) cuenta.set(m[1], (cuenta.get(m[1]) || 0) + 1);
  let mejor = null, n = 0;
  for (const [k, v] of cuenta) if (v > n) { mejor = k; n = v; }
  if (mejor) return mejor;
  const f = t.match(/function\s+([\w.:]+)/);
  return f ? f[1].replace(/[.:]/g, '_') : 'sin_nombre';
}

// Piezas: Lua mas corto o sin "function" (p. ej. el que cambia los enlaces del login por su Discord). Van aparte como
// p_<offset>_<nombre>.lua para no cambiar la numeracion de los tramos (la documentacion se refiere a ellos por numero).
const piezas = [];
ini = -1;
for (let i = 0; i <= b.length; i++) {
  const c = i < b.length ? b[i] : 0;
  const texto = (c >= 0x20 && c < 0x7f) || c === 9 || c === 10 || c === 13 || c >= 0x80;
  if (texto) { if (ini < 0) ini = i; continue; }
  if (ini >= 0 && i - ini >= 60) {
    const t = b.toString('latin1', ini, i);
    const esTramo = i - ini >= MIN && /\bfunction\b/.test(t) && /\bend\b/.test(t);
    const lua = /\bend\b/.test(t) && /\b(local|then|SetScript|_G\[)\b/.test(t) && !/#version|vec4|precision /.test(t);
    if (lua && !esTramo) piezas.push({ off: ini, len: i - ini, t });
  }
  ini = -1;
}

fs.rmSync(salida, { recursive: true, force: true });
fs.mkdirSync(salida, { recursive: true });
const indice = ['# Lua incrustado en ' + path.basename(wasm) + ' (' + b.length + ' bytes)', '# n\toffset\tbytes\tarchivo\tprimera linea'];
tramos.forEach((r, i) => {
  const limpio = r.t.split(/\r?\n/).map(l => l.replace(/[ \t]+$/, '')).join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
  const nombre = String(i + 1).padStart(2, '0') + '_' + adivinar(r.t) + '.lua';
  fs.writeFileSync(path.join(salida, nombre), '-- Extraido de ' + path.basename(wasm) + ' offset ' + r.off + ' (' + r.len + ' bytes). Codigo de Last Havens: solo lectura.\n' + limpio);
  const primera = (limpio.split('\n').find(l => l.trim()) || '').slice(0, 100);
  indice.push([i + 1, r.off, r.len, nombre, primera].join('\t'));
});
indice.push('# piezas (Lua corto o sin "function")');
for (const r of piezas) {
  const limpio = r.t.split(/\r?\n/).map(l => l.replace(/[ \t]+$/, '')).join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
  const nombre = 'p_' + r.off + '_' + adivinar(r.t) + '.lua';
  fs.writeFileSync(path.join(salida, nombre), '-- Extraido de ' + path.basename(wasm) + ' offset ' + r.off + ' (' + r.len + ' bytes). Codigo de Last Havens: solo lectura.\n' + limpio);
  const primera = (limpio.split('\n').find(l => l.trim()) || '').slice(0, 100);
  indice.push(['p', r.off, r.len, nombre, primera].join('\t'));
}
fs.writeFileSync(path.join(salida, 'indice.txt'), indice.join('\n') + '\n');
console.log(tramos.length + ' tramos + ' + piezas.length + ' piezas -> ' + salida);
