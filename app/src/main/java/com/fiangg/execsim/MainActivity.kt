package com.fiangg.execsim

import android.app.Application
import android.graphics.Paint
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewmodel.compose.viewModel

class SimViewModel(app: Application) : AndroidViewModel(app) {
    val engine = ExecutorEngine(app)
}

internal val Accent = Color(0xFF00E5A8)
internal val Bad = Color(0xFFFF6B6B)
internal val Warn = Color(0xFFFFC857)
private val Miss = Color(0xFFB388FF)
internal val Muted = Color(0xFF8B95A7)

private val DarkScheme = darkColorScheme(
    primary = Accent,
    onPrimary = Color(0xFF00382A),
    secondary = Color(0xFF7C9CFF),
    background = Color(0xFF0E1117),
    onBackground = Color(0xFFE6EAF2),
    surface = Color(0xFF151A23),
    onSurface = Color(0xFFE6EAF2),
    surfaceVariant = Color(0xFF1E2531),
    onSurfaceVariant = Color(0xFFB7C0D0),
    outline = Color(0xFF3A4455),
    error = Bad,
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        setContent {
            MaterialTheme(colorScheme = DarkScheme) {
                val vm: SimViewModel = viewModel()
                AppRoot(vm.engine)
            }
        }
    }
}

private data class Tab(val title: String, val icon: ImageVector)

@Composable
private fun AppRoot(engine: ExecutorEngine) {
    val tabs = listOf(
        Tab("Run", Icons.Filled.PlayArrow),
        Tab("sUNC", Icons.Filled.Science),
        Tab("Functions", Icons.AutoMirrored.Filled.List),
        Tab("Game", Icons.Filled.Dashboard),
        Tab("Settings", Icons.Filled.Settings),
    )
    var selected by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                tabs.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = selected == i,
                        onClick = { selected = i },
                        icon = { Icon(t.icon, contentDescription = t.title) },
                        label = { Text(t.title, fontSize = 11.sp) },
                    )
                }
            }
        },
    ) { pad ->
        Box(
            Modifier
                .padding(pad)
                .fillMaxSize()
                .imePadding(),
        ) {
            when (selected) {
                0 -> RunScreen(engine)
                1 -> SuncScreen(engine)
                2 -> FunctionsScreen(engine)
                3 -> GameScreen(engine)
                else -> SettingsScreen(engine)
            }
        }
    }
}

// ---------------------------------------------------------------------
// Run screen: editor + console
// ---------------------------------------------------------------------

private val SAMPLES: List<Pair<String, String>> = listOf(
    "Hello" to """
print("Hello from " .. identifyexecutor())
print("identity:", getthreadidentity())
print("game:", game.Name, "| players:", #game.Players:GetPlayers())
""".trimIndent(),
    "Env check" to """
local names = {
  "getgenv", "getrenv", "hookfunction", "newcclosure", "getgc", "filtergc",
  "getconnections", "firesignal", "debug.getupvalue", "crypt.hash",
  "Drawing.new", "WebSocket.connect", "request", "readfile", "getscripts",
}
for _, n in ipairs(names) do
  local cur = getgenv()
  for part in string.gmatch(n, "[^.]+") do cur = cur and cur[part] end
  print((cur and "[ok]      " or "[missing] ") .. n)
end
""".trimIndent(),
    "Hooks" to """
local function greet() return "hello" end
local old = hookfunction(greet, function() return "hooked!" end)
print(greet(), "| original:", old())
restorefunction(greet)
print("restored:", greet())

local t = setmetatable({}, { __index = function() return "real" end })
local ref = hookmetamethod(t, "__index", function() return "fake" end)
print(t.anything, ref())
""".trimIndent(),
    "Drawing" to """
local sq = Drawing.new("Square")
sq.Visible = true
sq.Position = Vector2.new(40, 40)
sq.Size = Vector2.new(140, 90)
sq.Color = Color3.fromRGB(0, 229, 168)
sq.Thickness = 3

local c = Drawing.new("Circle")
c.Visible = true
c.Position = Vector2.new(210, 160)
c.Radius = 40
c.Filled = true
c.Color = Color3.fromRGB(255, 107, 107)
c.Transparency = 0.7

local l = Drawing.new("Line")
l.Visible = true
l.From = Vector2.new(30, 220)
l.To = Vector2.new(300, 260)
l.Color = Color3.fromRGB(124, 156, 255)
l.Thickness = 4

local tx = Drawing.new("Text")
tx.Visible = true
tx.Text = "ExecSim Drawing API"
tx.Position = Vector2.new(40, 300)
tx.Size = 20
tx.Color = Color3.new(1, 1, 1)
print("open the Screen tab")
""".trimIndent(),
    "Roblox API" to """
-- the Roblox API dump downloads automatically; see Settings
local part = Instance.new("Part")
print(part.ClassName, part:IsA("BasePart"), part:IsA("PVInstance"), part:IsA("Instance"))
print("Workspace is WorldRoot:", workspace:IsA("WorldRoot"))
print("Reflectance default:", part.Reflectance)

local ok, res = pcall(function()
  return game:HttpGet("https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer")
end)
if ok then
  local info = game:GetService("HttpService"):JSONDecode(res)
  print("Roblox client version:", info.version)
else
  warn("HttpGet failed:", res)
end
""".trimIndent(),
    "Files + crypt" to """
writefile("demo/hello.txt", "hello world")
appendfile("demo/hello.txt", "!")
print(readfile("demo/hello.txt"), isfile("demo/hello.txt"))
for _, f in ipairs(listfiles("demo")) do print("file:", f) end

print(crypt.hash("test", "sha256"))
local key = crypt.generatekey()
local enc, iv = crypt.encrypt("secret", key, nil, "CBC")
print(enc, crypt.decrypt(enc, key, iv, "CBC"))
print(crypt.base64encode("ExecSim"), #lz4compress(string.rep("a", 500)))
""".trimIndent(),
)

