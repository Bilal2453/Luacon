local parser = require 'argparse'()

-- You might consider changing this for a system wide compatibility
-- this is just a dirty fix for my use case
local CONFIGS_DIR <const> = arg[0]..[[/../luacon-configs.lua]]
local BASE_DIR    <const> = "C:/Lua/" -- Where all of the Lua installations exists
local LUA_VERSIONS<const> = {         -- Available Lua versions
  ["Lua 5.1"] = true,
  ["Lua 5.2"] = true,
  ["Lua 5.3"] = true,
  ["Lua 5.4"] = true,
  ["LuaJIT"]  = true,
}

local ERR_MSGS <const> = {
  openConfig   = "Attempt to open the config file : ",
  loadConfig   = "Attempt to load the config file : ",
  writeConfig  = "Attempt to write to the config file : ",
  createConfig = 'Attempt to create the config file "%s" : ',
  
  openBatch  = 'Attempt to open/create the batch file "%s" : ',
  writeBatch = "Attempt to write data to the batch file : ",
  
  hardcodedOpen  = "Attempt to open LuaRocks's hardcoded.lua : ",
  hardcodedWrite = "Attempt to write data to LuaRocks's hardcoded.lua file : "
}

do
  local oAssert = assert
  assert = function(val, ...)
    local msgs = {...}
    return oAssert(val, (msgs[2] or '')..msgs[1])
  end
end

--------------------------------------------------------
--             Handling Default Configs               --
--------------------------------------------------------

local LUA_VERSION <const> = 'Lua 5.4' -- The default Lua version to use

local defaultConfigs      = {
  CURRENT_LUA_VERSION      = LUA_VERSION,
  CURRENT_ROCKS_VERSION    = LUA_VERSION ~= 'LuaJIT' and LUA_VERSION or 'Lua 5.1',

  DIR_BATCH_PATH           = BASE_DIR .. 'cmd/',
  DIR_ROCKS_TREE           = BASE_DIR .. 'LuaRocks/',
  DIR_LUA_TREE             = BASE_DIR .. LUA_VERSION,
  NAME_LUA_INTERP          = (LUA_VERSION ~= 'LuaJIT' and 'lua.exe' or 'luajit.exe'),
  EXTENSION_BATCH          = 'cmd',
}

do -- Set default configs that depends on previous configs
  local dc = defaultConfigs

  dc["DIR_LUA_BIN"]    = dc.DIR_LUA_TREE   .. '/bin/'
  dc["DIR_LUA_INC"]    = dc.DIR_LUA_TREE   .. '/include/'
  
  -- On my machine, this is the only accepted dir by luarocks,
  -- even when it is just a regular lua installation, this seems to be a LuaRocks bug.
  -- You might want to change that up to "Lua/lib" instead.
  dc["DIR_LUA_LIB"]    = dc.DIR_LUA_TREE   .. '/bin/'

  dc["DIR_ROCKS_CORE"] = dc.DIR_ROCKS_TREE .. 'lua/luarocks/core/'
  dc["DIR_LUA_BATCH" ] = dc.DIR_BATCH_PATH .. 'lua.' .. dc.EXTENSION_BATCH
  dc["COMMAND_BATCH" ] = ('@"{DIR_LUA_BIN}%s" %%*'):format(dc.NAME_LUA_INTERP)
end

--------------------------------------------------------
--                  Handling Configs                  --
--------------------------------------------------------

local configs

local function wrapAsText(t, v)
  return ("%s%s%s"):format(v or "[[", t, v or "]]")
end

local function loadConfigs()
  if configs then return configs end -- No need to load again
  local data, err, success

  data = assert(io.open(CONFIGS_DIR, "r"), ERR_MSGS.openConfig):read('a')
  success, data, err = pcall(load(data, 'Configs'))

  if not success and data or not data and err then
    parser:error(ERR_MSGS.loadConfig..data or err or 'Unknown error')
  end

  configs = data or {}
  return data
end

local function saveConfigs(c)
  local chunk = {"return {\n"}
  c = c or configs

  do
    local buffer = {}
    local function t(v)
      return type(v) == 'string' and wrapAsText(v) or v
    end

    for k, v in pairs(c) do
      table.insert(buffer, ('\t%s = %s,\n'):format(k, t(v)))
    end

    table.insert(chunk, table.concat(buffer))
  end

  table.insert(chunk, '}')
  chunk = table.concat(chunk)

  local f = assert(io.open(CONFIGS_DIR, "w+"), ERR_MSGS.openConfig)
  assert(f:write(chunk), ERR_MSGS.writeConfig)
  f:close()
