package com.fiangg.execsim

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.luaj.vm2.Globals
import org.luaj.vm2.LuaError
import org.luaj.vm2.LuaString
import org.luaj.vm2.LuaTable
import org.luaj.vm2.LuaValue
import org.luaj.vm2.Varargs
import org.luaj.vm2.lib.VarArgFunction
import org.luaj.vm2.lib.jse.JsePlatform
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

data class ConsoleLine(val kind: String, val text: String, val time: Long = System.currentTimeMillis())

data class DrawObj(val id: Int, val type: String, val props: Map<String, Any?>)

/** One Part of the simulated game world (from world.lua __snapshot). */
class WPart(
    val id: Int,
    val name: String,
    val cls: String,
    val pos: FloatArray,
    val size: FloatArray,
    val rot: FloatArray,
    val r: Float,
    val g: Float,
    val b: Float,
    val transparency: Float,
    val flags: Int,
    val shape: Int,
)

class WorldSnapshot(
    val cam: FloatArray = floatArrayOf(0f, 10f, 14f, 1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f, 70f),
    val parts: List<WPart> = emptyList(),
    val health: Float = 100f,
    val maxHealth: Float = 100f,
    val state: String = "Running",
    val dead: Boolean = false,
    val clock: Float = 14f,
)

data class ExplorerRow(val depth: Int, val id: Int, val cls: String, val name: String, val hasChildren: Boolean)

data class PropRow(val name: String, val type: String, val value: String, val editable: Boolean)

data class CursorState(
    val x: Float = 200f,
    val y: Float = 300f,
    val left: Boolean = false,
    val right: Boolean = false,
    val pulse: Int = 0,
)

data class TestResult(val name: String, val category: String, val status: String, val message: String)

data class TestState(
    val running: Boolean = false,
    val finished: Boolean = false,
    val total: Int = 0,
    val results: List<TestResult> = emptyList(),
)

data class RConsoleState(
    val visible: Boolean = false,
    val title: String = "Console",
    val lines: List<String> = emptyList(),
    val awaitingInput: Boolean = false,
)

data class SimSettings(
    val executorName: String = "ExecSim",
    val version: String = "1.0.0",
    val profile: String = "perfect", // perfect | weak | fake | custom
    val disabled: Set<String> = emptySet(),
    val identity: Int = 8,
)

val WEAK_DISABLED: Set<String> = setOf(
    "debug.getconstant", "debug.getconstants", "debug.getproto", "debug.getprotos",
    "debug.getstack", "debug.setstack", "debug.getupvalue", "debug.getupvalues",
    "debug.setconstant", "debug.setupvalue", "debug.getinfo",
    "hookfunction", "hookmetamethod", "restorefunction", "getfunctionhash",
    "getgc", "filtergc", "getreg", "getconnections", "firesignal", "replicatesignal",
    "getscriptfromthread", "getscriptbytecode", "getscripthash", "getscriptclosure",
    "getsenv", "getcallbackvalue", "gethiddenproperty", "sethiddenproperty",
    "isscriptable", "setscriptable", "WebSocket.connect", "WebSocket",
    "Drawing", "Drawing.new", "Drawing.Fonts", "cache.replace", "setrbxclipboard",
)

class ExecutorEngine(private val app: Application) {

    private val prefs = app.getSharedPreferences("execsim", Context.MODE_PRIVATE)

    private val _console = MutableStateFlow<List<ConsoleLine>>(emptyList())
    val console: StateFlow<List<ConsoleLine>> = _console.asStateFlow()

    private val _drawings = MutableStateFlow<List<DrawObj>>(emptyList())
    val drawings: StateFlow<List<DrawObj>> = _drawings.asStateFlow()

    private val _cursor = MutableStateFlow(CursorState())
    val cursor: StateFlow<CursorState> = _cursor.asStateFlow()

    private val _tests = MutableStateFlow(TestState())
    val tests: StateFlow<TestState> = _tests.asStateFlow()

    private val _rconsole = MutableStateFlow(RConsoleState())
    val rconsole: StateFlow<RConsoleState> = _rconsole.asStateFlow()

    private val _present = MutableStateFlow<Map<String, Boolean>>(emptyMap())
    val present: StateFlow<Map<String, Boolean>> = _present.asStateFlow()

    private val _apiStatus = MutableStateFlow(if (ApiDump.exists(app)) "Roblox API dump cached (applies on boot)" else "Roblox API dump not downloaded yet")
    val apiStatus: StateFlow<String> = _apiStatus.asStateFlow()

    private val _apiAuto = MutableStateFlow(ApiDump.autoUpdate(app))
    val apiAuto: StateFlow<Boolean> = _apiAuto.asStateFlow()

    @Volatile
    private var apiActive = ""

    // ---- simulated game world (Game tab) ---------------------------------
    private val _world = MutableStateFlow(WorldSnapshot())
    val world: StateFlow<WorldSnapshot> = _world.asStateFlow()

    private val _explorer = MutableStateFlow<List<ExplorerRow>>(emptyList())
    val explorer: StateFlow<List<ExplorerRow>> = _explorer.asStateFlow()

