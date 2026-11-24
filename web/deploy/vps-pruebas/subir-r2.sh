#!/usr/bin/env bash
# Sube el cliente del VPS a R2 (lo sirve el Worker, web/deploy/worker). Desde el VPS: su conexion va sobrada.
#   game/<ruta en minuscula>   Data/*.MPQ, Data/<locale>/** (menos realmlist.wtf), Interface/AddOns/Blizzard_*/**
#   web/Wow.js, web/Wow.wasm   (los de cliente-web: el wasm parcheado)
# "sync": game/ queda IGUAL que el disco (borra de R2 lo que no este en el VPS). Re-ejecutable: salta lo que no cambio.
# Credenciales: remote "r2" en ~/.config/rclone/rclone.conf (permisos 600). rclone en ~/bin/rclone.
# Uso:  bash subir-r2.sh            todo
#       bash subir-r2.sh parche     solo Data/patch-4.MPQ (lo llama publicar-vps.ps1 -Parche)
#       bash subir-r2.sh web        solo Wow.js / Wow.wasm (lo llama publicar-vps.ps1)
#       bash subir-r2.sh simular    lista lo que haria, sin subir ni borrar
set -euo pipefail
RUTA=${RUTA:-/opt/miwow-juego}
REMOTE=${REMOTE:-r2:wotlk-cliente}
RCLONE=${RCLONE:-$HOME/bin/rclone}
LOCALE=${LOCALE:-esES}
MODO=${1:-todo}
FLAGS=(--copy-links --transfers 4 --s3-chunk-size 64M --s3-upload-concurrency 8
       --retries 5 --low-level-retries 20 --stats 30s --stats-one-line --stats-log-level NOTICE)
if [ "$MODO" = simular ]; then FLAGS+=(--dry-run); fi

if [ "$MODO" = parche ]; then
  "$RCLONE" copyto "$RUTA/cliente/Data/patch-4.MPQ" "$REMOTE/game/data/patch-4.mpq" "${FLAGS[@]}"
  "$RCLONE" lsl "$REMOTE/game/data/patch-4.mpq"
  exit 0
fi
if [ "$MODO" = web ]; then
  for w in Wow.js Wow.wasm; do "$RCLONE" copyto "$RUTA/cliente-web/$w" "$REMOTE/web/$w" "${FLAGS[@]}"; done
  "$RCLONE" lsl "$REMOTE/web"
  exit 0
fi

# Arbol de enlaces con las rutas en minuscula (las claves de R2 son en minuscula; el Worker baja la ruta pedida)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$RUTA/cliente"
{
  find Data -maxdepth 1 -type f -iname '*.mpq'
  if [ -d "Data/$LOCALE" ]; then find "Data/$LOCALE" -type f ! -iname realmlist.wtf; fi
  if [ -d Interface/AddOns ]; then
    find Interface/AddOns -mindepth 1 -maxdepth 1 -type d -name 'Blizzard_*' -exec find {} -type f \;
  fi
} | sort > "$tmp/lista"
dups=$(tr '[:upper:]' '[:lower:]' < "$tmp/lista" | sort | uniq -d)
if [ -n "$dups" ]; then echo "Rutas que chocan en minuscula:"; echo "$dups"; exit 1; fi
while IFS= read -r f; do
  k=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')
  mkdir -p "$tmp/game/$(dirname "$k")"
  ln -s "$RUTA/cliente/$f" "$tmp/game/$k"
done < "$tmp/lista"
echo "$(wc -l < "$tmp/lista") archivos, $(du -shL "$tmp/game" | cut -f1) -> $REMOTE/game"

"$RCLONE" sync "$tmp/game" "$REMOTE/game" "${FLAGS[@]}"
for w in Wow.js Wow.wasm; do
  "$RCLONE" copyto "$RUTA/cliente-web/$w" "$REMOTE/web/$w" "${FLAGS[@]}"
done
"$RCLONE" size "$REMOTE"
