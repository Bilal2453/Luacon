local parser = require 'argparse'()

local BASE_DIR    <const> = "C:/Lua/"
local LUA_VERSIONS<const> = {
  ["Lua 5.1"] = true,
  ["Lua 5.2"] = true,
  ["Lua 5.3"] = true,
  ["Lua 5.4"] = true,
  ["LuaJIT"]  = true,
}

local BATCH_EXT   <const> = "cmd"
local LUA_VERSION <const> = "Lua 5.4"
-- You might consider changing this for a system wide compatibility
-- this is just a dirty fix for my use case
local CONFIGS_DIR <const> = arg[0]..[[/../luacon-configs.lua]]

local defaultConfigs      = {
  CURRENT_LUA_VERSION    = LUA_VERSION,
  CURRENT_ROCKS_VERSION  = LUA_VERSION ~= "LuaJIT" and LUA_VERSION or "Lua 5.1",

  DIR_BATCH_PATH         = BASE_DIR.. 'cmd/',
  DIR_ROCKS_TREE         = BASE_DIR.. 'LuaRocks/',
  DIR_LUA_TREE           = BASE_DIR.. LUA_VERSION,
  NAME_LUA_INTERP        = (LUA_VERSION ~= "LuaJIT" and 'lua.exe' or 'luajit.exe'),
  EXTENSION_BATCH        = BATCH_EXT,
}

do -- set default configs that depends on other configs
  local dc = defaultConfigs

  dc ["DIR_LUA_BIN"]    = dc.DIR_LUA_TREE   .. '/bin/'
  dc ["DIR_LUA_INC"]    = dc.DIR_LUA_TREE   .. '/include/'
  dc ["DIR_LUA_LIB"]    = dc.DIR_LUA_TREE   .. '/bin/' -- On my machine, this is the only accepted dir by luarocks,
  -- even when it is just a regular lua installalition.
  -- you might want to change that up to Lua/lib.

  dc ["DIR_ROCKS_CORE"] = dc.DIR_ROCKS_TREE .. 'lua/luarocks/core/'
  dc ["DIR_LUA_BATCH" ] = dc.DIR_BATCH_PATH .. 'lua.' .. dc.EXTENSION_BATCH
  dc ["COMMAND_BATCH" ] = ('@"{DIR_LUA_BIN}%s" %%*')
    :format(dc.NAME_LUA_INTERP)
end

-----------------------------------------

local configs

local function wrapAsText(t, v)
  return (v or "[[").. t.. (v or "]]")
end

local function loadConfigs()
  if configs then return configs end -- No need to load again
  local data, err, success

  data = assert(io.open(CONFIGS_DIR, "r")):read('a')
  success, data, err = pcall(load(data, 'Configs'))

  if not success and data or not data and err then
    parser:error("Attempt loading configs file : ".. data or err or 'Unknown issue')
  end

  configs = data or {}
  return data
end

local function saveConfigs(c)
  c = c or configs
  local chunk = {"return {\n"}

  do
    local buffer = {}
    local function t(v)
      return type(v) == 'string' and wrapAsText(v) or v
    end

    for k, v in pairs(c) do
      table.insert(buffer, '\t'.. (k .. ' = ' .. t(v) .. ',\n'))
    end

    table.insert(chunk, table.concat(buffer))
    buffer = nil
  end

  table.insert(chunk, '}')
  chunk = table.concat(chunk)

  local f = assert(io.open(CONFIGS_DIR, "w+"), "Attempt to open the configs file.")
  assert(f:write(chunk))
  f:close()
end

local function newVersionConfigs(ver)
  if not LUA_VERSIONS[ver] then return end
  local c = {}

  for k, v in pairs(configs) do c[k] = v end

  c.CURRENT_LUA_VERSION = ver
  c.NAME_LUA_INTERP= (c.CURRENT_LUA_VERSION ~= "LuaJIT" and 'lua.exe' or 'luajit.exe')

  c.DIR_LUA_TREE   = BASE_DIR.. ver
  c.DIR_LUA_BIN    = c.DIR_LUA_TREE.. '/bin/'
  c.DIR_LUA_INC    = c.DIR_LUA_TREE.. '/include/'
  c.DIR_LUA_LIB    = c.DIR_LUA_TREE.. '/bin/'
  c.COMMAND_BATCH  = ('@"{DIR_LUA_BIN}%s" %%*'):format(c.NAME_LUA_INTERP)

  return c
