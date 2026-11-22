package com.fiangg.execsim

import java.io.ByteArrayOutputStream

/** Minimal LZ4 *block* format compressor / decompressor (no frame header). */
object Lz4 {

    private fun read32(src: ByteArray, p: Int): Int =
        (src[p].toInt() and 0xFF) or
            ((src[p + 1].toInt() and 0xFF) shl 8) or
            ((src[p + 2].toInt() and 0xFF) shl 16) or
            ((src[p + 3].toInt() and 0xFF) shl 24)

    private fun writeLen(out: ByteArrayOutputStream, extra: Int) {
        var rem = extra
        while (rem >= 255) {
            out.write(255)
            rem -= 255
        }
        out.write(rem)
    }

    fun compress(src: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        val n = src.size
        val table = IntArray(1 shl 16)
        java.util.Arrays.fill(table, -1)
        var anchor = 0
        var i = 0
        val limit = n - 12
        while (i < limit) {
            val h = (read32(src, i) * -1640531535) ushr 16
            val ref = table[h]
            table[h] = i
            if (ref >= 0 && i - ref <= 65535 && read32(src, ref) == read32(src, i)) {
                var mlen = 4
                val maxLen = n - 5 - i
                while (mlen < maxLen && src[ref + mlen] == src[i + mlen]) mlen++
                val litLen = i - anchor
                val mcode = mlen - 4
                val token = (minOf(litLen, 15) shl 4) or minOf(mcode, 15)
                out.write(token)
                if (litLen >= 15) writeLen(out, litLen - 15)
                out.write(src, anchor, litLen)
                val offset = i - ref
                out.write(offset and 0xFF)
                out.write((offset ushr 8) and 0xFF)
                if (mcode >= 15) writeLen(out, mcode - 15)
                i += mlen
                anchor = i
            } else {
                i++
            }
        }
        val litLen = n - anchor
        out.write(minOf(litLen, 15) shl 4)
        if (litLen >= 15) writeLen(out, litLen - 15)
        out.write(src, anchor, litLen)
        return out.toByteArray()
    }

    fun decompress(src: ByteArray, expected: Int): ByteArray {
        var buf = ByteArray(if (expected > 0) expected else 256)
        var op = 0
        var ip = 0

        fun ensure(extra: Int) {
            if (op + extra > buf.size) {
                buf = buf.copyOf(maxOf(buf.size * 2, op + extra))
            }
        }

        while (ip < src.size) {
            val token = src[ip++].toInt() and 0xFF
            var lit = token ushr 4
            if (lit == 15) {
                while (true) {
                    val b = src[ip++].toInt() and 0xFF
                    lit += b
                    if (b != 255) break
                }
            }
            if (ip + lit > src.size) throw IllegalArgumentException("corrupt LZ4 data")
            ensure(lit)
            System.arraycopy(src, ip, buf, op, lit)
            ip += lit
            op += lit
            if (ip >= src.size) break
            val offset = (src[ip].toInt() and 0xFF) or ((src[ip + 1].toInt() and 0xFF) shl 8)
            ip += 2
            var mlen = token and 15
            if (mlen == 15) {
                while (true) {
                    val b = src[ip++].toInt() and 0xFF
                    mlen += b
                    if (b != 255) break
                }
            }
            mlen += 4
            if (offset == 0 || offset > op) throw IllegalArgumentException("corrupt LZ4 data")
            ensure(mlen)
            var from = op - offset
            for (k in 0 until mlen) {
                buf[op++] = buf[from++]
            }
        }
        return buf.copyOf(op)
    }
}
