# Install DLSS5 + ReShade 0.5.10

**Use these steps if you play through EveJS Launcher. ReShade is already included.**

You need a working EveJS setup on Windows and **EveJS Launcher 1.0.68 or newer**. This mod supports EVE client build **3396210**.

Version 0.5.10 fixes a 110-second installer cutoff that could interrupt a slow download or payload preparation. It keeps the 0.5.9 RenoDX, ReShade, NVIDIA and client patch bytes. Those renderer bytes were tested in EVE on an **RTX 5090 with NVIDIA driver 617.14**; the updated installer still needs a live retry on the affected computer.

**Already have 0.5.8 or 0.5.9?** Close all EVE clients, open **Mods**, then use the gold **Update** button on the DLSS5 row. Let the launcher finish. If the row was previously off after a failed install, switch it on after the update and check for **CONFIGURED ON** before launching again. Keep your recovery backups. The steps below are for a new install or a manual upgrade from 0.5.7.

This package supports both known build 3396210 client variants, including the client used with EveJS 0.12.9. It accepts the `eve.js` and `evejs-repo` server package names. The installer checks the files it will change, preserves unrelated mod files, and keeps recovery backups.

## 1. Download the mod

Click **[Download EveJS-DLSS5-0.5.10.zip](https://github.com/V0nCleef/EveJS-DLSS5/releases/download/v0.5.10/EveJS-DLSS5-0.5.10.zip)**.

Save it somewhere you can find, such as **Downloads**.

**Leave the ZIP as it is. Do not extract it.** The launcher will unpack it for you. You do not need `Source code` or the `.update.json` file.

## 2. Open the correct launcher

1. Close **all EVE game windows**. Keep the launcher open.
2. Check the version at the bottom-right of the launcher. It must say **1.0.68 or newer**.
3. If it is older, update the launcher first. You can also [download Launcher 1.0.68 here](https://github.com/V0nCleef/evejs-launcher/releases/tag/v1.0.68).

If you already play successfully through this launcher, leave its paths as they are.

If you are setting it up for the first time, open **Settings**:

- **EveJS Root** is your server folder, containing `package.json` and `Play.bat`.
- **EVE Client Path** is the game's `tq` folder, containing `bin64/exefile.exe`.

These are two different folders. Finish setting up EveJS and confirm the game works before adding the mod.

## 3. Already have DLSS5 0.5.7? Remove it first

**Never installed DLSS5 before? Skip to step 4.**

1. In the launcher, click **Mods** on the left.
2. Find the **EveJS DLSS5** row.
3. Click its **UNINSTALL** button.
4. Click **Yes** when the launcher asks whether to uninstall.
5. Wait for the **DLSS5 Uninstalled** message. Close that message.

The launcher keeps the recovery package and backups. Your private profile settings are retained automatically; there is no separate “keep settings” checkbox to find.

**If uninstall reports an error, stop here and ask for help with that exact message. Do not delete or overwrite the old mod folder.**

Updating the launcher alone does **not** update DLSS5 0.5.7. It also does not add an Update button to that old mod.

## 4. Add the new ZIP

1. Open **Mods** in the launcher.
2. Click **Add ZIP**.
3. Find the **EveJS-DLSS5-0.5.10.zip** file you downloaded in step 1.
4. Select it and click **Open**.
5. Wait for **EveJS DLSS5 + ReShade** to appear in the mod list. It starts switched off.

**You do not need to copy files into the mods folder yourself.**

## 5. Turn the mod on

1. On the **EveJS DLSS5 + ReShade** row, click the **small on/off switch at the far right**.
2. Wait for installation to finish. The first installation may take longer because it downloads the files it needs.
3. Check that the row says **CONFIGURED ON**. If it shows an error instead, stop and copy the error message when asking for help.

## 6. Launch EVE

1. Start your server and market as you normally do.
2. Launch your character through the launcher.
3. In EVE, press **Esc** and open the graphics settings.
4. Set **Upscaling** to **DLSS** and apply the change.
5. Close the Esc menu. Press **F6** to toggle Neural Rendering on or off in that game window.

**Neural Rendering is the extra visual effect. It is separate from DLSS upscaling and Frame Generation.** It is not a promise of higher FPS.

## Optional: choose a saved setting for each profile

1. Close the EVE window for that profile.
2. Open **Mods → Configure** on the DLSS5 row.
3. Choose the profile from the list and click **OK**.
4. Set **Enable Neural Rendering** how you want it, then click **Save**.
5. Close the settings window and launch that profile again.

If no profiles are listed, launch an account through the launcher once, close its EVE window, then try Configure again.

## What happens with later DLSS5 updates?

Version **0.5.8 and later** can show a gold **Update** button on the mod row and a gold count beside **Mods**. Click Update to read its changes and start the update. The window shows download progress and installation stages.

**The move from 0.5.7 to 0.5.8 is the one-time manual upgrade described above.**

## Need the standalone scripts or technical details?

[Standalone installation, recovery, compatibility and licensing](https://github.com/V0nCleef/EveJS-DLSS5/blob/main/docs/TECHNICAL.md).