@Composable
private fun RunScreen(engine: ExecutorEngine) {
    var code by rememberSaveable { mutableStateOf(SAMPLES[0].second) }
    val lines by engine.console.collectAsState()
    val busy by engine.busy.collectAsState()
    val rcon by engine.rconsole.collectAsState()
    val listState = rememberLazyListState()
    var rconInput by remember { mutableStateOf("") }

    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) listState.scrollToItem(lines.lastIndex)
    }

    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Executor", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(SAMPLES) { s ->
                AssistChip(onClick = { code = s.second }, label = { Text(s.first) })
            }
        }
        OutlinedTextField(
            value = code,
            onValueChange = { code = it },
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            textStyle = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp),
            placeholder = { Text("-- paste a Luau/Lua script") },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { engine.execute(code) }, enabled = !busy) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Spacer(Modifier.size(4.dp))
                Text("Execute")
            }
            OutlinedButton(onClick = { engine.stop() }, enabled = busy) {
                Icon(Icons.Filled.Stop, contentDescription = null)
                Spacer(Modifier.size(4.dp))
                Text("Stop")
            }
            TextButton(onClick = { code = "" }) { Text("Clear code") }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())

        if (rcon.visible) {
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFF05070B)),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(10.dp)) {
                    Text(rcon.title, color = Accent, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    for (l in rcon.lines.takeLast(6)) {
                        Text(l, fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = Color(0xFFCFD6E4))
                    }
                    if (rcon.awaitingInput) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(
                                value = rconInput,
                                onValueChange = { rconInput = it },
                                modifier = Modifier.weight(1f),
                                singleLine = true,
                                placeholder = { Text("rconsoleinput...") },
                            )
                            TextButton(onClick = {
                                engine.submitConsoleInput(rconInput)
                                rconInput = ""
                            }) { Text("Send") }
                        }
                    }
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Console", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            IconTextButton(Icons.Filled.Delete, "Clear") { engine.clearConsole() }
        }
        Card(
            colors = CardDefaults.cardColors(containerColor = Color(0xFF080B10)),
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            LazyColumn(state = listState, modifier = Modifier.padding(8.dp)) {
                items(lines) { l ->
                    val color = when (l.kind) {
                        "error" -> Bad
                        "warn" -> Warn
                        "system" -> Accent
                        "info" -> Color(0xFF7C9CFF)
                        else -> Color(0xFFD9DEE8)
                    }
                    Text(
                        l.text,
                        color = color,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun IconTextButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.size(4.dp))
        Text(label)
    }
}

// ---------------------------------------------------------------------
// sUNC screen
// ---------------------------------------------------------------------

private fun statusColor(status: String): Color = when (status) {
    "pass" -> Accent
    "warn" -> Warn
    "fail" -> Bad
    else -> Miss
}

private fun statusIcon(status: String): ImageVector = when (status) {
    "pass" -> Icons.Filled.Check
    "warn" -> Icons.Filled.Warning
    "fail" -> Icons.Filled.Close
    else -> Icons.Filled.Close
}

@Composable
private fun SuncScreen(engine: ExecutorEngine) {
    val state by engine.tests.collectAsState()
    val busy by engine.busy.collectAsState()
    val settings by engine.settings.collectAsState()
    var filter by rememberSaveable { mutableStateOf("all") }

    val pass = state.results.count { it.status == "pass" }
    val warn = state.results.count { it.status == "warn" }
    val fail = state.results.count { it.status == "fail" }
    val missing = state.results.count { it.status == "missing" }
    val done = state.results.size
    val percent = if (done == 0) 0 else ((pass + warn) * 100) / done

    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("sUNC test", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    "${settings.executorName} ${settings.version}  -  profile: ${settings.profile}",
                    color = Muted,
                    fontSize = 12.sp,
                )
                Text(
                    if (done == 0) "No results yet" else "$percent% success rate",
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (percent >= 90) Accent else if (percent >= 60) Warn else Bad,
                )
                if (state.total > 0) {
                    LinearProgressIndicator(
                        progress = { done.toFloat() / state.total.toFloat() },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Text(
                    "pass $pass   warn $warn   fail $fail   missing $missing   (${done}/${state.total})",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(onClick = { engine.runSunc() }, enabled = !busy) {
                    Icon(Icons.Filled.Science, contentDescription = null)
                    Spacer(Modifier.size(6.dp))
                    Text(if (state.running) "Running..." else "Run sUNC test")
                }
            }
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(listOf("all", "fail", "missing", "warn", "pass")) { f ->
                FilterChip(selected = filter == f, onClick = { filter = f }, label = { Text(f) })
            }
        }
        val shown = if (filter == "all") state.results else state.results.filter { it.status == filter }
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            items(shown) { r ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        statusIcon(r.status),
                        contentDescription = r.status,
                        tint = statusColor(r.status),
                        modifier = Modifier.size(18.dp),
                    )
                    Column(Modifier.weight(1f)) {
                        Text(r.name, fontFamily = FontFamily.Monospace, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        if (r.message.isNotEmpty()) {
                            Text(r.message, fontSize = 11.sp, color = statusColor(r.status), lineHeight = 14.sp)
                        }
                    }
                    Text(r.category, fontSize = 10.sp, color = Muted)
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
            }
        }
    }
}

