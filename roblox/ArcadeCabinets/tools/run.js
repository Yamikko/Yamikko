// run.js — exécute run.lua dans fengari (Lua 5.3 en JS) et écrit scene.json
// usage : NODE_PATH=<node_modules> node run.js <fxTime> <out.json>
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const here = __dirname;
const fxTime = parseFloat(process.argv[2] || '0.3');
const out = process.argv[3] || path.join(here, 'scene.json');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const setStr = (name, s) => { lua.lua_pushstring(L, to_luastring(s)); lua.lua_setglobal(L, to_luastring(name)); };
setStr('BUILDER_SRC', fs.readFileSync(path.join(here, '..', 'BuildArcadeCabinets.lua'), 'utf8'));
setStr('MOCK_SRC', fs.readFileSync(path.join(here, 'roblox_mock.lua'), 'utf8'));
lua.lua_pushnumber(L, fxTime); lua.lua_setglobal(L, to_luastring('FX_TIME'));
let result = null;
lua.lua_pushjsfunction(L, (L) => { result = lua.lua_tojsstring(L, 1); return 0; });
lua.lua_setglobal(L, to_luastring('__emit'));

const src = fs.readFileSync(path.join(here, 'run.lua'), 'utf8');
if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('run.lua')) !== lua.LUA_OK ||
    lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.error('ERREUR LUA :', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
const scene = JSON.parse(result);
scene.report.forEach(r => console.log('  ' + r));
fs.writeFileSync(out, JSON.stringify(scene));
console.log('scene ->', out, scene.items.length, 'items');