    private val _props = MutableStateFlow<List<PropRow>>(emptyList())
    val props: StateFlow<List<PropRow>> = _props.asStateFlow()

    @Volatile private var joyX = 0f
    @Volatile private var joyY = 0f
    @Volatile private var jumpReq = false
    @Volatile private var camYaw = 0.6f
    @Volatile private var camPitch = 0.35f
    @Volatile private var camDist = 14f
    @Volatile private var viewW = 800f
    @Volatile private var viewH = 450f
    @Volatile private var tickMs = 50L
    @Volatile private var tickErrLogged = false
    private val uiJobs = ConcurrentLinkedQueue<() -> Unit>()
    private val snapPending = AtomicBoolean(false)
    private val tickPending = AtomicBoolean(false)

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    private val _settings = MutableStateFlow(loadSettings())
    val settings: StateFlow<SimSettings> = _settings.asStateFlow()

    @Volatile
    private var generation = 0
    private var worker: ExecutorService = newWorker()
    private var globals: Globals? = null

    private val workspace: File = File(app.filesDir, "workspace").apply { mkdirs() }
    private val inputQueue = LinkedBlockingQueue<String>()
    private val drawMap = LinkedHashMap<Int, DrawBuilder>()
    private var drawDirty = false
    private var drawLast = 0L
    private var clipboardText = ""
    private val rng = SecureRandom()

    private class DrawBuilder(val type: String) {
        val props = LinkedHashMap<String, Any?>()
    }

    init {
        boot()
        startApiWatcher()
        startTicker()
    }

    // ------------------------------------------------------------------
    // lifecycle
    // ------------------------------------------------------------------