// ---------------------------------------------------------------------
// Functions screen
// ---------------------------------------------------------------------

@Composable
private fun FunctionsScreen(engine: ExecutorEngine) {
    val present by engine.present.collectAsState()
    val settings by engine.settings.collectAsState()
    var query by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf("All") }

    val shown = REGISTRY.filter { e ->
        (category == "All" || e.category == category) &&
            (query.isBlank() || e.allNames().any { it.contains(query.trim(), ignoreCase = true) })
    }
    val totalNames = REGISTRY.sumOf { it.allNames().size }
    val presentNames = REGISTRY.sumOf { e -> e.allNames().count { present[it] == true } }

    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Functions", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(
            "${REGISTRY.size} functions, $totalNames names incl. aliases  -  $presentNames present right now",
            color = Muted,
            fontSize = 12.sp,
        )
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            placeholder = { Text("Search functions or aliases") },
        )
        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(listOf("All") + CATEGORIES) { c ->
                FilterChip(selected = category == c, onClick = { category = c }, label = { Text(c) })
            }
        }
        LazyColumn(Modifier.weight(1f)) {
            items(shown) { e ->
                val disabled = e.name in settings.disabled
                val ok = present[e.name] == true
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(
                        Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(if (ok) Accent else Bad),
                    )
                    Column(Modifier.weight(1f)) {
                        Text(
                            e.name,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (ok) MaterialTheme.colorScheme.onSurface else Muted,
                        )
                        Text(
                            e.category + "  |  " + e.tag +
                                (if (e.aliases.isEmpty()) "" else "  |  aliases: " + e.aliases.joinToString(", ")),
                            fontSize = 10.sp,
                            color = Muted,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    Switch(checked = !disabled, onCheckedChange = { engine.toggleFunction(e.name) })
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
            }
        }
    }
}

