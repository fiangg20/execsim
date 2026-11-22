package com.fiangg.execsim

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt
import kotlin.math.tan

// ---------------------------------------------------------------------
// helpers shared with the Drawing API overlay
// ---------------------------------------------------------------------

internal fun vecOf(p: Map<String, Any?>, key: String): Offset {
    val l = p[key] as? List<*> ?: return Offset.Zero
    val x = (l.getOrNull(0) as? Double) ?: 0.0
    val y = (l.getOrNull(1) as? Double) ?: 0.0
    return Offset(x.toFloat(), y.toFloat())
}

internal fun numOf(p: Map<String, Any?>, key: String, def: Float): Float =
    ((p[key] as? Double) ?: def.toDouble()).toFloat()

internal fun colorOf(p: Map<String, Any?>, key: String = "Color"): Color {
    val l = p[key] as? List<*>
    val r = ((l?.getOrNull(0) as? Double) ?: 0.0).toFloat().coerceIn(0f, 1f)
    val g = ((l?.getOrNull(1) as? Double) ?: 0.0).toFloat().coerceIn(0f, 1f)
    val b = ((l?.getOrNull(2) as? Double) ?: 0.0).toFloat().coerceIn(0f, 1f)
    val a = numOf(p, "Transparency", 1f).coerceIn(0f, 1f)
    return Color(r, g, b, a)
}

private fun DrawScope.drawExecutorOverlay(objs: List<DrawObj>, cursor: CursorState, s: Float) {
    for (o in objs.sortedBy { (it.props["ZIndex"] as? Double) ?: 0.0 }) {
        if (o.props["Visible"] != true) continue
        val p = o.props
        val col = colorOf(p)
        val thick = numOf(p, "Thickness", 1f) * s
        val filled = p["Filled"] == true
        val style = if (filled) Fill else Stroke(width = thick)
        when (o.type) {
            "Line" -> drawLine(col, vecOf(p, "From") * s, vecOf(p, "To") * s, strokeWidth = thick)
            "Square" -> drawRect(col, vecOf(p, "Position") * s, Size(vecOf(p, "Size").x * s, vecOf(p, "Size").y * s), style = style)
            "Circle" -> drawCircle(col, numOf(p, "Radius", 0f) * s, vecOf(p, "Position") * s, style = style)
            "Triangle", "Quad" -> {
                val path = Path()
                val keys = if (o.type == "Triangle") listOf("PointA", "PointB", "PointC") else listOf("PointA", "PointB", "PointC", "PointD")
                keys.forEachIndexed { i, k ->
                    val pt = vecOf(p, k) * s
                    if (i == 0) path.moveTo(pt.x, pt.y) else path.lineTo(pt.x, pt.y)
                }
                path.close()
                drawPath(path, col, style = style)
            }
            "Text" -> {
                val paint = Paint().apply {
                    isAntiAlias = true
                    color = col.toArgb()
                    textSize = numOf(p, "Size", 14f) * s
                    textAlign = if (p["Center"] == true) Paint.Align.CENTER else Paint.Align.LEFT
                }
                val pos = vecOf(p, "Position") * s
                drawContext.canvas.nativeCanvas.drawText((p["Text"] as? String) ?: "", pos.x, pos.y + paint.textSize, paint)
            }
            "Image" -> {
                val pos = vecOf(p, "Position") * s
                drawRect(Color(0xFF3A4455), pos, Size(vecOf(p, "Size").x * s, vecOf(p, "Size").y * s), style = Stroke(width = 2f))
            }
        }
    }
    val c = Offset(cursor.x * s, cursor.y * s)
    drawCircle(Color.White.copy(alpha = 0.9f), 6f * s, c)
    drawCircle(if (cursor.left || cursor.right) Accent else Color.White.copy(alpha = 0.4f), 12f * s, c, style = Stroke(width = 2f * s))
}

// ---------------------------------------------------------------------
// 3D rendering of the simulated Workspace
// ---------------------------------------------------------------------

private class HitFace(val id: Int, val pts: FloatArray)

