package com.fiangg.execsim

import org.luaj.vm2.Globals
import org.luaj.vm2.LuaClosure
import org.luaj.vm2.LuaError
import org.luaj.vm2.LuaTable
import org.luaj.vm2.LuaValue
import org.luaj.vm2.Prototype
import org.luaj.vm2.Varargs
import org.luaj.vm2.lib.VarArgFunction
import java.lang.reflect.Field
import java.security.MessageDigest
import java.util.Collections
import java.util.WeakHashMap

private fun LuaTable.defFn(name: String, body: (Varargs) -> Varargs) {
    this.set(name, object : VarArgFunction() {
        override fun invoke(args: Varargs): Varargs = body(args)
    })
}

private fun field(cls: Class<*>, name: String): Field {
    val f = cls.getDeclaredField(name)
    f.isAccessible = true
    return f
}

private fun protoOf(f: LuaValue): Prototype {
    if (f !is LuaClosure) throw LuaError("invalid argument #1 (Lua function expected)")
    return field(LuaClosure::class.java, "p").get(f) as Prototype
}

private fun hex(b: ByteArray): String {
    val sb = StringBuilder(b.size * 2)
    for (x in b) {
        val v = x.toInt() and 0xFF
        sb.append("0123456789abcdef"[v ushr 4]).append("0123456789abcdef"[v and 15])
    }
    return sb.toString()
}

/**
 * Natives that need access to LuaJ internals (Prototype / LuaClosure).
 * Everything uses reflection so that a LuaJ layout change only breaks the feature,
 * not the whole build.
 */
fun registerClosureTools(host: LuaTable, g: Globals) {
    val wrapped: MutableSet<LuaValue> = Collections.synchronizedSet(
        Collections.newSetFromMap(WeakHashMap<LuaValue, Boolean>()),
    )

    host.defFn("fkind") { a ->
        LuaValue.valueOf(if (a.arg(1) is LuaClosure) "lua" else "java")
    }

    host.defFn("fsource") { a ->
        val f = a.arg(1)
        if (f is LuaClosure) {
            try {
                val p = protoOf(f)
                LuaValue.valueOf(p.source?.tojstring() ?: "")
            } catch (e: Throwable) {
                LuaValue.valueOf("")
            }
        } else {
            LuaValue.NIL
        }
    }

    host.defFn("cwrap") { a ->
        val inner = a.checkfunction(1)
        val w = object : VarArgFunction() {
            override fun invoke(args: Varargs): Varargs = inner.invoke(args)
        }
        wrapped.add(w)
        w
    }

    host.defFn("iscwrapped") { a -> LuaValue.valueOf(wrapped.contains(a.arg(1))) }

    host.defFn("fclone") { a ->
        val f = a.arg(1)
        if (f !is LuaClosure) return@defFn LuaValue.NIL
        try {
            val p = protoOf(f)
            val ctor = LuaClosure::class.java.getDeclaredConstructor(Prototype::class.java, LuaValue::class.java)
            ctor.isAccessible = true
            val copy = ctor.newInstance(p, g) as LuaClosure
            val uf = field(LuaClosure::class.java, "upValues")
            uf.set(copy, uf.get(f))
            copy
        } catch (e: Throwable) {
            LuaValue.NIL
        }
    }

    host.defFn("fpatch") { a ->
        val target = a.arg(1)
        val source = a.arg(2)
        if (target !is LuaClosure || source !is LuaClosure) return@defFn LuaValue.FALSE
        try {
            field(LuaClosure::class.java, "p").set(target, protoOf(source))
            val uf = field(LuaClosure::class.java, "upValues")
            uf.set(target, uf.get(source))
            LuaValue.TRUE
        } catch (e: Throwable) {
            LuaValue.FALSE
        }
    }

    host.defFn("consts") { a ->
        val p = protoOf(a.arg(1))
        val t = LuaTable()
        val k = p.k
        if (k != null) {
            for (i in k.indices) t.set(i + 1, k[i])
        }
        t
    }

    host.defFn("setconst") { a ->
        val p = protoOf(a.arg(1))
        val idx = a.checkint(2)
        val k = p.k
        if (k == null || idx < 1 || idx > k.size) throw LuaError("constant index out of range")
        k[idx - 1] = a.arg(3)
        LuaValue.NONE
    }

    host.defFn("protos") { a ->
        val p = protoOf(a.arg(1))
        val t = LuaTable()
        val kids = p.p
        if (kids != null) {
            val ctor = LuaClosure::class.java.getDeclaredConstructor(Prototype::class.java, LuaValue::class.java)
            ctor.isAccessible = true
            for (i in kids.indices) t.set(i + 1, ctor.newInstance(kids[i], g) as LuaClosure)
        }
        t
    }

    host.defFn("fhash") { a ->
        val p = protoOf(a.arg(1))
        val md = MessageDigest.getInstance("SHA-384")
        val code = p.code
        if (code != null) {
            for (c in code) {
                md.update((c ushr 24).toByte())
                md.update((c ushr 16).toByte())
                md.update((c ushr 8).toByte())
                md.update(c.toByte())
            }
        }
        val k = p.k
        if (k != null) {
            for (v in k) md.update(v.tojstring().toByteArray())
        }
        LuaValue.valueOf(hex(md.digest()))
    }

    host.defFn("nparams") { a ->
        val p = protoOf(a.arg(1))
        LuaValue.varargsOf(LuaValue.valueOf(p.numparams), LuaValue.valueOf(p.is_vararg != 0))
    }
}