// ---------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------

private data class ProfileInfo(val id: String, val title: String, val desc: String)

private val PROFILES = listOf(
    ProfileInfo("perfect", "Perfect executor", "Every UNC / sUNC function is implemented and behaves like a real executor."),
    ProfileInfo("weak", "Weak executor", "Typical budget executor: debug, hooking, getgc, signals, Drawing and WebSocket are missing."),
    ProfileInfo("fake", "Fake executor (spoofed)", "Every name exists, but nothing really works. Passes a UNC existence check, fails sUNC."),
    ProfileInfo("custom", "Custom", "Pick exactly which functions exist on the Functions tab."),
)

@Composable
private fun SettingsScreen(engine: ExecutorEngine) {
    val settings by engine.settings.collectAsState()
    val apiStatus by engine.apiStatus.collectAsState()
    val apiAuto by engine.apiAuto.collectAsState()
    var name by remember(settings.executorName) { mutableStateOf(settings.executorName) }
    var version by remember(settings.version) { mutableStateOf(settings.version) }
    var identity by remember(settings.identity) { mutableStateOf(settings.identity.toString()) }
    var files by remember { mutableStateOf<List<String>>(emptyList()) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)

        Text("Executor profile", style = MaterialTheme.typography.titleMedium)
        for (p in PROFILES) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = settings.profile == p.id, onClick = { engine.setProfile(p.id) })
                Column(Modifier.weight(1f)) {
                    Text(p.title, fontWeight = FontWeight.SemiBold)
                    Text(p.desc, fontSize = 12.sp, color = Muted)
                }
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
        Text("Identity (identifyexecutor / thread identity)", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Executor name") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = version,
            onValueChange = { version = it },
            label = { Text("Version") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = identity,
            onValueChange = { identity = it.filter { c -> c.isDigit() }.take(1) },
            label = { Text("Default thread identity (0-8)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = { engine.updateIdentity(name, version, identity.toIntOrNull() ?: 8) }) {
            Text("Apply and rebuild environment")
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
        Text("Roblox API dump", style = MaterialTheme.typography.titleMedium)
        Text(
            "ExecSim downloads the full API-Dump.json from the Roblox-Client-Tracker project so Instance.new, " +
                "IsA, GetService, events and properties follow the real Roblox API.",
            fontSize = 12.sp,
            color = Muted,
        )
        Text(apiStatus, fontSize = 12.sp, color = Accent)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Auto-update", fontWeight = FontWeight.SemiBold)
                Text("Checks GitHub every 30 minutes while the app is open and applies a newer dump.", fontSize = 12.sp, color = Muted)
            }
            Switch(checked = apiAuto, onCheckedChange = { engine.setApiAuto(it) })
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { engine.checkApiNow() }) { Text("Check / download now") }
            OutlinedButton(onClick = { engine.removeApiDump() }) { Text("Remove") }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
        Text("Workspace folder", style = MaterialTheme.typography.titleMedium)
        Text(
            "readfile / writefile / listfiles use a private sandbox folder inside this app.",
            fontSize = 12.sp,
            color = Muted,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { files = engine.workspaceFiles() }) {
                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(4.dp))
                Text("List files")
            }
            OutlinedButton(onClick = {
                engine.wipeWorkspace()
                files = emptyList()
            }) { Text("Wipe") }
        }
        if (files.isNotEmpty()) {
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF080B10))) {
                Column(Modifier.padding(10.dp)) {
                    for (f in files) Text(f, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                }
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
        OutlinedButton(onClick = { engine.reset(clearConsole = true) }) { Text("Reset environment") }
        Text(
            "ExecSim runs scripts on an embedded Lua VM against a simulated Roblox client. " +
                "Nothing here touches Roblox. HTTP requests are real; WebSocket is a local echo.",
            fontSize = 11.sp,
            color = Muted,
        )
        Spacer(Modifier.height(24.dp))
    }
}