    private fun newWorker(): ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(null, r, "lua-worker", 16L * 1024 * 1024).apply { isDaemon = true }
    }

    private fun boot() {
        val gen = generation
        worker.submit {
            try {
                setup(gen)
            } catch (t: Throwable) {
                log("error", "[boot] " + (t.message ?: t.toString()))
            }
        }
    }

    /** Throw away the Lua state and build a fresh one (used after settings change). */
    fun reset(clearConsole: Boolean = false) {
        generation++
        try {
            worker.shutdownNow()
        } catch (_: Throwable) {
        }
        worker = newWorker()
        globals = null
        synchronized(drawMap) {
            drawMap.clear()
            drawDirty = false
        }
        _drawings.value = emptyList()
        _rconsole.value = RConsoleState()
        _tests.value = TestState()
        _busy.value = false
        inputQueue.clear()
        if (clearConsole) _console.value = emptyList()
        boot()
    }

    private fun setup(gen: Int) {
        val g = JsePlatform.debugGlobals()
        g.set("luajava", LuaValue.NIL)
        g.set("io", LuaValue.NIL)
        val os = g.get("os")
        if (os.istable()) {
            for (k in listOf("execute", "exit", "remove", "rename", "tmpname", "getenv", "setlocale")) {
                os.set(k, LuaValue.NIL)
            }
        }
        val host = LuaTable()
        registerHost(host, gen)
        g.set("__host", host)

        registerClosureTools(host, g)

        try {
            val parsed = ApiDump.parse(app)
            if (parsed != null) {
                host.set("api", parsed.table)
                apiActive = "Roblox API dump active: ${parsed.classes} classes, ${parsed.props} properties" +
                    (if (parsed.version.isNotEmpty()) " (v${parsed.version})" else "")
                _apiStatus.value = apiActive
            }
        } catch (t: Throwable) {
            _apiStatus.value = "Roblox API dump failed to load: " + (t.message ?: t.toString())
            log("error", "[api dump] " + (t.message ?: t.toString()))
        }

        for (name in listOf("roblox", "world", "unc_core", "unc_sys", "unc_drawing", "sunc_tests")) {
            try {
                val text = app.assets.open("lua/$name.lua").bufferedReader().use { it.readText() }
                // chunk names matter: "game_*" = simulated Roblox code, "exec_*" = executor natives
                val chunk = when (name) {
                    "roblox", "world" -> "game_env"
                    "sunc_tests" -> "executor_tests"
                    else -> "exec_$name"
                }
                g.load(text, chunk).call()
            } catch (t: Throwable) {
                log("error", "[boot] $name.lua failed: " + (t.message ?: t.toString()))
            }
        }

        val s = _settings.value
        try {
            val disabled = LuaTable()
            var i = 1
            for (n in s.disabled) {
                disabled.set(i++, LuaValue.valueOf(n))
            }
            g.get("__apply_profile").invoke(LuaValue.valueOf(s.profile), disabled)
        } catch (t: Throwable) {
            log("error", "[boot] profile: " + (t.message ?: t.toString()))
        }

        if (gen != generation) return
        globals = g
        refreshPresence(g)
        log("system", "${s.executorName} ${s.version} ready  (profile: ${s.profile}, identity ${s.identity})")
    }

    /** Checks GitHub for a newer API-Dump.json right now (the watcher also does this every 30 minutes). */
    fun checkApiNow() {
        Thread { syncApi(true) }.start()
    }

    fun setApiAuto(value: Boolean) {
        ApiDump.setAutoUpdate(app, value)
        _apiAuto.value = value
        if (value) Thread { syncApi(false) }.start()
    }

    fun removeApiDump() {
        ApiDump.delete(app)
        apiActive = ""
        _apiStatus.value = "Roblox API dump not downloaded"
        reset()
    }

    @Synchronized
    private fun syncApi(force: Boolean) {
        try {
            _apiStatus.value = "Checking Roblox API dump..."
            when (val r = ApiDump.sync(app, force)) {
                is ApiDump.Check.NotModified -> {
                    _apiStatus.value = if (apiActive.isNotEmpty()) "$apiActive - up to date" else "Roblox API dump is up to date"
                }
                is ApiDump.Check.Updated -> {
                    _apiStatus.value = "New API dump downloaded (${r.bytes / 1024} KB), applying..."
                    // never rebuild the Lua state under a running script
                    var waited = 0
                    while (_busy.value && waited < 300) {
                        Thread.sleep(1000)
                        waited++
                    }
                    Handler(Looper.getMainLooper()).post { reset() }
                }
            }
        } catch (t: Throwable) {
            _apiStatus.value = "API dump check failed: " + (t.message ?: t.toString())
        }
    }

    private fun startApiWatcher() {
        Thread {
            while (true) {
                if (_apiAuto.value) syncApi(false)
                try {
                    Thread.sleep(30L * 60L * 1000L)
                } catch (_: InterruptedException) {
                    return@Thread
                }
            }
        }.apply {
            isDaemon = true
            name = "api-watcher"
        }.start()
    }

    private fun refreshPresence(g: Globals) {
        val map = LinkedHashMap<String, Boolean>()
        try {
            val exists = g.get("__exists")
            for (entry in REGISTRY) {
                for (n in entry.allNames()) {
                    map[n] = exists.call(LuaValue.valueOf(n)).toboolean()
                }
            }
        } catch (t: Throwable) {
            log("error", "[coverage] " + (t.message ?: t.toString()))
        }
        _present.value = map
    }

    // ------------------------------------------------------------------
    // public API for the UI
    // ------------------------------------------------------------------

    fun execute(code: String) {
        worker.submit {
            val g = globals
            if (g == null) {
                log("error", "environment is not ready yet")
                return@submit
            }
            _busy.value = true
            try {
                log("system", "> executing script (${code.length} chars)")
                val chunk = g.load(LuauCompat.convert(code), "executor")
                chunk.call()
                g.get("__finish").call()
            } catch (t: Throwable) {
                log("error", t.message ?: t.toString())
            } finally {
                flushDrawings()
                _busy.value = false
            }
        }
    }

    fun runSunc() {
        worker.submit {
            val g = globals
            if (g == null) {
                log("error", "environment is not ready yet")
                return@submit
            }
            _busy.value = true
            try {
                g.get("__run_sunc").call()
            } catch (t: Throwable) {
                log("error", "[sUNC] " + (t.message ?: t.toString()))
            } finally {
                flushDrawings()
                _tests.update { it.copy(running = false, finished = true) }
                _busy.value = false
            }
        }
    }

    fun stop() {
        // Interrupts task.wait / sleeps. A tight infinite loop needs "Reset environment".
        generation++
        val old = worker
        worker = newWorker()
        try {
            old.shutdownNow()
        } catch (_: Throwable) {
        }
        _busy.value = false
        log("system", "stop requested - rebuilding environment")
        globals = null
        boot()
    }

    // ------------------------------------------------------------------
    // simulated game world
    // ------------------------------------------------------------------

    private fun drainJobs() {
        while (true) {
            val job = uiJobs.poll() ?: break
            try {
                job()
            } catch (_: Throwable) {
            }
        }
    }

    /** Runs [job] on the Lua thread: either on the idle worker or between frames of a running script. */
    private fun postLua(job: () -> Unit) {
        uiJobs.add(job)
        try {
            worker.submit { drainJobs() }
        } catch (_: Throwable) {
        }
    }

    private fun startTicker() {
        Thread {
            while (true) {
                try {
                    Thread.sleep(tickMs)
                } catch (_: InterruptedException) {
                    return@Thread
                }
                if (_busy.value || globals == null) continue
                if (!tickPending.compareAndSet(false, true)) continue
                try {
                    worker.submit {
                        try {
                            val g = globals
                            val f = g?.get("__tick")
                            if (g != null && f != null && f.isfunction() && !_busy.value) {
                                f.call()
                                maybeFlushDrawings()
                            }
                        } catch (t: Throwable) {
                            if (!tickErrLogged) {
                                tickErrLogged = true
                                log("error", "[world] " + (t.message ?: t.toString()))
                            }
                        } finally {
                            tickPending.set(false)
                        }
                    }
                } catch (_: Throwable) {
                    tickPending.set(false)
                }
            }
        }.apply {
            isDaemon = true
            name = "world-ticker"
        }.start()
    }

    fun setGameVisible(visible: Boolean) {
        tickMs = if (visible) 33L else 50L
    }

    fun setJoystick(x: Float, y: Float) {
        joyX = x
        joyY = y
    }

    fun requestJump() {
        jumpReq = true
    }

    fun setCamera(yaw: Float, pitch: Float, dist: Float) {
        camYaw = yaw
        camPitch = pitch
        camDist = dist
    }

    fun setViewSize(w: Float, h: Float) {
        viewW = w
        viewH = h
    }

    fun requestSnapshot() {
        if (!snapPending.compareAndSet(false, true)) return
        postLua {
            try {
                val g = globals
                if (g != null) {
                    val f = g.get("__snapshot")
                    if (f.isfunction()) _world.value = parseSnapshot(f.call().tojstring())
                }
            } finally {
                snapPending.set(false)
            }
        }
    }

    fun requestExplorer(expanded: Set<Int>) {
        postLua {
            val g = globals ?: return@postLua
            val f = g.get("__explorer")
            if (!f.isfunction()) return@postLua
            val text = f.call(LuaValue.valueOf(expanded.joinToString(","))).tojstring()
            val rows = ArrayList<ExplorerRow>()
            for (line in text.split('\n')) {
                if (line.isEmpty()) continue
                val p = line.split('\t')
                if (p.size < 5) continue
                rows.add(ExplorerRow(p[0].toIntOrNull() ?: 0, p[1].toIntOrNull() ?: 0, p[2], p[3], p[4] == "1"))
            }
            _explorer.value = rows
        }
    }

    fun requestProps(id: Int) {
        postLua {
            val g = globals ?: return@postLua
            val f = g.get("__props")
            if (!f.isfunction()) return@postLua
            val text = f.call(LuaValue.valueOf(id)).tojstring()
            val rows = ArrayList<PropRow>()
            for (line in text.split('\n')) {
                if (line.isEmpty()) continue
                val p = line.split('\t')
                if (p.size < 4) continue
                rows.add(PropRow(p[0], p[1], p[2], p[3] == "1"))
            }
            _props.value = rows
        }
    }

    fun setProp(id: Int, name: String, value: String) {
        postLua {
            val g = globals ?: return@postLua
            val f = g.get("__setprop")
            if (!f.isfunction()) return@postLua
            val r = f.invoke(LuaValue.valueOf(id), LuaValue.valueOf(name), LuaValue.valueOf(value))
            if (!r.arg1().toboolean()) {
                log("error", "[properties] $name: " + r.arg(2).tojstring())
            }
        }
        requestProps(id)
    }

    fun deleteInstance(id: Int) {
        postLua {
            val g = globals ?: return@postLua
            val f = g.get("__delete")
            if (f.isfunction()) f.call(LuaValue.valueOf(id))
        }
    }

    private fun parseSnapshot(text: String): WorldSnapshot {
        var cam = floatArrayOf(0f, 10f, 14f, 1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f, 70f)
        var health = 100f
        var maxHealth = 100f
        var state = "Running"
        var dead = false
        var clock = 14f
        val parts = ArrayList<WPart>()
        for (line in text.split('\n')) {
            if (line.isEmpty()) continue
            val f = line.split('\t')
            when (f[0]) {
                "C" -> if (f.size >= 14) cam = FloatArray(13) { f[it + 1].toFloatOrNull() ?: 0f }
                "S" -> if (f.size >= 5) {
                    health = f[1].toFloatOrNull() ?: 100f
                    maxHealth = f[2].toFloatOrNull() ?: 100f
                    state = f[3]
                    dead = f[4] == "1"
                }
                "L" -> if (f.size >= 2) clock = f[1].toFloatOrNull() ?: 14f
                "P" -> if (f.size >= 25) {
                    fun n(i: Int): Float = f[i].toFloatOrNull() ?: 0f
                    parts.add(
                        WPart(
                            id = f[1].toIntOrNull() ?: 0,
                            name = f[2],
                            cls = f[3],
                            pos = floatArrayOf(n(4), n(5), n(6)),
                            size = floatArrayOf(n(7), n(8), n(9)),
                            rot = FloatArray(9) { n(10 + it) },
                            r = n(19),
                            g = n(20),
                            b = n(21),
                            transparency = n(22),
                            flags = f[23].toIntOrNull() ?: 0,
                            shape = f[24].toIntOrNull() ?: 0,
                        ),
                    )
                }
            }
        }
        return WorldSnapshot(cam, parts, health, maxHealth, state, dead, clock)
    }

    fun clearConsole() {
        _console.value = emptyList()
    }

    fun submitConsoleInput(text: String) {
        inputQueue.offer(text)
    }

    fun clearDrawings() {
        synchronized(drawMap) {
            drawMap.clear()
            drawDirty = true
        }
        flushDrawings()
    }

    fun workspaceFiles(): List<String> {
        val out = ArrayList<String>()
        fun walk(dir: File, prefix: String) {
            val kids = dir.listFiles() ?: return
            for (f in kids.sortedBy { it.name }) {
                if (f.isDirectory) {
                    out.add("$prefix${f.name}/")
                    walk(f, "$prefix${f.name}/")
                } else {
                    out.add("$prefix${f.name}  (${f.length()} B)")
                }
            }
        }
        walk(workspace, "")
        return out
    }

    fun wipeWorkspace() {
        workspace.deleteRecursively()
        workspace.mkdirs()
    }

    // settings ---------------------------------------------------------

    private fun loadSettings(): SimSettings = SimSettings(
        executorName = prefs.getString("name", "ExecSim") ?: "ExecSim",
        version = prefs.getString("version", "1.0.0") ?: "1.0.0",
        profile = prefs.getString("profile", "perfect") ?: "perfect",
        disabled = prefs.getStringSet("disabled", emptySet())?.toSet() ?: emptySet(),
        identity = prefs.getInt("identity", 8),
    )

    private fun saveSettings(s: SimSettings) {
        prefs.edit()
            .putString("name", s.executorName)
            .putString("version", s.version)
            .putString("profile", s.profile)
            .putStringSet("disabled", s.disabled)
            .putInt("identity", s.identity)
            .apply()
    }

    fun updateIdentity(name: String, version: String, identity: Int) {
        val s = _settings.value.copy(
            executorName = name.ifBlank { "ExecSim" },
            version = version.ifBlank { "1.0.0" },
            identity = identity.coerceIn(0, 8),
        )
        _settings.value = s
        saveSettings(s)
        reset()
    }

    fun setProfile(profile: String) {
        val cur = _settings.value
        val disabled = when (profile) {
            "perfect", "fake" -> emptySet()
            "weak" -> WEAK_DISABLED
            else -> cur.disabled
        }
        val s = cur.copy(profile = profile, disabled = disabled)
        _settings.value = s
        saveSettings(s)
        reset()
    }

    fun toggleFunction(name: String) {
        val cur = _settings.value
        val d = cur.disabled.toMutableSet()
        if (!d.add(name)) d.remove(name)
        val s = cur.copy(profile = "custom", disabled = d)
        _settings.value = s
        saveSettings(s)
        reset()
    }

    // ------------------------------------------------------------------
    // logging / drawing helpers
    // ------------------------------------------------------------------

    private fun log(kind: String, text: String) {
        val line = ConsoleLine(kind, text)
        _console.update { (it + line).takeLast(1500) }
    }

    private fun flushDrawings() {
        val snap: List<DrawObj>
        synchronized(drawMap) {
            snap = drawMap.map { (id, b) -> DrawObj(id, b.type, LinkedHashMap(b.props)) }
            drawDirty = false
        }
        drawLast = System.currentTimeMillis()
        _drawings.value = snap
    }

    private fun maybeFlushDrawings() {
        val now = System.currentTimeMillis()
        if (now - drawLast > 40) flushDrawings()
    }

    // ------------------------------------------------------------------
    // host functions exposed to Lua as __host.*
    // ------------------------------------------------------------------

    private fun LuaTable.def(name: String, body: (Varargs) -> Varargs) {
        this.set(name, object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs = body(args)
        })
    }

    private fun bytesOf(v: LuaValue): ByteArray {
        val s = v.checkstring()
        val n = s.length()
        val out = ByteArray(n)
        for (i in 0 until n) out[i] = s.luaByte(i).toByte()
        return out
    }

    private fun lstr(b: ByteArray): LuaValue = LuaString.valueOf(b)

    private fun resolvePath(path: String): File {
        val parts = path.replace("\\", "/").split("/").filter { it.isNotEmpty() && it != "." }
        if (parts.any { it == ".." }) throw LuaError("path escapes the workspace folder")
        return if (parts.isEmpty()) workspace else File(workspace, parts.joinToString("/"))
    }

    private fun hex(b: ByteArray): String {
        val sb = StringBuilder(b.size * 2)
        for (x in b) {
            val v = x.toInt() and 0xFF
            sb.append("0123456789abcdef"[v ushr 4]).append("0123456789abcdef"[v and 15])
        }
        return sb.toString()
    }

    private fun normaliseKey(raw: ByteArray): ByteArray {
        if (raw.size == 16 || raw.size == 24 || raw.size == 32) return raw
        return MessageDigest.getInstance("SHA-256").digest(raw)
    }

    private fun cipherFor(mode: String, encrypt: Boolean, key: ByteArray, iv: ByteArray?): Cipher {
        val m = mode.uppercase().trim().ifEmpty { "CBC" }
        val transformation = when (m) {
            "CBC" -> "AES/CBC/PKCS5Padding"
            "ECB" -> "AES/ECB/PKCS5Padding"
            "CTR" -> "AES/CTR/NoPadding"
            "CFB" -> "AES/CFB/NoPadding"
            "GCM" -> "AES/GCM/NoPadding"
            else -> throw LuaError("unsupported cipher mode: $mode")
        }
        val c = Cipher.getInstance(transformation)
        val spec = SecretKeySpec(normaliseKey(key), "AES")
        val opmode = if (encrypt) Cipher.ENCRYPT_MODE else Cipher.DECRYPT_MODE
        when (m) {
            "ECB" -> c.init(opmode, spec)
            "GCM" -> c.init(opmode, spec, GCMParameterSpec(128, iv))
            else -> c.init(opmode, spec, IvParameterSpec(iv))
        }
        return c
    }

    private fun registerHost(host: LuaTable, gen: Int) {
        // ---- logging --------------------------------------------------
        host.def("log") { a ->
            if (gen == generation) log(a.optjstring(1, "print"), a.optjstring(2, ""))
            LuaValue.NONE
        }
        host.def("now") { _ -> LuaValue.valueOf(System.nanoTime() / 1.0e9) }
        host.def("epoch") { _ -> LuaValue.valueOf(System.currentTimeMillis() / 1000.0) }
        host.def("sleep") { a ->
            var remaining = (a.optdouble(1, 0.0) * 1000.0).toLong()
            while (remaining > 0) {
                val slice = if (remaining > 40) 40L else remaining
                try {
                    Thread.sleep(slice)
                } catch (e: InterruptedException) {
                    throw LuaError("script stopped")
                }
                remaining -= slice
            }
            drainJobs()
            if (Thread.currentThread().isInterrupted) throw LuaError("script stopped")
            LuaValue.NONE
        }
        host.def("luau") { a -> LuaValue.valueOf(LuauCompat.convert(a.checkjstring(1))) }

        // ---- executor identity ---------------------------------------
        host.def("exec_info") { _ ->
            val s = _settings.value
            LuaValue.varargsOf(
                arrayOf<LuaValue>(
                    LuaValue.valueOf(s.executorName),
                    LuaValue.valueOf(s.version),
                    LuaValue.valueOf(s.identity),
                ),
            )
        }

        // ---- filesystem (sandboxed to <app files>/workspace) -----------
        host.def("fs_read") { a ->
            val f = resolvePath(a.checkjstring(1))
            if (!f.isFile) throw LuaError("${a.checkjstring(1)} does not exist")
            lstr(f.readBytes())
        }
        host.def("fs_write") { a ->
            val f = resolvePath(a.checkjstring(1))
            f.parentFile?.mkdirs()
            f.writeBytes(bytesOf(a.arg(2)))
            LuaValue.NONE
        }
        host.def("fs_append") { a ->
            val f = resolvePath(a.checkjstring(1))
            f.parentFile?.mkdirs()
            f.appendBytes(bytesOf(a.arg(2)))
            LuaValue.NONE
        }
        host.def("fs_list") { a ->
            val raw = a.optjstring(1, "")
            val dir = resolvePath(raw)
            if (!dir.isDirectory) throw LuaError("$raw is not a folder")
            val prefix = raw.replace("\\", "/").trim('/').let { if (it.isEmpty() || it == ".") "" else "$it/" }
            val t = LuaTable()
            var i = 1
            for (f in (dir.listFiles() ?: emptyArray()).sortedBy { it.name }) {
                t.set(i++, LuaValue.valueOf(prefix + f.name))
            }
            t
        }
        host.def("fs_isfile") { a -> LuaValue.valueOf(resolvePath(a.checkjstring(1)).isFile) }
        host.def("fs_isfolder") { a -> LuaValue.valueOf(resolvePath(a.checkjstring(1)).isDirectory) }
        host.def("fs_mkdir") { a ->
            resolvePath(a.checkjstring(1)).mkdirs()
            LuaValue.NONE
        }
        host.def("fs_delfile") { a ->
            val f = resolvePath(a.checkjstring(1))
            if (!f.isFile) throw LuaError("${a.checkjstring(1)} does not exist")
            f.delete()
            LuaValue.NONE
        }
        host.def("fs_delfolder") { a ->
            val f = resolvePath(a.checkjstring(1))
            if (!f.isDirectory) throw LuaError("${a.checkjstring(1)} does not exist")
            if (f == workspace) throw LuaError("cannot delete the workspace root")
            f.deleteRecursively()
            LuaValue.NONE
        }
        host.def("fs_url") { a ->
            // getcustomasset: a stable fake asset id for a workspace file
            val f = resolvePath(a.checkjstring(1))
            if (!f.isFile) throw LuaError("${a.checkjstring(1)} does not exist")
            LuaValue.valueOf("rbxasset://" + f.name)
        }

        // ---- crypt ---------------------------------------------------
        host.def("b64enc") { a -> LuaValue.valueOf(Base64.getEncoder().encodeToString(bytesOf(a.arg(1)))) }
        host.def("b64dec") { a ->
            try {
                lstr(Base64.getDecoder().decode(a.checkjstring(1).trim()))
            } catch (e: IllegalArgumentException) {
                throw LuaError("invalid base64 input")
            }
        }
        host.def("hash") { a ->
            val alg = a.checkjstring(1).lowercase().replace("_", "").replace("-", "")
            val name = when (alg) {
                "md5" -> "MD5"
                "sha1" -> "SHA-1"
                "sha224" -> "SHA-224"
                "sha256" -> "SHA-256"
                "sha384" -> "SHA-384"
                "sha512" -> "SHA-512"
                "sha3224" -> "SHA3-224"
                "sha3256" -> "SHA3-256"
                "sha3384" -> "SHA3-384"
                "sha3512" -> "SHA3-512"
                else -> throw LuaError("unsupported hash algorithm: ${a.checkjstring(1)}")
            }
            try {
                LuaValue.valueOf(hex(MessageDigest.getInstance(name).digest(bytesOf(a.arg(2)))))
            } catch (e: java.security.NoSuchAlgorithmException) {
                throw LuaError("hash algorithm not available on this device: $name")
            }
        }
        host.def("randbytes") { a ->
            val n = a.optint(1, 16).coerceIn(0, 1 shl 20)
            val b = ByteArray(n)
            rng.nextBytes(b)
            lstr(b)
        }
        host.def("aes_encrypt") { a ->
            try {
                val data = bytesOf(a.arg(1))
                val key = Base64.getDecoder().decode(a.checkjstring(2))
                val mode = a.optjstring(4, "CBC")
                var iv: ByteArray? = null
                if (!a.isnil(3) && a.checkjstring(3).isNotEmpty()) {
                    iv = Base64.getDecoder().decode(a.checkjstring(3))
                } else if (mode.uppercase() != "ECB") {
                    iv = ByteArray(if (mode.uppercase() == "GCM") 12 else 16)
                    rng.nextBytes(iv)
                }
                val c = cipherFor(mode, true, key, iv)
                val enc = c.doFinal(data)
                LuaValue.varargsOf(
                    LuaValue.valueOf(Base64.getEncoder().encodeToString(enc)),
                    LuaValue.valueOf(if (iv == null) "" else Base64.getEncoder().encodeToString(iv)),
                )
            } catch (e: LuaError) {
                throw e
            } catch (e: Exception) {
                throw LuaError("encrypt failed: " + (e.message ?: e.toString()))
            }
        }
        host.def("aes_decrypt") { a ->
            try {
                val data = Base64.getDecoder().decode(a.checkjstring(1))
                val key = Base64.getDecoder().decode(a.checkjstring(2))
                val mode = a.optjstring(4, "CBC")
                var iv: ByteArray? = null
                if (!a.isnil(3) && a.checkjstring(3).isNotEmpty()) {
                    iv = Base64.getDecoder().decode(a.checkjstring(3))
                }
                if (iv == null && mode.uppercase() != "ECB") throw LuaError("an IV is required for $mode")
                val c = cipherFor(mode, false, key, iv)
                lstr(c.doFinal(data))
            } catch (e: LuaError) {
                throw e
            } catch (e: Exception) {
                throw LuaError("decrypt failed: " + (e.message ?: e.toString()))
            }
        }
        host.def("lz4c") { a -> lstr(Lz4.compress(bytesOf(a.arg(1)))) }
        host.def("lz4d") { a ->
            try {
                lstr(Lz4.decompress(bytesOf(a.arg(1)), a.optint(2, 0)))
            } catch (e: Exception) {
                throw LuaError("lz4decompress failed: " + (e.message ?: e.toString()))
            }
        }

        // ---- clipboard -----------------------------------------------
        host.def("clip_set") { a ->
            clipboardText = a.checkjstring(1)
            val text = clipboardText
            Handler(Looper.getMainLooper()).post {
                try {
                    val cm = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("ExecSim", text))
                } catch (_: Throwable) {
                }
            }
            LuaValue.NONE
        }
        host.def("clip_get") { _ -> LuaValue.valueOf(clipboardText) }

        // ---- http ----------------------------------------------------
        host.def("http") { a ->
            val method = a.optjstring(1, "GET").uppercase()
            val url = a.checkjstring(2)
            val headers = a.arg(3)
            val body: ByteArray? = if (a.isnil(4)) null else bytesOf(a.arg(4))
            try {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.requestMethod = method
                conn.connectTimeout = 15000
                conn.readTimeout = 25000
                conn.instanceFollowRedirects = true
                conn.setRequestProperty("User-Agent", "Roblox/WinInet")
                if (headers.istable()) {
                    var k: LuaValue = LuaValue.NIL
                    while (true) {
                        val n = headers.next(k)
                        k = n.arg1()
                        if (k.isnil()) break
                        conn.setRequestProperty(k.tojstring(), n.arg(2).tojstring())
                    }
                }
                if (body != null && method != "GET" && method != "HEAD") {
                    conn.doOutput = true
                    conn.outputStream.use { it.write(body) }
                }
                val code = conn.responseCode
                val stream = if (code >= 400) conn.errorStream else conn.inputStream
                val data = stream?.use { it.readBytes() } ?: ByteArray(0)
                val ht = LuaTable()
                for ((hk, hv) in conn.headerFields) {
                    if (hk != null && hv.isNotEmpty()) ht.set(hk, LuaValue.valueOf(hv.joinToString(", ")))
                }
                LuaValue.varargsOf(
                    arrayOf<LuaValue>(
                        LuaValue.valueOf(code),
                        LuaValue.valueOf(conn.responseMessage ?: ""),
                        lstr(data),
                        ht,
                    ),
                )
            } catch (e: LuaError) {
                throw e
            } catch (e: Exception) {
                throw LuaError("HttpError: " + (e.message ?: e.toString()))
            }
        }

        // ---- misc ----------------------------------------------------
        host.def("messagebox") { a ->
            val text = a.optjstring(1, "")
            val caption = a.optjstring(2, "")
            val flags = a.optint(3, 0)
            log("info", "[messagebox] $caption: $text")
            val kind = flags and 0xF
            LuaValue.valueOf(if (kind == 3 || kind == 4) 6 else 1)
        }
        host.def("rcon") { a ->
            val op = a.checkjstring(1)
            when (op) {
                "create" -> _rconsole.update { it.copy(visible = true) }
                "destroy" -> _rconsole.value = RConsoleState()
                "clear" -> _rconsole.update { it.copy(lines = emptyList()) }
                "title" -> _rconsole.update { it.copy(title = a.optjstring(2, "Console")) }
                "print" -> {
                    val txt = a.optjstring(2, "")
                    _rconsole.update { st -> st.copy(visible = true, lines = (st.lines + txt).takeLast(500)) }
                }
                "input" -> {
                    _rconsole.update { it.copy(visible = true, awaitingInput = true) }
                    val line = try {
                        inputQueue.poll(120, TimeUnit.SECONDS) ?: ""
                    } catch (e: InterruptedException) {
                        throw LuaError("script stopped")
                    }
                    _rconsole.update { st -> st.copy(awaitingInput = false, lines = (st.lines + "> $line").takeLast(500)) }
                    return@def LuaValue.valueOf(line)
                }
            }
            LuaValue.NONE
        }
        host.def("fps") { a ->
            log("info", "[setfpscap] ${a.optint(1, 0)}")
            LuaValue.NONE
        }

        // ---- input simulation -------------------------------------------
        host.def("input") { a ->
            val kind = a.checkjstring(1)
            _cursor.update { c ->
                when (kind) {
                    "move_abs" -> c.copy(x = a.optdouble(2, 0.0).toFloat(), y = a.optdouble(3, 0.0).toFloat())
                    "move_rel" -> c.copy(x = c.x + a.optdouble(2, 0.0).toFloat(), y = c.y + a.optdouble(3, 0.0).toFloat())
                    "press" -> if (a.optint(2, 1) == 1) c.copy(left = true, pulse = c.pulse + 1) else c.copy(right = true, pulse = c.pulse + 1)
                    "release" -> if (a.optint(2, 1) == 1) c.copy(left = false) else c.copy(right = false)
                    "click" -> c.copy(pulse = c.pulse + 1)
                    else -> c
                }
            }
            LuaValue.NONE
        }
        host.def("cursor") { _ ->
            val c = _cursor.value
            LuaValue.varargsOf(LuaValue.valueOf(c.x.toDouble()), LuaValue.valueOf(c.y.toDouble()))
        }

        host.def("moveinput") { _ ->
            val jump = jumpReq
            jumpReq = false
            LuaValue.varargsOf(
                LuaValue.valueOf(joyX.toDouble()),
                LuaValue.valueOf(joyY.toDouble()),
                LuaValue.valueOf(jump),
            )
        }
        host.def("camera") { _ ->
            LuaValue.varargsOf(
                LuaValue.valueOf(camYaw.toDouble()),
                LuaValue.valueOf(camPitch.toDouble()),
                LuaValue.valueOf(camDist.toDouble()),
            )
        }
        host.def("vsize") { _ ->
            LuaValue.varargsOf(LuaValue.valueOf(viewW.toDouble()), LuaValue.valueOf(viewH.toDouble()))
        }

        // ---- drawing ---------------------------------------------------
        host.def("draw_new") { a ->
            synchronized(drawMap) {
                drawMap[a.checkint(1)] = DrawBuilder(a.checkjstring(2))
                drawDirty = true
            }
            maybeFlushDrawings()
            LuaValue.NONE
        }
        host.def("draw_set") { a ->
            val id = a.checkint(1)
            val prop = a.checkjstring(2)
            val value: Any? = when {
                a.narg() >= 5 -> listOf(a.arg(3).checkdouble(), a.arg(4).checkdouble(), a.arg(5).checkdouble())
                a.narg() == 4 -> listOf(a.arg(3).checkdouble(), a.arg(4).checkdouble())
                a.arg(3).isboolean() -> a.arg(3).toboolean()
                a.arg(3).isnumber() -> a.arg(3).todouble()
                a.arg(3).isstring() -> a.arg(3).tojstring()
                else -> null
            }
            synchronized(drawMap) {
                drawMap[id]?.props?.put(prop, value)
                drawDirty = true
            }
            maybeFlushDrawings()
            LuaValue.NONE
        }
        host.def("draw_del") { a ->
            synchronized(drawMap) {
                drawMap.remove(a.checkint(1))
                drawDirty = true
            }
            maybeFlushDrawings()
            LuaValue.NONE
        }
        host.def("draw_clear") { _ ->
            synchronized(drawMap) {
                drawMap.clear()
                drawDirty = true
            }
            flushDrawings()
            LuaValue.NONE
        }
        host.def("draw_flush") { _ ->
            flushDrawings()
            LuaValue.NONE
        }

        // ---- sUNC test reporting ------------------------------------------
        host.def("test_begin") { a ->
            _tests.value = TestState(running = true, finished = false, total = a.optint(1, 0))
            LuaValue.NONE
        }
        host.def("test_result") { a ->
            val r = TestResult(
                a.checkjstring(1),
                a.optjstring(2, ""),
                a.checkjstring(3),
                a.optjstring(4, ""),
            )
            _tests.update { it.copy(results = it.results + r) }
            LuaValue.NONE
        }
        host.def("test_end") { _ ->
            _tests.update { it.copy(running = false, finished = true) }
            LuaValue.NONE
        }
    }
}