private fun pointInPoly(x: Float, y: Float, p: FloatArray): Boolean {
    var inside = false
    val n = p.size / 2
    var j = n - 1
    for (i in 0 until n) {
        val xi = p[i * 2]
        val yi = p[i * 2 + 1]
        val xj = p[j * 2]
        val yj = p[j * 2 + 1]
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside
        j = i
    }
    return inside
}

private const val NEAR = 0.4f

private fun daylight(clock: Float): Float {
    val t = ((clock - 6f) / 12f).coerceIn(0f, 1f)
    return kotlin.math.sin(t * Math.PI.toFloat()).coerceIn(0f, 1f)
}

private fun DrawScope.drawWorld(world: WorldSnapshot, selected: Int, hits: MutableList<HitFace>) {
    val w = size.width
    val h = size.height
    val day = daylight(world.clock)
    val skyTop = lerp(Color(0xFF080D22), Color(0xFF4F9BFF), day)
    val skyBottom = lerp(Color(0xFF141B33), Color(0xFFBFE4FF), day)
    drawRect(Brush.verticalGradient(listOf(skyTop, skyBottom)), size = size)
    hits.clear()

    val cam = world.cam
    val cpx = cam[0]
    val cpy = cam[1]
    val cpz = cam[2]
    val rightX = cam[3]; val rightY = cam[6]; val rightZ = cam[9]
    val upX = cam[4]; val upY = cam[7]; val upZ = cam[10]
    val backX = cam[5]; val backY = cam[8]; val backZ = cam[11]
    val fy = (h / 2f) / tan(Math.toRadians((cam[12] / 2f).toDouble())).toFloat()
    val lx = 0.35f; val ly = 0.85f; val lz = 0.40f
    val lm = sqrt(lx * lx + ly * ly + lz * lz)

    // order: huge flat parts first (ground), everything else far to near
    val keyed = world.parts.map { p ->
        val dx = p.pos[0] - cpx
        val dy = p.pos[1] - cpy
        val dz = p.pos[2] - cpz
        val dist = sqrt(dx * dx + dy * dy + dz * dz)
        val big = max(p.size[0], max(p.size[1], p.size[2])) >= 100f
        Triple(p, dist, big)
    }
    val ordered = keyed.filter { it.third }.sortedBy { it.first.pos[1] } +
        keyed.filter { !it.third }.sortedByDescending { it.second }

    val axes = Array(3) { FloatArray(3) }
    val cs = FloatArray(3)

    for ((p, dist, _) in ordered) {
        val alpha = (1f - p.transparency).coerceIn(0f, 1f)
        if (alpha <= 0.01f) continue
        val fog = (dist / 450f).coerceIn(0f, 0.75f)
        val rot = p.rot
        axes[0][0] = rot[0]; axes[0][1] = rot[3]; axes[0][2] = rot[6]
        axes[1][0] = rot[1]; axes[1][1] = rot[4]; axes[1][2] = rot[7]
        axes[2][0] = rot[2]; axes[2][1] = rot[5]; axes[2][2] = rot[8]
        val hs = floatArrayOf(p.size[0] / 2f, p.size[1] / 2f, p.size[2] / 2f)
        val base = Color(p.r, p.g, p.b)

        if (p.shape == 1) {
            // ball: a shaded disc
            val rx = p.pos[0] - cpx
            val ry = p.pos[1] - cpy
            val rz = p.pos[2] - cpz
            val x = rx * rightX + ry * rightY + rz * rightZ
            val y = rx * upX + ry * upY + rz * upZ
            val d = -(rx * backX + ry * backY + rz * backZ)
            if (d > NEAR) {
                val sx = w / 2f + fy * x / d
                val sy = h / 2f - fy * y / d
                val rad = fy * (max(p.size[0], max(p.size[1], p.size[2])) / 2f) / d
                val col = lerp(Color(base.red * 0.9f, base.green * 0.9f, base.blue * 0.9f, alpha), skyBottom, fog)
                drawCircle(col, rad, Offset(sx, sy))
                if (p.id == selected) drawCircle(Accent, rad, Offset(sx, sy), style = Stroke(width = 3f))
            }
            continue
        }

        for (a in 0..2) {
            val b = (a + 1) % 3
            val c = (a + 2) % 3
            for (sgn in intArrayOf(-1, 1)) {
                val s = sgn.toFloat()
                val nx = axes[a][0] * s
                val ny = axes[a][1] * s
                val nz = axes[a][2] * s
                val fcx = p.pos[0] + nx * hs[a]
                val fcy = p.pos[1] + ny * hs[a]
                val fcz = p.pos[2] + nz * hs[a]
                // back-face culling
                if (nx * (cpx - fcx) + ny * (cpy - fcy) + nz * (cpz - fcz) <= 0f) continue
                // 4 corners in camera space
                val poly = ArrayList<FloatArray>(5)
                val us = floatArrayOf(-1f, 1f, 1f, -1f)
                val vs = floatArrayOf(-1f, -1f, 1f, 1f)
                for (i in 0..3) {
                    val wx = fcx + us[i] * hs[b] * axes[b][0] + vs[i] * hs[c] * axes[c][0]
                    val wy = fcy + us[i] * hs[b] * axes[b][1] + vs[i] * hs[c] * axes[c][1]
                    val wz = fcz + us[i] * hs[b] * axes[b][2] + vs[i] * hs[c] * axes[c][2]
                    val rx = wx - cpx
                    val ry = wy - cpy
                    val rz = wz - cpz
                    poly.add(
                        floatArrayOf(
                            rx * rightX + ry * rightY + rz * rightZ,
                            rx * upX + ry * upY + rz * upZ,
                            -(rx * backX + ry * backY + rz * backZ),
                        ),
                    )
                }
                // clip against the near plane
                val clipped = ArrayList<FloatArray>(6)
                for (i in poly.indices) {
                    val cur = poly[i]
                    val nxt = poly[(i + 1) % poly.size]
                    val curIn = cur[2] >= NEAR
                    val nxtIn = nxt[2] >= NEAR
                    if (curIn) clipped.add(cur)
                    if (curIn != nxtIn) {
                        val t = (NEAR - cur[2]) / (nxt[2] - cur[2])
                        clipped.add(
                            floatArrayOf(
                                cur[0] + (nxt[0] - cur[0]) * t,
                                cur[1] + (nxt[1] - cur[1]) * t,
                                NEAR,
                            ),
                        )
                    }
                }
                if (clipped.size < 3) continue
                val path = Path()
                val pts = FloatArray(clipped.size * 2)
                for (i in clipped.indices) {
                    val q = clipped[i]
                    cs[0] = w / 2f + fy * q[0] / q[2]
                    cs[1] = h / 2f - fy * q[1] / q[2]
                    pts[i * 2] = cs[0]
                    pts[i * 2 + 1] = cs[1]
                    if (i == 0) path.moveTo(cs[0], cs[1]) else path.lineTo(cs[0], cs[1])
                }
                path.close()
                val shade = 0.45f + 0.55f * max(0f, (nx * lx + ny * ly + nz * lz) / lm)
                val lit = Color(
                    (base.red * shade).coerceIn(0f, 1f),
                    (base.green * shade).coerceIn(0f, 1f),
                    (base.blue * shade).coerceIn(0f, 1f),
                    alpha,
                )
                val dayShade = 0.35f + 0.65f * day
                val col = lerp(
                    Color(lit.red * dayShade, lit.green * dayShade, lit.blue * dayShade, alpha),
                    skyBottom,
                    fog,
                )
                drawPath(path, col, style = Fill)
                drawPath(path, Color.Black.copy(alpha = 0.18f * alpha), style = Stroke(width = 1f))
                if (p.id == selected) drawPath(path, Accent, style = Stroke(width = 3f))
                hits.add(HitFace(p.id, pts))
            }
        }
    }
}

