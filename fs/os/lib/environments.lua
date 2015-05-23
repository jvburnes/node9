local M = {}

local bit = require('bit')
local ffi = require('ffi')


-- Test code
--opts = getopt( arg, "ab" )
--for k, v in pairs(opts) do
--  print( k, v )
--end

function M.safe()
    return {
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        setfenv = setfenv,
        getfenv = getfenv,
        error = error,
        pcall = pcall,
        xpcall = xpcall,
        debug = debug,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack,
        setmetatable = setmetatable,   -- allows modules to alter their implementation
        coroutine = { create = coroutine.create, resume = coroutine.resume,
          running = coroutine.running, status = coroutine.status, yield = coroutine.yield,
          wrap = coroutine.wrap },
        string = { byte = string.byte, char = string.char, find = string.find,
          format = string.format, gmatch = string.gmatch, gsub = string.gsub,
          len = string.len, lower = string.lower, match = string.match,
          rep = string.rep, reverse = string.reverse, sub = string.sub,
          upper = string.upper },
        table = { insert = table.insert, maxn = table.maxn, remove = table.remove,
          sort = table.sort, concat = table.concat },
        math = { abs = math.abs, acos = math.acos, asin = math.asin,
          atan = math.atan, atan2 = math.atan2, ceil = math.ceil, cos = math.cos,
          cosh = math.cosh, deg = math.deg, exp = math.exp, floor = math.floor,
          fmod = math.fmod, frexp = math.frexp, huge = math.huge,
          ldexp = math.ldexp, log = math.log, log10 = math.log10, max = math.max,
          min = math.min, modf = math.modf, pi = math.pi, pow = math.pow,
          rad = math.rad, random = math.random, sin = math.sin, sinh = math.sinh,
          sqrt = math.sqrt, tan = math.tan, tanh = math.tanh },
        bit = bit,
        loadstring = loadstring,
        os = { clock = os.clock, difftime = os.difftime, time = os.time, date=os.date},
        dprint = print,  -- for debugging
        assert = assert,
        collectgarbage = collectgarbage,
        ffi = { string = ffi.string },
    }
end

return M
