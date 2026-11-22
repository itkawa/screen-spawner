Title: Screen Spawner 0.3.2 — reconnecting in mirror mode
Tag: v0.3.2

---

A fix for devices that mirror the laptop screen.

## What's fixed

- **Connecting again after leaving works in mirror mode.** When a device mirrored the laptop screen and left, the next connection could fail: GNOME brought the device's screen back already mirrored, at the laptop screen's size, Hermes could not set the size Moonlight asked for inside the mirror, removed the screen, and Moonlight did not connect until GNOME was restarted. Now Hermes gives the screen a place of its own first, sets its size, and the app mirrors it again. Tested: three connections in a row in mirror mode.
- The fix is in the Hermes packages `0.5.1+ss0.2.3` for all systems (builds release [v0.2.3](https://github.com/itkawa/screen-spawner-packages/releases/tag/v0.2.3)).
- README: 2.4 GHz Wi-Fi is enough; four devices at once were tested over it.
- README: to type on the tablet, tap it with three fingers; Moonlight opens the Android keyboard.

## Updating

Installed from a package: `sudo apt upgrade` or `sudo dnf upgrade`.

Installed with `install.sh`: run `git pull` in the `screen-spawner` folder, then `./install.sh`.

New installations: see [INSTALL.md](https://github.com/itkawa/screen-spawner/blob/v0.3.2/INSTALL.md).
