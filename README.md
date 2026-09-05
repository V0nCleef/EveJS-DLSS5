# EveJS DLSS5

Add optional AI-enhanced visuals to your local EveJS game.

**[Download DLSS5 0.5.7](https://github.com/V0nCleef/EveJS-DLSS5/releases/tag/v0.5.7)** · **[Get EveJS Launcher 1.0.52](https://github.com/V0nCleef/evejs-launcher/releases/tag/v1.0.52)** · **[Launcher GitHub](https://github.com/V0nCleef/evejs-launcher)**

This is a community mod for **local EveJS**, not for the official EVE Online service.

## Before you start

- Have a working **EveJS installation** connected to **client build 3396210**. DLSS5 does not restrict the EveJS package version; the exact EVE client build is still pinned.
- Use **64-bit Windows** with **Windows PowerShell 5.1**.
- You need compatible NVIDIA RTX hardware. This package was tested on an **RTX 5090**; other cards have not been verified by this project.
- Have an internet connection for the first installation. It downloads about **108 MiB** of required files and keeps them for reuse.
- **Close all game clients before installing, updating or uninstalling.** Keep a backup of your working setup.

**Choose ONE installation method below.** Launcher users do not need to run the standalone installer.

> If two EveJS folders use the same `tq` client, they share one graphics installation and one rollback record beside that client. Only one EveJS root owns the active receipt at a time. With every game client closed, 0.5.6 and later can safely hand that ownership to an immediate sibling EveJS folder.

## What are DLSS, NR and FG?

These are different things:

| Name | Plain-English meaning |
| --- | --- |
| **DLSS upscaling** | Builds a higher-resolution picture from a lower-resolution one. This is the DLSS option in the game's graphics settings. |
| **NR — Neural Rendering** | The extra AI visual effect added by this mod. It changes the appearance of lighting and materials in the picture. |
| **FG — Frame Generation** | Creates additional frames to make motion look smoother. It is a separate setting, not the NR on/off switch. |

NR adds visual processing; it is **not a promise of higher FPS**. It is also not the same thing as ray tracing. [NVIDIA's explanation of Neural Rendering](https://www.nvidia.com/en-us/geforce/news/dlss5-breakthrough-in-visual-fidelity-for-games/).

**DLSS can be on while NR is off.** In that case, you are using DLSS upscaling without the mod's NR effect.

ReShade is the in-game menu used to show the add-on. RenoDX is the component that provides the NR controls. **You do not need to install either separately.**

## Option A — Install with EveJS Launcher

1. Download and open [EveJS Launcher 1.0.52](https://github.com/V0nCleef/evejs-launcher/releases/tag/v1.0.52).
2. In **Settings**, check that **EveJS Root** is the folder containing `package.json` and `Play.bat`, and **EVE Client Path** is the game's `tq` folder. This launcher-mod workflow uses **Native — run directly on Windows**, not Docker.
3. Download **`EveJS-DLSS5-0.5.7.zip`** from the [DLSS5 release page](https://github.com/V0nCleef/EveJS-DLSS5/releases/tag/v0.5.7). Choose this file under **Assets**, not **Source code**.
4. Right-click the ZIP and choose **Extract All**. Do not run anything from inside the ZIP.
5. In the launcher, open **Mods → Open Mod Folder**. If it says **Create Mod Folder**, click that first. Place the extracted **`DLSS5` folder** directly inside that Mods folder.
6. Click **Refresh**. You should see **EveJS DLSS5** with **ENABLED-AUTO**. It is enabled automatically; there is no extra checkbox to turn on.
7. Start the game server and market as usual, then launch a character. The launcher downloads and installs the required files **when it prepares that first client**. Let it finish; the first launch takes longer.

The folder layout should look like this:

```text
Your EveJS folder/
├── package.json
├── Play.bat
└── mods/
    └── DLSS5/
        ├── evejs-launcher.client-mod.json
        ├── Install-DLSS5.bat
        └── ...the rest of the extracted files
```

Do not put another `DLSS5` folder inside `mods/DLSS5`. Keep the entire extracted folder together.

**Starting the server alone does not install DLSS5.** You do not need **Apply & Restart Server** for this mod. Launch a character, then follow “Turn it on in game” below.

## Option B — Install without the launcher

Use this if you normally start EveJS with its `.bat` files.

1. Download **`EveJS-DLSS5-0.5.7.zip`** from the [release page](https://github.com/V0nCleef/EveJS-DLSS5/releases/tag/v0.5.7).
2. Right-click it → **Extract All**. Keep the complete `DLSS5` folder somewhere with a short path, for example `D:\DLSS5`. Keep it for uninstalling later.
3. Close your game clients and double-click **`Install-DLSS5.bat`** inside that folder.
4. When asked for your EveJS folder, paste the folder containing **`package.json` and `Play.bat`**, then press Enter. This is **not** your `tq` client folder. The installer reads the client location from your EveJS setup; if it separately asks for the client folder, select `tq`.
5. Check the EveJS and client paths printed in the window. Wait for **“DLSS5 integration installed.”** If an error appears, keep the window open and save the message.
6. Start **`StartServer.bat`**, **`StartMarketServer.bat`**, then your normal **`Play.bat`** and log in.

No new character profiles or replacement `Play.bat` are needed.

## Turn it on in game

1. Open the game's **Settings → Display & Graphics** page.
2. Set **Upscaling → DLSS**. There is no separate “DLSS5” entry to select.
3. Wait for the change to finish. **Switching into DLSS automatically turns NR on.**
4. Frame Generation is optional. You do not need to enable it to use NR.

To check NR, open the ReShade menu using the key shown in its startup banner. In **Add-ons**, look for **DLSS 5 Neural Rendering** and its NR control/status. A ReShade banner by itself only shows that ReShade loaded.

### F6 and switching settings

- **Press F6 once** to turn NR off or back on in the game window you are using. DLSS upscaling stays selected.
- With two clients open, **click the client you want to control first**. F6 only affects that foreground client.
- Switch **DLSS → Off or FSR**: NR turns off automatically.
- Switch **Off or FSR → DLSS**: NR turns on automatically, even if you previously turned it off with F6.
- Change DLSS quality, shaders or Frame Generation while staying on DLSS: your manual NR choice is kept.
- If the game starts with DLSS already selected, NR can still be off. Check it and press F6 if needed.

Graphics changes can take several seconds. Let one change finish before making the next; do not repeatedly press F6 while a change is still being applied.

## Remove it with the launcher

1. Close **all game clients**, including any second client.
2. Open the launcher and check that it is pointing to the EveJS setup where you installed the mod.
3. Open **Mods** and click **Uninstall** beside **EveJS DLSS5**.
4. Check the paths in the confirmation, click **Yes**, and wait for the success message.
5. Launch normally when you want to play again.

The uninstaller restores the original client files and settings it backed up. It moves the mod folder out of the active Mods list and keeps a recoverable copy and backups.

**Do not just delete the mod folder.** F6, Upscaling Off, and closing ReShade do not uninstall it.

## Remove a standalone installation

1. Close all game clients.
2. Open the same extracted `DLSS5` folder you used to install it.
3. Double-click **`Uninstall-DLSS5.bat`**.
4. If asked, enter the **same EveJS folder** you selected during installation.
5. Wait for **“Original client files and EveJS config restored.”**

You can then start the game normally. Your characters and server/market data are not removal targets.

Keep the client-scoped backups in **`the folder containing tq\_evejs\dlss5\install`**. They belong to that physical client, not to a particular EveJS server folder. If uninstall reports an error, do not delete the package or backups; save the error and ask for help.

**Installed through Mods? Use the launcher's Uninstall button instead.** Running the standalone uninstaller but leaving `mods/DLSS5` in place can make the launcher install it again on the next client launch.

## Updating later

For the 0.5.6 → 0.5.7 hotfix, close every client and replace the complete
`mods\DLSS5` package folder with 0.5.7. No client reinstall is needed because the
renderer payload and client-scoped receipt are unchanged. Use Launcher 1.0.52.

For other version changes, follow that release's upgrade instructions. Do not
assume an in-place package replacement is safe unless the release explicitly
says so.

Unless a release explicitly permits a package-only replacement, do not overwrite
an installed old package, delete its backups, or move the client folder before
uninstalling.

## Moving to a newer EveJS folder

For 0.5.6 and later, close every game client, copy the complete `mods\DLSS5` folder into the new EveJS root, select that root in its matching launcher, then launch a character. If the old and new EveJS roots are immediate siblings and use the same physical `tq`, the manager verifies the old receipt, payload, backups and configuration, restores the old root, archives its receipt unchanged, and creates a fresh receipt for the new root.

Do **not** copy or edit `_evejs\dlss5\install`; it follows the physical client automatically. Character, item, server and market databases are not DLSS5 files and are never migration targets.

Version 0.5.5 used root-local state. Its active installation must be explicitly restored with the original 0.5.5 package before the first 0.5.6-or-later installation. Client-scoped packages refuse to silently adopt or relabel that old receipt.

## Quick help

**The mod does not appear in the launcher.**

Check the launcher's selected EveJS folder, the folder layout above, and that you used the release ZIP. Then click Refresh.

**Windows says “Path too long.”**

Extract to a shorter location, such as `D:\DLSS5`, not inside several nested download folders.

**I only see “DLSS,” not “DLSS5.”**

That is correct. Select DLSS; NR is the additional effect controlled by this mod.

**I turned NR off but ReShade is still there.**

That is normal. Turning off an effect is not uninstalling it.

**Do I need the mod to update my launcher?**

No. Launcher 1.0.52 works without DLSS5. Updating the launcher alone does not install this mod.

**Something failed.**

Stop and keep the exact error message. For a standalone install, `Verify-DLSS5.bat` checks installed files; it does not prove the effect is rendering in game. [Report a DLSS5 problem here](https://github.com/V0nCleef/EveJS-DLSS5/issues). Include your GPU, EveJS version and what you clicked. Do not post passwords or private account details.

## More information

- [Release notes and downloads](https://github.com/V0nCleef/EveJS-DLSS5/releases)
- [Technical details for developers](https://github.com/V0nCleef/EveJS-DLSS5/blob/main/DLSS5/SOURCE-GENERATION.md)
- [License information](https://github.com/V0nCleef/EveJS-DLSS5/blob/main/DLSS5/LICENSING.md) and [third-party notices](https://github.com/V0nCleef/EveJS-DLSS5/blob/main/DLSS5/THIRD-PARTY-NOTICES.md)

Original project contributions are MIT licensed. Third-party components keep their own licenses. This is not an official CCP, NVIDIA, RenoDX or ReShade product.
