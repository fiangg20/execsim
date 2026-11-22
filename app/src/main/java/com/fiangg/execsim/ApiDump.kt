package com.fiangg.execsim

import android.app.Application
import android.content.Context
import android.util.JsonReader
import android.util.JsonToken
import org.luaj.vm2.LuaTable
import org.luaj.vm2.LuaValue
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Roblox API dump support. API-Dump.json (published by the Roblox-Client-Tracker
 * project) lists every class, property, function and event of the Roblox engine.
 * ExecSim downloads it, caches it in private storage, re-checks GitHub for a newer
 * copy (ETag based, so an unchanged file costs almost no data) and feeds a compact
 * form to the Lua environment so that Instance.new, IsA, GetService, events and
 * default properties follow the real API.
 */
object ApiDump {
    const val URL =
        "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"

    private val SKIP_PROPS = setOf("ClassName", "Parent", "Name")
    private const val PREFS = "apidump"

    sealed class Check {
        object NotModified : Check()
        class Updated(val bytes: Long) : Check()
    }

    fun file(app: Application): File = File(app.filesDir, "RobloxApiDump.json")

    fun exists(app: Application): Boolean = file(app).let { it.isFile && it.length() > 1000 }

    fun autoUpdate(app: Application): Boolean =
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("auto", true)

    fun setAutoUpdate(app: Application, value: Boolean) {
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("auto", value).apply()
    }

    /**
     * Asks GitHub whether the dump changed (If-None-Match with the stored ETag) and downloads it when it did.
     * Blocking: call from a background thread.
     */
    fun sync(app: Application, force: Boolean = false, url: String = URL): Check {
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val etag = prefs.getString("etag", null)
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 90000
        conn.requestMethod = "GET"
        conn.setRequestProperty("User-Agent", "ExecSim")
        if (!force && exists(app) && !etag.isNullOrEmpty()) {
            conn.setRequestProperty("If-None-Match", etag)
        }
        try {
            val code = conn.responseCode
            if (code == 304) return Check.NotModified
            if (code !in 200..299) throw RuntimeException("HTTP $code")
            val tmp = File(app.filesDir, "RobloxApiDump.tmp")
            conn.inputStream.use { input -> tmp.outputStream().use { out -> input.copyTo(out) } }
            if (tmp.length() < 1000) {
                val n = tmp.length()
                tmp.delete()
                throw RuntimeException("download too small ($n bytes)")
            }
            val dst = file(app)
            if (dst.exists()) dst.delete()
            if (!tmp.renameTo(dst)) throw RuntimeException("could not save the file")
            val newTag = conn.getHeaderField("ETag")
            prefs.edit().putString("etag", newTag ?: "").apply()
            return Check.Updated(dst.length())
        } finally {
            conn.disconnect()
        }
    }

    fun delete(app: Application) {
        file(app).delete()
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove("etag").apply()
    }

    class Parsed(val table: LuaTable, val classes: Int, val props: Int, val version: String)

    private class Member {
        var type = ""
        var name = ""
        var tags: Set<String> = emptySet()
        var vtCategory = ""
        var vtName = ""
        var default: String? = null
    }

    /** Streams the cached dump and converts it into the table shape roblox.lua expects. */
    fun parse(app: Application): Parsed? {
        val f = file(app)
        if (!f.isFile) return null
        val out = LuaTable()
        val counts = intArrayOf(0, 0) // classes, properties
        var version = ""
        JsonReader(f.bufferedReader()).use { r ->
            r.beginObject()
            while (r.hasNext()) {
                when (r.nextName()) {
                    "Classes" -> readClasses(r, out, counts)
                    "Version" -> version = readScalar(r) ?: ""
                    else -> r.skipValue()
                }
            }
            r.endObject()
        }
        if (counts[0] == 0) return null
        return Parsed(out, counts[0], counts[1], version)
    }

    private fun readClasses(r: JsonReader, out: LuaTable, counts: IntArray) {
        r.beginArray()
        while (r.hasNext()) readClass(r, out, counts)
        r.endArray()
    }