// ---------------------------------------------------------------------
// Game tab
// ---------------------------------------------------------------------

@Composable
internal fun GameScreen(engine: ExecutorEngine) {
    var mode by rememberSaveable { mutableIntStateOf(0) }
    var selected by rememberSaveable { mutableIntStateOf(-1) }
    val world by engine.world.collectAsState()

    LaunchedEffect(Unit) {
        engine.setGameVisible(true)
        try {
            while (true) {
                engine.requestSnapshot()
                delay(66)
            }
        } finally {
            engine.setGameVisible(false)
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Game", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            FilterChip(selected = mode == 0, onClick = { mode = 0 }, label = { Text("View") })
            FilterChip(selected = mode == 1, onClick = { mode = 1 }, label = { Text("Explorer") })
        }
        if (mode == 0) {
            ViewportPane(engine, world, selected, onSelect = { selected = it }, onOpen = { mode = 1 })
        } else {
            ExplorerPane(engine, selected, onSelect = { selected = it })
        }
    }
}

@Composable
private fun ViewportPane(
    engine: ExecutorEngine,
    world: WorldSnapshot,
    selected: Int,
    onSelect: (Int) -> Unit,
    onOpen: () -> Unit,
) {
    val objs by engine.drawings.collectAsState()
    val cursor by engine.cursor.collectAsState()
    var yaw by rememberSaveable { mutableFloatStateOf(0.6f) }
    var pitch by rememberSaveable { mutableFloatStateOf(0.35f) }
    var dist by rememberSaveable { mutableFloatStateOf(14f) }
    val hits = remember { ArrayList<HitFace>() }
    val density = LocalDensity.current.density

    LaunchedEffect(yaw, pitch, dist) { engine.setCamera(yaw, pitch, dist) }

    val selName = world.parts.firstOrNull { it.id == selected }

    Box(
        Modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(14.dp))
            .background(Color(0xFF05070B)),
    ) {
        Canvas(
            Modifier
                .fillMaxSize()
                .onSizeChanged { engine.setViewSize(it.width / density, it.height / density) }
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        yaw -= pan.x * 0.008f
                        pitch = (pitch + pan.y * 0.006f).coerceIn(-0.25f, 1.35f)
                        dist = (dist / zoom).coerceIn(4f, 70f)
                    }
                }
                .pointerInput(Unit) {
                    detectTapGestures { o ->
                        var found = -1
                        for (i in hits.indices.reversed()) {
                            if (pointInPoly(o.x, o.y, hits[i].pts)) {
                                found = hits[i].id
                                break
                            }
                        }
                        onSelect(found)
                    }
                },
        ) {
            drawWorld(world, selected, hits)
            drawExecutorOverlay(objs, cursor, density)
        }

        // HUD
        Column(Modifier.padding(10.dp)) {
            Text(
                "${world.state}  -  ${world.parts.size} parts",
                color = Color.White.copy(alpha = 0.8f),
                fontSize = 11.sp,
            )
            Spacer(Modifier.height(4.dp))
            val frac = if (world.maxHealth > 0f) (world.health / world.maxHealth).coerceIn(0f, 1f) else 0f
            Box(
                Modifier
                    .width(120.dp)
                    .height(10.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(Color.Black.copy(alpha = 0.5f)),
            ) {
                Box(
                    Modifier
                        .fillMaxHeight()
                        .width((120f * frac).dp)
                        .background(if (frac > 0.5f) Accent else if (frac > 0.25f) Warn else Bad),
                )
            }
            if (world.dead) {
                Text("You died - respawning...", color = Bad, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }

        if (selName != null) {
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xCC151A23)),
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 10.dp)) {
                    Text(selName.name + " (" + selName.cls + ")", fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                    TextButton(onClick = onOpen) { Text("Edit") }
                }
            }
        }

        Joystick(
            onChange = { x, y -> engine.setJoystick(x, y) },
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(18.dp),
        )
        Box(
            Modifier
                .align(Alignment.BottomEnd)
                .padding(24.dp)
                .size(68.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.14f))
                .clickable { engine.requestJump() },
            contentAlignment = Alignment.Center,
        ) {
            Text("JUMP", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun Joystick(onChange: (Float, Float) -> Unit, modifier: Modifier = Modifier) {
    var knob by remember { mutableStateOf(Offset.Zero) }
    val radius = with(LocalDensity.current) { 44.dp.toPx() }
    Box(
        modifier
            .size(112.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.10f))
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragEnd = {
                        knob = Offset.Zero
                        onChange(0f, 0f)
                    },
                    onDragCancel = {
                        knob = Offset.Zero
                        onChange(0f, 0f)
                    },
                ) { change, drag ->
                    change.consume()
                    var k = knob + drag
                    val len = k.getDistance()
                    if (len > radius) k = k * (radius / len)
                    knob = k
                    onChange(k.x / radius, -k.y / radius)
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .offset { IntOffset(knob.x.roundToInt(), knob.y.roundToInt()) }
                .size(46.dp)
                .clip(CircleShape)
                .background(Accent.copy(alpha = 0.75f)),
        )
    }
}