end

local function newVersionConfigs(ver)
  if not LUA_VERSIONS[ver] then return end

  local c = {}
  for k, v in pairs(configs) do c[k] = v end

  c.CURRENT_LUA_VERSION = ver
  c.NAME_LUA_INTERP = (c.CURRENT_LUA_VERSION ~= 'LuaJIT' and 'lua.exe' or 'luajit.exe')

  c.DIR_LUA_TREE    = BASE_DIR       .. ver
  c.DIR_LUA_BIN     = c.DIR_LUA_TREE .. '/bin/'
  c.DIR_LUA_INC     = c.DIR_LUA_TREE .. '/include/'
  c.DIR_LUA_LIB     = c.DIR_LUA_TREE .. '/bin/'
  c.COMMAND_BATCH   = ('@"{DIR_LUA_BIN}%s" %%*'):format(c.NAME_LUA_INTERP)

  return c
end

local function changeLuaVersion(ver)
  if not LUA_VERSIONS[ver] then return end
  configs = newVersionConfigs(ver)
end


do -- Load configs
  if not io.open(CONFIGS_DIR, 'r') then
    assert(io.open(CONFIGS_DIR, 'w'), ERR_MSGS.createConfig:format(CONFIGS_DIR)):close()
  end

  loadConfigs()

  if not next(configs) then
    configs = defaultConfigs
    saveConfigs()
  else -- Write missing configs (if any)
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

--------------------------------------------------------
--                     Generation                     --
--------------------------------------------------------

local function generateShellScript(ver)
  changeLuaVersion(ver or configs.CURRENT_LUA_VERSION)
  return (configs.COMMAND_BATCH:gsub('{(.-)}', configs))
end

local function generateLuaCMD(ver)
  if ver and not LUA_VERSIONS[ver] then return end

  local batchfile = assert(io.open(configs.DIR_LUA_BATCH, "w+"),
    ERR_MSGS.openBatch:format(configs.DIR_LUA_BATCH)
  )
  assert(batchfile:write(generateShellScript(ver)), ERR_MSGS.writeBatch)

  batchfile:close() -- Should handle possible errors as well?
  return true
end

local function generateRocksCMD(ver)
  if ver and not LUA_VERSIONS[ver] then return end
  local c = newVersionConfigs(ver or configs.CURRENT_LUA_VERSION)

  local HARDCODED_PATH<const> = c.DIR_ROCKS_CORE .. 'hardcoded.lua'

  local hardcodedData = assert(io.open(HARDCODED_PATH, "r"), ERR_MSGS.hardcodedOpen):read('a')
  local hardcodedFile = assert(io.open(HARDCODED_PATH, "w"), ERR_MSGS.hardcodedOpen)

  local newValues = {
    -- These are all the values need to be changed
    LUA_VERSION     = wrapAsText(c.CURRENT_LUA_VERSION:sub(5)),
    LUA_INCDIR      = wrapAsText(c.DIR_LUA_INC),
    LUA_LIBDIR      = wrapAsText(c.DIR_LUA_LIB),
    LUA_BINDIR      = wrapAsText(c.DIR_LUA_BIN),
    LUA_INTERPRETER = wrapAsText(c.NAME_LUA_INTERP),
  }

  -- Just going to replace the targeted fields since the index is guaranteed(?) to exist
  hardcodedData = hardcodedData:gsub('([a-zA-Z_]+)(%s*=%s*).-(,?\n)', function(index, eq, rest)
    return newValues[index] and ('%s%s%s%s'):format(index, eq, newValues[index], rest)
  end)

  assert(hardcodedFile:write(hardcodedData), ERR_MSGS.hardcodedWrite)
end

--------------------------------------------------------
--                    CLI Handling                    --
--------------------------------------------------------

local function is_valid_version(v)
  v = v:lower():gsub('lua', ''):gsub('%.%s*', '')
  return ({ -- This map is only used here, so no need to store it
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


local change = parser:command('change c', 'Changes the Lua version used by the targeted item')
change:argument('target',
  'The target which should start using the specified Lua version', nil, is_valid_target
)

change:argument('version',
  'The Lua version the target should use', nil, is_valid_version
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
