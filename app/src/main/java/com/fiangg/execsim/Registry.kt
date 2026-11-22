package com.fiangg.execsim

/**
 * Single source of truth for every UNC / sUNC function this simulator provides.
 * The Lua side (assets/lua/*.lua) defines each of these; the UI and the
 * coverage check read this list.
 */
data class FnEntry(
    val name: String,
    val category: String,
    val unc: Boolean,
    val sunc: Boolean,
    val aliases: List<String> = emptyList(),
) {
    val tag: String
        get() = when {
            unc && sunc -> "UNC + sUNC"
            sunc -> "sUNC"
            else -> "UNC"
        }
}

private fun e(
    name: String,
    category: String,
    unc: Boolean,
    sunc: Boolean,
    vararg aliases: String,
) = FnEntry(name, category, unc, sunc, aliases.toList())

val REGISTRY: List<FnEntry> = listOf(
    // ---------------- Cache ----------------
    e("cache.invalidate", "Cache", true, false),
    e("cache.iscached", "Cache", true, false),
    e("cache.replace", "Cache", true, false),
    e("cloneref", "Cache", true, true),
    e("compareinstances", "Cache", true, true),

    // ---------------- Closures ----------------
    e("checkcaller", "Closures", true, true),
    e("clonefunction", "Closures", true, true),
    e("getcallingscript", "Closures", true, false),
    e("getscriptclosure", "Closures", true, true, "getscriptfunction"),
    e("hookfunction", "Closures", true, true, "replaceclosure"),
    e("iscclosure", "Closures", true, true),
    e("islclosure", "Closures", true, true),
    e("isexecutorclosure", "Closures", true, true, "checkclosure", "isourclosure"),
    e("loadstring", "Closures", true, true),
    e("newcclosure", "Closures", true, true),
    e("getfunctionhash", "Closures", false, true),
    e("restorefunction", "Closures", false, true),

    // ---------------- Console ----------------
    e("rconsoleclear", "Console", true, false, "consoleclear"),
    e("rconsolecreate", "Console", true, false, "consolecreate"),
    e("rconsoledestroy", "Console", true, false, "consoledestroy"),
    e("rconsoleinput", "Console", true, false, "consoleinput"),
    e("rconsoleprint", "Console", true, false, "consoleprint"),
    e("rconsolesettitle", "Console", true, false, "rconsolename", "consolesettitle"),

    // ---------------- Crypt / Encoding ----------------
    e(
        "crypt.base64encode", "Crypt", true, false,
        "crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode",
    ),
    e(
        "crypt.base64decode", "Crypt", true, false,
        "crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode",
    ),
    e("crypt.encrypt", "Crypt", true, false),
    e("crypt.decrypt", "Crypt", true, false),
    e("crypt.generatebytes", "Crypt", true, false),
    e("crypt.generatekey", "Crypt", true, false),
    e("crypt.hash", "Crypt", true, false),
    e("base64encode", "Crypt", false, true),
    e("base64decode", "Crypt", false, true),
    e("lz4compress", "Crypt", true, true),
    e("lz4decompress", "Crypt", true, true),

    // ---------------- Debug ----------------
    e("debug.getconstant", "Debug", true, true),
    e("debug.getconstants", "Debug", true, true),
    e("debug.getinfo", "Debug", true, false),
    e("debug.getproto", "Debug", true, true),
    e("debug.getprotos", "Debug", true, true),
    e("debug.getstack", "Debug", true, true),
    e("debug.getupvalue", "Debug", true, true),
    e("debug.getupvalues", "Debug", true, true),
    e("debug.setconstant", "Debug", true, true),
    e("debug.setstack", "Debug", true, true),
    e("debug.setupvalue", "Debug", true, true),

    // ---------------- Filesystem ----------------
    e("readfile", "Filesystem", true, true),
    e("listfiles", "Filesystem", true, true),
    e("writefile", "Filesystem", true, true),
    e("makefolder", "Filesystem", true, true),
    e("appendfile", "Filesystem", true, true),
    e("isfile", "Filesystem", true, true),
    e("isfolder", "Filesystem", true, true),
    e("delfolder", "Filesystem", true, true),
    e("delfile", "Filesystem", true, true),
    e("loadfile", "Filesystem", true, true),
    e("dofile", "Filesystem", true, false),
    e("getcustomasset", "Filesystem", true, true),

    // ---------------- Input ----------------
    e("isrbxactive", "Input", true, false, "isgameactive"),
    e("mouse1click", "Input", true, false),
    e("mouse1press", "Input", true, false),
    e("mouse1release", "Input", true, false),
    e("mouse2click", "Input", true, false),
    e("mouse2press", "Input", true, false),
    e("mouse2release", "Input", true, false),
    e("mousemoveabs", "Input", true, false),
    e("mousemoverel", "Input", true, false),
    e("mousescroll", "Input", true, false),

    // ---------------- Instances ----------------
    e("fireclickdetector", "Instances", true, true),
    e("getcallbackvalue", "Instances", true, true),
    e("getconnections", "Instances", true, true),
    e("gethiddenproperty", "Instances", true, true),
    e("sethiddenproperty", "Instances", true, true),
    e("gethui", "Instances", true, true),
    e("getinstances", "Instances", true, true),
    e("getnilinstances", "Instances", true, true),
    e("isscriptable", "Instances", true, true),
    e("setscriptable", "Instances", true, true),
    e("setrbxclipboard", "Instances", true, false),
    e("fireproximityprompt", "Instances", false, true),
    e("firetouchinterest", "Instances", false, true),
    e("firesignal", "Instances", false, true),
    e("replicatesignal", "Instances", false, true),

    // ---------------- Metatable ----------------
    e("getrawmetatable", "Metatable", true, true),
    e("hookmetamethod", "Metatable", true, true),
    e("getnamecallmethod", "Metatable", true, true),
    e("setnamecallmethod", "Metatable", true, false),
    e("isreadonly", "Metatable", true, true),
    e("setrawmetatable", "Metatable", true, true),
    e("setreadonly", "Metatable", true, true),

    // ---------------- Miscellaneous ----------------
    e("identifyexecutor", "Miscellaneous", true, true, "getexecutorname"),
    e("messagebox", "Miscellaneous", true, false),
    e("queue_on_teleport", "Miscellaneous", true, false, "queueonteleport"),
    e("request", "Miscellaneous", true, true, "http.request", "http_request"),
    e("setclipboard", "Miscellaneous", true, false, "toclipboard"),
    e("setfpscap", "Miscellaneous", true, false),
    e("getfpscap", "Miscellaneous", true, false),
    e("isluau", "Miscellaneous", true, false),
    e("isnetworkowner", "Instances", true, false),
    e("decompile", "Scripts", true, false),

    // ---------------- Scripts / Environment / Reflection ----------------
    e("getgc", "Scripts", true, true),
    e("getgenv", "Scripts", true, true),
    e("getloadedmodules", "Scripts", true, true),
    e("getrenv", "Scripts", true, true),
    e("getrunningscripts", "Scripts", true, true),
    e("getscriptbytecode", "Scripts", true, true, "dumpstring"),
    e("getscripthash", "Scripts", true, true),
    e("getscripts", "Scripts", true, true),
    e("getsenv", "Scripts", true, true),
    e("getthreadidentity", "Scripts", true, true, "getidentity", "getthreadcontext"),
    e("setthreadidentity", "Scripts", true, true, "setidentity", "setthreadcontext"),
    e("getreg", "Scripts", false, true),
    e("filtergc", "Scripts", false, true),
    e("getscriptfromthread", "Scripts", false, true),

    // ---------------- Drawing ----------------
    e("Drawing", "Drawing", true, false),
    e("Drawing.new", "Drawing", true, false),
    e("Drawing.Fonts", "Drawing", true, false),
    e("isrenderobj", "Drawing", true, true),
    e("getrenderproperty", "Drawing", true, true),
    e("setrenderproperty", "Drawing", true, true),
    e("cleardrawcache", "Drawing", true, true),

    // ---------------- WebSocket ----------------
    e("WebSocket", "WebSocket", true, false),
    e("WebSocket.connect", "WebSocket", true, true),
)

val CATEGORIES: List<String> = REGISTRY.map { it.category }.distinct()

/** Names in the form "a.b.c" for the canonical entry plus all aliases. */
fun FnEntry.allNames(): List<String> = listOf(name) + aliases