end

local function changeLuaVersion(ver)
  if not LUA_VERSIONS[ver] then return end
  configs = newVersionConfigs(ver)
end

do -- load configs
  if not io.open(CONFIGS_DIR, "r") then
    io.open(CONFIGS_DIR, 'w'):close()
  end

  loadConfigs()

  if not next(configs) then
    configs = defaultConfigs
    saveConfigs()
  else -- writing any messing configs
    local d
    for k, v in pairs(defaultConfigs) do
      if not configs[k] then
        configs[k] = v
        d = true
      end
    end
    if d then saveConfigs() end
  end
end

-----------------------------------------

local function generateShellScript(ver)
  changeLuaVersion(ver or configs.CURRENT_LUA_VERSION)
  return (configs.COMMAND_BATCH:gsub('{(.-)}', configs))
end

local function generateLuaCMD(ver)
  if ver and not LUA_VERSIONS[ver] then return end

  local batchfile = assert(
    io.open(configs.DIR_LUA_BATCH, "w+"),
    "Attempt to open Lua batch file : ".. configs.DIR_LUA_BATCH
  )

  assert(
    batchfile:write(generateShellScript(ver)),
    "Attempt to write data to Lua batch file : ".. configs.DIR_LUA_BATCH
  )

  batchfile:close() -- Should handle possible errors as well?

  return true
end

local function generateRocksCMD(ver)
  if ver and not LUA_VERSIONS[ver] then return end
  local c = newVersionConfigs(ver or configs.CURRENT_LUA_VERSION)

  local HARDCODED_PATH<const> = c.DIR_ROCKS_CORE..'hardcoded.lua'

  local hardcodedData = assert(io.open(HARDCODED_PATH, "r")):read("a")
  local hardcodedFile = assert(
    io.open(HARDCODED_PATH, "w"),
    "Attempt to open Lua LuaRocks hardcoded.lua file : ".. HARDCODED_PATH
  )

  local newValues = {
    -- These are all values needs changing
    LUA_VERSION= wrapAsText(c.CURRENT_LUA_VERSION:sub(5)),
    LUA_INCDIR = wrapAsText(c.DIR_LUA_INC),
    LUA_LIBDIR = wrapAsText(c.DIR_LUA_LIB),
    LUA_BINDIR = wrapAsText(c.DIR_LUA_BIN),
    LUA_INTERPRETER = wrapAsText(c.NAME_LUA_INTERP),
  }

  -- Just going to replace the targeted values since the index is guarantee to exist
  hardcodedData = hardcodedData:gsub('([a-zA-z_]+)(%s*=%s*).-(,?\n)', function(index, eq, rest)
    return newValues[index] and (index.. eq.. newValues[index].. rest)
  end)

  assert(
    hardcodedFile:write(hardcodedData),
    "Attempt to write data to LuaRocks hardcoded.lua file : ".. HARDCODED_PATH
  )
end

-----------------------------------------

local function is_valid_version(v)
  v = v:lower():gsub('lua', ''):gsub('%.%s*', '')
  return ({ -- This map is only used here, so no need to define it as global
    ['51'] = 'Lua 5.1',
    ['52'] = 'Lua 5.2',
    ['53'] = 'Lua 5.3',
    ['54'] = 'Lua 5.4',
    ['jit'] = 'LuaJIT',
  })[v] or nil, "Invalid argument <version>\
    <version> should be one of (5.1, 5.2, 5.3, 5.4, jit)"
end

local function is_valid_target(t)
  return ({
    ['luarocks'] = 2,
    ['rocks'] = 2,
    ['rock'] = 2,
    ['lua'] = 1,
    ['l'] = 1,
    ['r'] = 2,
  })[t:lower()] or nil, "Invalid argument <target>\
    <target> should be one of (lua [l], luarocks [r|rocks])"
end


local change = parser:command('change c', 'Changes the lua version used by the targeted item')
change:argument('target',
  "The target that should use the specified version",
  nil, is_valid_target
)

change:argument('version',
  "The version that the target should use",
  nil, is_valid_version
)


change:action(function(args)
  if not args.change then os.exit() end

  if args.target == 1 then
    generateLuaCMD(args.version)
  elseif args.version ~= "LuaJIT" then
    generateRocksCMD(args.version)
  else
    parser:error 'invalid argument <version>\
      The version "LuaJIT" is not supported by the current target'
  end

  os.exit(0)
end)

parser:parse()
