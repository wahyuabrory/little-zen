# Little Zen without Sine

A Windows-focused Little Zen backport for Zen Browser. It runs through `userChromeJS` and does not require Sine.

This project is based on [12th-devs/little-zen](https://github.com/12th-devs/little-zen) and includes the behavior and UI changes developed for this setup.

## Features

- Open a blank Little Zen window with `Ctrl+Alt+N`.
- Use an editable address and search bar inside Little Zen.
- Keep searches and typed addresses in the Little Zen window.
- Use Back, Forward, and Reload navigation controls.
- Open a page link in a focused Little Zen window with `Ctrl+Alt+Click`.
- Open an existing Zen tab in Little Zen with `Ctrl+Alt+Click` on the tab.
- Press `Ctrl+O` in Little Zen to move the page to the most recent Space.
- Press `Ctrl+Alt+O` to select a different Space.
- Use the **Open in Space** toolbar control with searchable Space selection.
- Preserve the live tab when moving it back into the main Zen window when possible.
- Adapt the Little Zen frame and toolbar colors to the loaded page.
- Skip this backport automatically when native Little Zen support is available.

## Requirements

- Zen Browser on Windows.
- A working [`fx-autoconfig`](https://github.com/MrOtherGuy/fx-autoconfig) `userChromeJS` loader.
- `toolkit.legacyUserProfileCustomizations.stylesheets` set to `true` in `about:config`.

This version was developed and tested with the `fx-autoconfig` layout that loads scripts from `chrome/JS` and styles from `chrome/CSS`.

## Install

1. Open `about:support` in Zen.
2. Find **Profile Folder**, then select **Open Folder**.
3. Close Zen.
4. Copy `littleZen.uc.js` to:

   ```text
   <profile>/chrome/JS/littleZen.uc.js
   ```

5. Copy `little-zen.css` to:

   ```text
   <profile>/chrome/CSS/little-zen.css
   ```

6. Add this line at the top of `<profile>/chrome/userChrome.css`:

   ```css
   @import url("CSS/little-zen.css");
   ```

7. Start Zen.

No Sine files or `sine-mods` configuration are required.

## Use

| Action | Shortcut |
| --- | --- |
| Open blank Little Zen | `Ctrl+Alt+N` |
| Open a link in Little Zen | `Ctrl+Alt+Click` |
| Open a main-window tab in Little Zen | `Ctrl+Alt+Click` on the tab |
| Open in the recent Space | `Ctrl+O` |
| Choose another Space | `Ctrl+Alt+O` |

You can also use the **Open in Space** button in the Little Zen toolbar.

## Debugging

Set `extensions.littleZen.debugRouting` to `true` in `about:config` to write detailed routing messages. Restart Zen after changes to the script or stylesheet.

## Compatibility

Zen internal browser APIs can change between releases. If an update breaks the mod, first test with the latest files and inspect the Browser Console. This backport stops itself when Zen exposes native `ZenLittleWindow` support.

## Credits

- Original project: [12th-devs/little-zen](https://github.com/12th-devs/little-zen)
- `userChromeJS` loader: [MrOtherGuy/fx-autoconfig](https://github.com/MrOtherGuy/fx-autoconfig)
