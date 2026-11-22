# ExecSim: Roblox executor simulator (Android)

ExecSim is a fake Roblox executor for Android. It runs your Lua/Luau scripts on an embedded Lua VM (LuaJ) against a simulated Roblox client, and it implements the full UNC and sUNC function set (120 functions plus their aliases). Use it to practice executor scripts, or to see how a sUNC test behaves against a perfect, weak, or fake executor.

Nothing here touches Roblox.

## What is inside

- **Run**: script editor, Execute / Stop, console with colored output, `rconsole*` window.
- **sUNC**: one behavior test per function, with pass / warn / fail / missing and a success percentage.
- **Functions**: every UNC/sUNC name and alias, with a switch to turn each one off (custom profile).
- **Game**: a fake Roblox game view. A 3D baseplate world with your R15 character, a virtual joystick, a Jump button, drag to rotate the camera, pinch to zoom, and tap a part to select it. The Explorer shows the full instance tree with live Properties (tap to edit, Destroy to delete). The `Drawing` API and the mouse cursor draw on top of the view.
- **Settings**: executor profile (perfect, weak, fake, custom), `identifyexecutor` name/version, thread identity, workspace folder, Roblox API dump download.

## Engine behavior

Scripts now act on a live world, not just a tree of values:

- Gravity, collisions, anchored and unanchored parts, falling into the void, `Touched` / `TouchEnded`.
- An R15 character with a Humanoid: `WalkSpeed`, `JumpPower`, `Health`, `Died`, `MoveTo`, `TakeDamage`, states, and respawn after 5 seconds.
- Real `CFrame` math (rotation matrices, `lookAt`, `Angles`, `Inverse`, `ToObjectSpace`), `Workspace:Raycast`, `RaycastParams`, `GetPartBoundsInBox`, `Camera:WorldToViewportPoint`, and a live `Mouse`.
- Changes you make from a script show up in the Game tab at once, and edits in the Explorer reach your scripts.

## Build it (no Android Studio needed)

1. Unzip the file. Open the unzipped folder until you see `app`, `build.gradle.kts`, `settings.gradle.kts` and `build.yml.txt`. (If you see another folder with the same name inside, go into it.)
2. Go to github.com/new, type a name, click **Create repository**.
3. Click the **uploading an existing file** link. Select everything INSIDE the folder (not the folder itself), drag it into the page, wait until it finishes, then click **Commit changes**.
4. Add the build workflow: open `build.yml.txt` on your phone or PC and copy all of its text. In your repo click **Add file > Create new file**. In the name box type `.github/workflows/build.yml` (typing each `/` makes the folder), paste the text, and click **Commit changes**.
5. Click the **Actions** tab. Wait 3 to 6 minutes for a green check. (If nothing starts, click the workflow name, then **Run workflow**.)
6. When the check is green, open the repo's **Releases** page and download `ExecSim.apk`. Best: open that page in the browser on your phone so the file never goes through a PC. Install it and allow "install unknown apps" if Android asks.

This is a debug APK (debug key). It is for personal use, not the Play Store.

If the first build fails: open the failed step, type `e: file` in **Search logs**, and paste those lines to Claude to get a small patch.

## Notes and limits

- The code could not be compiled where it was written, so the first build may need a small fix.
- The VM is Lua 5.2 (LuaJ). A small Luau shim handles `+=`-style operators and simple type annotations. `continue` is not supported.
- `WebSocket.connect` is a local echo server. `request` and `game:HttpGet` make real HTTP calls.
- The full Roblox `API-Dump.json` is downloaded automatically from the Roblox-Client-Tracker project on GitHub and cached in the app. It makes class hierarchy, `IsA`, `GetService`, events and properties follow the real API. With auto-update on (Settings), the app checks GitHub every 30 minutes while it is open (ETag check, so an unchanged file costs almost no data) and rebuilds the environment when the dump changes.
- The fixed debug keystore (`app/execsim-debug.keystore`) keeps the app signature the same on every build, so new builds install over the old one. If Android still says the package is invalid, uninstall the old ExecSim once and install again.
- Debug library level offsets (`debug.getstack`, `debug.getlocal`) are the most likely thing to need tuning.
