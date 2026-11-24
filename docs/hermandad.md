# Temporadas de hermandad

Compilado y probado por el usuario (2026-11-21), commit `35dc84a`. Traido de `mod-guild-season` (repo `newserver-wotlk`,
SOLO LECTURA) a `modules/mod-miwow/src/guild/`. Decision del usuario: sin tocar esquemas ni el core.

**Disenos del original (leerlos antes de tocar esto)**: `mod-guild-season/doc/GUILD_SEASON_SYSTEM.md`,
`AIO_FRONTEND_INSTRUCTIONS.md` (las 4 ventanas) y `QUEST_GUILD_TYPE.md` (misiones). La ventana sigue las instrucciones
(se puede mejorar).

## Datos
- Definiciones en world (`db-world/2026_11_21_01_miwow_guild.sql`): `miwow_guild_quest` (sustituye a las columnas de
  `quest_template_addon` y al tipo de mision del core), `_perk`, `_rank`, `_vendor`, `_season`, `_prize`.
- Estado en characters (`db-characters/2026_11_21_00`): `miwow_guild_state/progress/member/claim/board/vendor_active/
  history` (sustituye a las columnas de `guild`/`guild_member`). Config `MiWow.Guild.*`.
- CONTENIDO DE PRUEBA en el SQL world: misiones 9500000-9500003 (sin objetivos, QuestSortID -400), premios (bolsas) y
  tienda (5 bolsas/tabardo).

## Misiones
- `QuestSortID = -400` solo pone las misiones en la categoria "Hermandad" del registro (`questsort_dbc` 400, al cliente
  con `Build-Dbc`); la de hermandad la marca `miwow_guild_quest`.
- Puntos: individual = en cada entrega (pocos); de grupo = solo la primera entrega de la hermandad mientras sigue en el
  tablon (mas); reputacion siempre, a cada uno.
- Requisito al COMPLETARLA (objetivos cumplidos, p. ej. al morir el jefe; NO al entregarla): hermandad y, si es de grupo
  (`RequiredMembers` N > 0), ir en grupo/banda con N miembros de la hermandad conectados (contando al personaje; como el
  original, sin mirar el mapa). Si no, no se completa (sin estado "Fallida"), via `OnPlayerBeforeQuestComplete`; queda
  bloqueada (`miwow_guild_quest_block`) hasta abandonarla/reaceptarla, porque con los objetivos llenos el core no vuelve
  a intentarlo salvo al entregar.

## Tablon e intendente
- Tablon = objeto 9500200 (`go_miwow_guild_board`, copia del "Wanted Board" 2713, `.gobject add`): relaciones de
  misiones EN MEMORIA (`GetGOQuestRelationMap`; rotan con el reinicio diario/semanal), recoge todas las de hermandad.
  Manda `GUILD_BOARD_OPEN` + la info y luego el gossip: el cliente pone su tablon en lugar de la lista nativa.
- Intendente 9500201 (`npc_miwow_guild_vendor`, `.npc add`): tienda PROPIA (`GUILD_BUY`, `Price` en cobre o el del
  objeto; a menos de 10 m). El heraldo PNJ 9500200 de antes se borro (su spawn pasado a objeto).
- Cambios a las listas del tablon solo en el hilo del mundo (`Update`; los comandos dejan peticion). Cerrojo
  `MiWowGuildSeason::GetLock()` (MapUpdate.Threads > 1). Expulsado desconectado -> se pone al dia en su login (`SyncMember`).

## Ventajas (pasivas)
- Hechizos PASIVOS aprendidos (libro, como los raciales; sin icono de beneficio), revisados al conectar y cada 3 s
  (`RefreshPerks`; al conectar `RemoveStalePerkSpells` olvida los 9504000-9504099 que ya no estan en `miwow_guild_perk`
  o con el sistema desactivado), en TODAS partes (eventos y BG/arenas incluidos).
- 15 hechizos propios `data/spells/hermandad.toml` (9504000-9504014, se guardan en `character_spell`) +
  `miwow_guild_perk` (`Effect` = grupo de rangos: solo se sabe el mas alto). Umbrales 2.500-150.000 PTH.
- Nativas por aura: montura (172), experiencia (200 + 291), reputacion (156), honor (281). Del modulo (aura DUMMY,
  valor = efecto 1): oro extra al banco de la hermandad (`OnPlayerBeforeLootMoney` + `Guild::ModifyBankMoney`), piedra
  de hogar -15 min (`ModifySpellCooldown` cada 3 s), reparar -10 %, vendedores -5 %, +50 % al resucitar, correo
  instantaneo (`MailScript`, hermandad de la cache de personajes), punto extra de profesion.
- Descartadas de Cataclysm por ser NO pasivas: resurreccion en masa, invocar al grupo, calderos/festines, vuelos mas
  rapidos. **Pedido del usuario para una sesion futura**: hacer esas (hechizos que se lanzan).

## Corregido respecto al original
`lock` sin comillas (palabra reservada), puntos de misiones fuera del tablon, limite diario que se reiniciaba al
reconectar, expulsion desconectado, ventajas pegadas a desconectados tras el cambio de temporada, rango del vendedor
sin aplicar.

## Cliente
`MiWowGuild.lua` (protocolo v13, `GUILD_*` en `docs/protocolo.md`): ventana 720x560 con 4 pestanas: Tablon
(diarias/semanales con su reinicio, RECLAMADA/DISPONIBLE, boton por mision -> ventana de misiones nativa y vuelta),
Hermandad (puntos, ventajas, premios del podio, ranking interno + clasificacion), Reputacion (estrellas, progreso,
tramos), Tienda (disponibles / con candado, confirmacion). Sin hermandad no se abre. Pestana lateral en la ventana de
hermandad nativa, `/temporada`, `/miwow hermandad`. GM: `.miwow guild info|points|rep|rotate [daily|weekly]|endseason`.
