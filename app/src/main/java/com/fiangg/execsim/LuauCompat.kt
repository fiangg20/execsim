package com.fiangg.execsim

/**
 * Very small Luau -> Lua 5.2 shim so that common Luau-isms keep working in the
 * LuaJ based simulator: compound assignment (+=, -=, *=, /=, %=, ^=, ..=) and
 * simple type annotations on locals / function parameters.
 *
 * Not supported: `continue`, if-then-else expressions, string interpolation.
 */
object LuauCompat {

    private val compound = Regex("""^(\s*)([A-Za-z_][\w.\[\]"':]*)\s*(\+|-|\*|/|%|\^|\.\.)=\s*(.+)$""")
    private val localType = Regex("""(\blocal\s+[A-Za-z_]\w*)\s*:\s*[A-Za-z_][\w.?]*(?:<[^>]*>|\{[^}]*\})?\??""")
    private val funcSig = Regex("""\bfunction(\s*[\w.:]*)\s*\(([^)]*)\)(?:\s*:\s*[A-Za-z_][\w.?]*(?:<[^>]*>)?)?""")

    fun convert(src: String): String {
        val sb = StringBuilder(src.length + 64)
        for (raw in src.split("\n")) {
            var line = raw.trimEnd('\r')
            line = fixCompound(line)
            if (line.contains(":")) {
                line = localType.replace(line) { it.groupValues[1] }
                line = funcSig.replace(line) { m ->
                    val params = m.groupValues[2]
                        .split(",")
                        .joinToString(", ") { p -> p.substringBefore(":").trim() }
                    "function" + m.groupValues[1] + "(" + params + ")"
                }
            }
            sb.append(line).append('\n')
        }
        return sb.toString()
    }

    private fun fixCompound(line: String): String {
        val m = compound.find(line) ?: return line
        val indent = m.groupValues[1]
        val target = m.groupValues[2]
        val op = m.groupValues[3]
        var rhs = m.groupValues[4]
        var comment = ""
        val ci = rhs.indexOf("--")
        if (ci >= 0) {
            comment = " " + rhs.substring(ci)
            rhs = rhs.substring(0, ci)
        }
        rhs = rhs.trim().trimEnd(';')
        if (rhs.isEmpty()) return line
        return "$indent$target = $target $op ($rhs)$comment"
    }
}