// ---------------------------------------------------------------------
// Explorer + Properties
// ---------------------------------------------------------------------

@Composable
private fun ExplorerPane(engine: ExecutorEngine, selected: Int, onSelect: (Int) -> Unit) {
    val rows by engine.explorer.collectAsState()
    val props by engine.props.collectAsState()
    var expanded by remember { mutableStateOf(setOf<Int>()) }
    var editing by remember { mutableStateOf<PropRow?>(null) }
    var text by remember { mutableStateOf("") }

    LaunchedEffect(expanded) {
        while (true) {
            engine.requestExplorer(expanded)
            delay(800)
        }
    }
    LaunchedEffect(selected) {
        while (selected >= 0) {
            engine.requestProps(selected)
            delay(1000)
        }
    }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Card(
            colors = CardDefaults.cardColors(containerColor = Color(0xFF080B10)),
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            LazyColumn(Modifier.padding(6.dp)) {
                items(rows) { r ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .background(if (r.id == selected) Accent.copy(alpha = 0.18f) else Color.Transparent)
                            .clickable { onSelect(r.id) }
                            .padding(start = (r.depth * 14).dp, top = 4.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            if (!r.hasChildren) "  " else if (r.id in expanded) "v " else "> ",
                            color = Accent,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.sp,
                            modifier = Modifier.clickable(enabled = r.hasChildren) {
                                expanded = if (r.id in expanded) expanded - r.id else expanded + r.id
                            },
                        )
                        Text(r.name, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        Spacer(Modifier.width(8.dp))
                        Text(r.cls, fontSize = 10.sp, color = Muted, maxLines = 1)
                    }
                }
            }
        }

        Card(
            colors = CardDefaults.cardColors(containerColor = Color(0xFF080B10)),
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            Column(Modifier.padding(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Properties", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    if (selected >= 0) {
                        TextButton(onClick = {
                            engine.deleteInstance(selected)
                            onSelect(-1)
                        }) {
                            androidx.compose.material3.Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Destroy")
                        }
                    }
                }
                if (selected < 0) {
                    Text("Select an object in the Explorer or tap a part in the View tab.", color = Muted, fontSize = 12.sp)
                } else {
                    LazyColumn {
                        items(props) { pr ->
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = pr.editable) {
                                        if (pr.type == "bool") {
                                            engine.setProp(selected, pr.name, if (pr.value == "true") "false" else "true")
                                        } else {
                                            editing = pr
                                            text = pr.value
                                        }
                                    }
                                    .padding(vertical = 5.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(pr.name, fontFamily = FontFamily.Monospace, fontSize = 12.sp, modifier = Modifier.weight(0.42f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(
                                    pr.value,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 12.sp,
                                    color = if (pr.editable) Accent else Muted,
                                    modifier = Modifier.weight(0.58f),
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
                        }
                    }
                }
            }
        }
    }

    val ed = editing
    if (ed != null) {
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(ed.name) },
            text = {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    label = { Text(ed.type) },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    engine.setProp(selected, ed.name, text)
                    editing = null
                }) { Text("Set") }
            },
            dismissButton = { TextButton(onClick = { editing = null }) { Text("Cancel") } },
        )
    }
}
