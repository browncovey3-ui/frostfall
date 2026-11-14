# Frostfall

Snow on your Mac's desktop. A small menu-bar app: soft flakes drift down over your screen, pile up along the bottom and on the tops of your windows, and scatter when you push the cursor through them.

Requires macOS 13 or later. Apple silicon and Intel.

## What it does

- **Falls.** Every flake has its own size, speed and sway, with a slow breeze that shifts over time. Near flakes are bigger, brighter and faster.
- **Settles.** Snow builds into drifts along the bottom of the screen and on the top edge of any window with room above it, and slumps to a natural slope.
- **Moves.** Push the cursor through a drift and it ploughs aside and sprays. Drag a window quickly and its snow slides off. Close or minimise a window and its snow drops in lumps that burst where they land.
- **Melts.** Turn on Melt Snow and drifts thaw slowly so they never take over.
- **Stays out of the way.** Clicks pass straight through. Snow is left out of screenshots and screen sharing unless you turn on Show in Screenshots. It pauses when the display sleeps or the Mac is locked.

Everything is in the snowflake menu in the menu bar: Intensity, Opacity, Settle on Ground, Settle on Windows, Melt Snow, Clear Snow, Snow Behind Windows, Show over Full Screen, Show in Screenshots, Pause Snow, Launch at Login, Quit.

No permissions are needed. The app reads only the positions of other windows, never their contents, and makes no network connections.

## Install

### Download

Get `Frostfall.zip` from the [latest release](https://github.com/browncovey3-ui/frostfall/releases/latest), unzip it and open Frostfall.app. The app is not notarised by Apple, so the first launch is blocked: open System Settings > Privacy & Security and choose Open Anyway.

### Build it yourself

You need Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/browncovey3-ui/frostfall.git
cd frostfall
bash build.sh
open build/Frostfall.app
```

## How it works

One transparent, click-through window per display hosts a SpriteKit scene. Flakes are sprites sharing one texture. Each surface that catches snow (the screen bottom, each window top) is a heightmap with one value per two points of width, drawn as a filled path. Window positions come from `CGWindowListCopyWindowInfo`, polled a few times a second and faster while something is moving.

## Credits

Frostfall is an independent implementation inspired by desktop snow apps such as Snowhush and SnowFall. It shares no code or assets with them.

MIT licensed.