    private fun readClass(r: JsonReader, out: LuaTable, counts: IntArray) {
        var name = ""
        var superclass = ""
        var tags: Set<String> = emptySet()
        val members = ArrayList<Member>()
        r.beginObject()
        while (r.hasNext()) {
            when (r.nextName()) {
                "Name" -> name = readScalar(r) ?: ""
                "Superclass" -> superclass = readScalar(r) ?: ""
                "Tags" -> tags = readTags(r)
                "Members" -> {
                    r.beginArray()
                    while (r.hasNext()) members.add(readMember(r))
                    r.endArray()
                }
                else -> r.skipValue()
            }
        }
        r.endObject()
        if (name.isEmpty()) return

        val entry = LuaTable()
        entry.set("s", LuaValue.valueOf(superclass))
        entry.set("v", LuaValue.valueOf("Service" in tags))
        entry.set("c", LuaValue.valueOf("NotCreatable" !in tags && "Service" !in tags))
        val props = LuaTable()
        val funcs = LuaTable()
        val events = LuaTable()
        val defaults = LuaTable()
        var ev = 1
        for (m in members) {
            if (m.name.isEmpty() || "NotScriptable" in m.tags) continue
            when (m.type) {
                "Property" -> {
                    if (m.name in SKIP_PROPS) continue
                    props.set(m.name, LuaValue.valueOf(m.vtName))
                    counts[1]++
                    val raw = m.default
                    if (m.vtCategory == "Primitive" && raw != null) {
                        val v: LuaValue? = when (m.vtName) {
                            "bool" -> if (raw == "true" || raw == "false") LuaValue.valueOf(raw == "true") else null
                            "int", "int64", "float", "double" ->
                                raw.toDoubleOrNull()?.takeIf { !it.isNaN() && !it.isInfinite() }?.let { LuaValue.valueOf(it) }
                            "string" -> LuaValue.valueOf(raw)
                            else -> null
                        }
                        if (v != null) defaults.set(m.name, v)
                    }
                }
                "Function" -> funcs.set(m.name, LuaValue.TRUE)
                "Event" -> events.set(ev++, LuaValue.valueOf(m.name))
            }
        }
        entry.set("p", props)
        entry.set("f", funcs)
        entry.set("e", events)
        entry.set("d", defaults)
        out.set(name, entry)
        counts[0]++
    }

    private fun readMember(r: JsonReader): Member {
        val m = Member()
        r.beginObject()
        while (r.hasNext()) {
            when (r.nextName()) {
                "MemberType" -> m.type = readScalar(r) ?: ""
                "Name" -> m.name = readScalar(r) ?: ""
                "Tags" -> m.tags = readTags(r)
                "Default" -> m.default = readScalar(r)
                "ValueType" -> {
                    if (r.peek() == JsonToken.BEGIN_OBJECT) {
                        r.beginObject()
                        while (r.hasNext()) {
                            when (r.nextName()) {
                                "Category" -> m.vtCategory = readScalar(r) ?: ""
                                "Name" -> m.vtName = readScalar(r) ?: ""
                                else -> r.skipValue()
                            }
                        }
                        r.endObject()
                    } else {
                        r.skipValue()
                    }
                }
                else -> r.skipValue()
            }
        }
        r.endObject()
        return m
    }

    private fun readTags(r: JsonReader): Set<String> {
        val s = HashSet<String>()
        if (r.peek() != JsonToken.BEGIN_ARRAY) {
            r.skipValue()
            return s
        }
        r.beginArray()
        while (r.hasNext()) {
            if (r.peek() == JsonToken.STRING) s.add(r.nextString()) else r.skipValue()
        }
        r.endArray()
        return s
    }

    private fun readScalar(r: JsonReader): String? = when (r.peek()) {
        JsonToken.STRING, JsonToken.NUMBER -> r.nextString()
        JsonToken.BOOLEAN -> r.nextBoolean().toString()
        JsonToken.NULL -> {
            r.nextNull()
            null
        }
        else -> {
            r.skipValue()
            null
        }
    }
}
