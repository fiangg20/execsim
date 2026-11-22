-- unc_sys.lua : UNC / sUNC functions, part 2
-- filesystem, console, crypt/encoding, input, miscellaneous, WebSocket

local H = __host
local G = _G
local X = H.X
local rawtype = H.rawtype
local def = X.def
local argError = X.argError
local typeof = X.typeof

local function needStr(v, n, fname)
  if rawtype(v) ~= "string" then argError(n, fname, "string", v) end
end

local function needNum(v, n, fname)
  if rawtype(v) ~= "number" then argError(n, fname, "number", v) end
end

------------------------------------------------------------------------
-- filesystem (sandboxed to the app's workspace folder)
------------------------------------------------------------------------
def("readfile", function(path)
  needStr(path, 1, "readfile")
  return H.fs_read(path)
end)

def("writefile", function(path, data)
  needStr(path, 1, "writefile")
  if rawtype(data) ~= "string" then data = tostring(data) end
  H.fs_write(path, data)
end)

def("appendfile", function(path, data)
  needStr(path, 1, "appendfile")
  if rawtype(data) ~= "string" then data = tostring(data) end
  H.fs_append(path, data)
end)

def("listfiles", function(path)
  if path ~= nil then needStr(path, 1, "listfiles") end
  return H.fs_list(path or "")
end)

def("isfile", function(path)
  needStr(path, 1, "isfile")
  return H.fs_isfile(path)
end)

def("isfolder", function(path)
  needStr(path, 1, "isfolder")
  return H.fs_isfolder(path)
end)

def("makefolder", function(path)
  needStr(path, 1, "makefolder")
  H.fs_mkdir(path)
end)

def("delfile", function(path)
  needStr(path, 1, "delfile")
  H.fs_delfile(path)
end)

def("delfolder", function(path)
  needStr(path, 1, "delfolder")
  H.fs_delfolder(path)
end)

def("loadfile", function(path, chunkname)
  needStr(path, 1, "loadfile")
  local ok, src = pcall(H.fs_read, path)
  if not ok then return nil, src end
  local fn, err = load(H.luau(src), "executor_file", "t", G)
  if not fn then return nil, err end
  return fn
end)

def("dofile", function(path)
  needStr(path, 1, "dofile")
  local src = H.fs_read(path)
  local fn, err = load(H.luau(src), "executor_file", "t", G)
  if not fn then error(err, 2) end
  return fn()
end)

def("getcustomasset", function(path, noCache)
  needStr(path, 1, "getcustomasset")
  return H.fs_url(path)
end)

------------------------------------------------------------------------
-- console window
------------------------------------------------------------------------
def("rconsolecreate", function() H.rcon("create") end, "consolecreate")
def("rconsoledestroy", function() H.rcon("destroy") end, "consoledestroy")
def("rconsoleclear", function() H.rcon("clear") end, "consoleclear")
def("rconsoleprint", function(text)
  local s = tostring(text)
  s = s:gsub("@@[%u_]+@@", "")
  H.rcon("print", s)
end, "consoleprint")
def("rconsoleinput", function()
  return H.rcon("input")
end, "consoleinput")
def("rconsolesettitle", function(title)
  H.rcon("title", tostring(title))
end, "rconsolename", "consolesettitle")

------------------------------------------------------------------------
-- crypt / encoding
------------------------------------------------------------------------
local function b64e(s)
  needStr(s, 1, "base64encode")
  return H.b64enc(s)
end
local function b64d(s)
  needStr(s, 1, "base64decode")
  return H.b64dec(s)
end

def("crypt.base64encode", b64e, "crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode")
def("crypt.base64decode", b64d, "crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode")
def("base64encode", b64e)
def("base64decode", b64d)

def("crypt.encrypt", function(data, key, iv, mode)
  needStr(data, 1, "crypt.encrypt")
  needStr(key, 2, "crypt.encrypt")
  return H.aes_encrypt(data, key, iv, mode or "CBC")
end)

def("crypt.decrypt", function(data, key, iv, mode)
  needStr(data, 1, "crypt.decrypt")
  needStr(key, 2, "crypt.decrypt")
  return H.aes_decrypt(data, key, iv, mode or "CBC")
end)

def("crypt.generatebytes", function(size)
  needNum(size, 1, "crypt.generatebytes")
  return H.b64enc(H.randbytes(math.floor(size)))
end)

def("crypt.generatekey", function()
  return H.b64enc(H.randbytes(32))
end)

def("crypt.hash", function(data, algorithm)
  needStr(data, 1, "crypt.hash")
  needStr(algorithm, 2, "crypt.hash")
  return H.hash(algorithm, data)
end)

def("lz4compress", function(data)
  needStr(data, 1, "lz4compress")
  return H.lz4c(data)
end)

def("lz4decompress", function(data, size)
  needStr(data, 1, "lz4decompress")
  return H.lz4d(data, size or 0)
end)

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
def("isrbxactive", function() return true end, "isgameactive")
def("mouse1click", function() H.input("click", 1) end)
def("mouse1press", function() H.input("press", 1) end)
def("mouse1release", function() H.input("release", 1) end)
def("mouse2click", function() H.input("click", 2) end)
def("mouse2press", function() H.input("press", 2) end)
def("mouse2release", function() H.input("release", 2) end)
def("mousemoveabs", function(x, y)
  needNum(x, 1, "mousemoveabs")
  needNum(y, 2, "mousemoveabs")
  H.input("move_abs", x, y)
end)
def("mousemoverel", function(x, y)
  needNum(x, 1, "mousemoverel")
  needNum(y, 2, "mousemoverel")
  H.input("move_rel", x, y)
end)
def("mousescroll", function(amount)
  needNum(amount, 1, "mousescroll")
  H.input("scroll", amount)
end)

------------------------------------------------------------------------
-- miscellaneous
------------------------------------------------------------------------
def("identifyexecutor", function() return X.execName, X.execVersion end, "getexecutorname")

def("messagebox", function(text, caption, flags)
  return H.messagebox(tostring(text), tostring(caption or ""), flags or 0)
end)

def("queue_on_teleport", function(code)
  needStr(code, 1, "queue_on_teleport")
  X.teleportQueue[#X.teleportQueue + 1] = code
end, "queueonteleport")

def("setclipboard", function(text)
  needStr(text, 1, "setclipboard")
  H.clip_set(text)
end, "toclipboard")

local FPSCAP = 0
def("setfpscap", function(n)
  needNum(n, 1, "setfpscap")
  FPSCAP = n
  H.fps(n)
end)

def("getfpscap", function() return FPSCAP end)

local METHODS = { GET = true, POST = true, PUT = true, DELETE = true, PATCH = true, HEAD = true, OPTIONS = true }

def("request", function(opts)
  if rawtype(opts) ~= "table" then argError(1, "request", "table", opts) end
  if rawtype(opts.Url) ~= "string" then error("invalid argument #1 to 'request' (Url must be a string)", 2) end
  local method = string.upper(opts.Method or "GET")
  if not METHODS[method] then error("invalid request method '" .. method .. "'", 2) end
  if (method == "GET" or method == "HEAD") and opts.Body ~= nil then
    error("GET and HEAD requests cannot contain a Body", 2)
  end
  local ok, code, msg, body, headers = pcall(H.http, method, opts.Url, opts.Headers, opts.Body)
  if not ok then error(code, 2) end
  return {
    Success = code >= 200 and code < 300,
    StatusCode = code,
    StatusMessage = msg,
    Headers = headers,
    Body = body,
  }
end, "http.request", "http_request")

------------------------------------------------------------------------
-- WebSocket (simulated echo server: Send() comes straight back as OnMessage)
------------------------------------------------------------------------
local WS = {}
def("WebSocket", WS)
def("WebSocket.connect", function(url)
  needStr(url, 1, "WebSocket.connect")
  if not (url:match("^wss?://")) then
    error("invalid argument #1 to 'WebSocket.connect' (invalid url, expected ws:// or wss://)", 2)
  end
  local onMessage = X.newSignal("OnMessage")
  local onClose = X.newSignal("OnClose")
  local closed = false
  local obj = { OnMessage = onMessage, OnClose = onClose }
  function obj.Send(self, msg, binary)
    if closed then error("WebSocket is closed", 2) end
    if rawtype(msg) ~= "string" then argError(1, "Send", "string", msg) end
    G.task.defer(function()
      if not closed then X.fire(onMessage, msg) end
    end)
  end
  function obj.Close(self)
    if closed then return end
    closed = true
    X.fire(onClose)
  end
  return obj
end)
