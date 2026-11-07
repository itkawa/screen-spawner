# SmartDeviceDisplay

**SmartDeviceDisplay** aims to turn any number of smart devices (tablets, phones, smart TVs) into **extra monitors** for a Linux computer, connected over your home Wi-Fi network.

The goal is for each device to be either:

* an **extended display**: a separate monitor with its own workspace, or
* a **mirrored display**: a copy of an existing screen.

> **Current status:** the scripts set up **one extended virtual display**, and the setup has only been used with one Android tablet. With the EVDI backend Hermes supports a single virtual display; more than one needs its Hermes-KMS backend, which these scripts do not install. Mirroring and smart TVs have not been tested.

You don't need cables, special hardware, or a custom app on the device. SmartDeviceDisplay uses **low-latency game-streaming technology** and ties together existing open-source tools:

| Component | Role |
|-----------|------|
| [EVDI](https://github.com/DisplayLink/evdi) | Linux kernel module that creates virtual displays the OS treats as real monitors |
| [Apollo-Linux / Hermes](https://github.com/MrOz59/Apollo-Linux) | Linux port of Apollo, a fork of [Sunshine](https://github.com/LizardByte/Sunshine). It captures each virtual display and streams it |
| Intel VAAPI | Hardware H.264 / HEVC encoding for low CPU usage and low latency |
| [Artemis](https://github.com/ClassicOldSong/moonlight-android) / [Moonlight](https://moonlight-stream.org/) | Client on the device: Android phones, tablets, Android TV and Google TV, plus other platforms Moonlight supports |

The repository contains scripts that install, configure, and remove the whole stack on Ubuntu.

---

## Installation

### Requirements

* Ubuntu with an X11 session; tested on Ubuntu 22.04 with GNOME
* **An Intel GPU.** The scripts install only the Intel VAAPI driver and build Hermes without CUDA, so AMD and NVIDIA GPUs get no hardware encoding from this setup
* `sudo` access and an internet connection

### Install

```bash
git clone https://github.com/itkawa/smart-device-display
cd smart-device-display
./install.sh
```

The script installs the dependencies, configures EVDI to load at boot, and builds Hermes in `~/Apollo-Linux` from a tested commit with the fix from `patches/evdi-fix.patch`.

The build uses a single job by default, because parallel compilation can run out of memory on laptops, and it takes a long time. To build faster:

```bash
BUILD_JOBS=4 ./install.sh
```

When it finishes, continue with [Starting Hermes](#15-starting-hermes) and [Pairing the tablet](#5-pairing-the-tablet).

`additional_monitor_cfg.sh` is not part of the installation: Hermes does not read the file it creates.

### Uninstall

```bash
./uninstall.sh
```

`install.sh` records every change it makes in `~/.local/state/smart-device-display/installed.list`, and `uninstall.sh` removes only those. Anything that was there before the installation stays. `~/Apollo-Linux` is kept if it contains your own changes.

---

## Apollo-Linux / Hermes + EVDI

The current setup has been tested with an Android tablet and an Ubuntu laptop on the same local network.

The project combines:

* **EVDI** — creates a real virtual display on Linux
* **Hermes / Apollo-Linux** — captures and streams the virtual display
* **Intel VAAPI** — hardware H.264 / HEVC video encoding
* **Artemis / Moonlight-compatible Android client** — displays the streamed monitor on the tablet

The goal is not traditional screen mirroring.

The intended setup is:

```text
┌──────────────────────── Ubuntu laptop ────────────────────────┐
│                                                               │
│  Applications / games                                        │
│          │                                                    │
│          ▼                                                    │
│     EVDI virtual monitor                                     │
│          │                                                    │
│          ▼                                                    │
│     Hermes / Apollo-Linux                                    │
│          │                                                    │
│          ▼                                                    │
│     Intel VAAPI hardware encoder                             │
│          │                                                    │
└──────────┼────────────────────────────────────────────────────┘
           │
           │ H.264 / HEVC over local network
           ▼
    ┌─────────────────┐
    │ Android tablet  │
    │ Artemis/Moonlight│
    └─────────────────┘
```

---

# 1. Why use a virtual display?

A normal remote-desktop application usually captures the existing desktop.

That is not what we want.

The target configuration is:

```text
Laptop display
     +
EVDI virtual display
```

The operating system sees the virtual display as an additional monitor.

Therefore applications can be placed on it independently.

For example:

```text
┌─────────────────────┐    ┌─────────────────────┐
│                     │    │                     │
│   Main laptop      │    │   EVDI display      │
│   monitor          │    │                     │
│                     │    │                     │
└─────────────────────┘    └─────────────────────┘
          laptop                  tablet
```

This makes the Android tablet behave conceptually like a second monitor rather than a mirrored copy of the first one.

---

# 2. Why EVDI?

EVDI provides a virtual display interface at the Linux DRM level.

The important distinction is:

```text
Physical monitor
      OR
Virtual monitor
```

The application does not need to know that the second display is physically somewhere else.

Linux can treat the EVDI display as another output.

This is exactly what we need for the architecture.

---

# 3. Why Hermes / Apollo-Linux?

Hermes is the streaming server used in this setup.

It provides:

* virtual display support through EVDI
* screen capture
* hardware video encoding
* network streaming
* client pairing
* Web UI
* Sunshine/Moonlight-compatible streaming functionality

The binary in this build is still named:

```text
sunshine
```

while the application identifies itself as Hermes.

---

# 4. Android tablet

The tablet needs a compatible client such as Artemis or another Moonlight-compatible Android client.

The tablet does **not** need to receive raw desktop frames.

Instead, Hermes encodes the display into a compressed video stream:

```text
Virtual display
      ↓
Video frames
      ↓
H.264 / HEVC
      ↓
Network packets
      ↓
Android hardware decoder
      ↓
Tablet screen
```

The tablet therefore performs primarily:

```text
network receiving
+
hardware video decoding
+
display
```

rather than rendering the desktop itself.

---

# 5. Pairing the tablet

Start Hermes on Ubuntu:

```bash
cd ~/Apollo-Linux
./build/sunshine
```

Open:

```text
https://localhost:47990
```

Complete the initial Hermes setup.

Then install the compatible client on the Android tablet.

The tablet and Ubuntu laptop should be connected to the same local network.

Add the Ubuntu computer in the Android client.

The client will provide a pairing PIN.

Enter that PIN in the Hermes Web UI.

After pairing, the tablet can connect to Hermes.

---

# 6. Network topology

The preferred setup is:

```text
Ubuntu laptop
     │
     │ Wi-Fi / Ethernet
     │
     ▼
Local router
     │
     │ Wi-Fi
     ▼
Android tablet
```

An Ethernet connection for the laptop is preferable when available.

A good 5 GHz Wi-Fi connection can also work very well.

The important point is that both devices should be on the same local network with a stable, low-latency connection.

---

# 7. Why we expect this to be fast

The important thing is that the system does **not** send an uncompressed framebuffer across the network.

A typical display might be:

```text
1920 × 1080 × 60 FPS
```

Sending raw frames would require an enormous amount of bandwidth.

Instead, the pipeline is:

```text
EVDI
  ↓
capture
  ↓
hardware video encoding
  ↓
compressed H.264 / HEVC
  ↓
LAN/Wi-Fi
  ↓
hardware decoding
  ↓
display
```

This is essentially the same general strategy used by game-streaming technologies.

---

# 8. Hardware encoding

Our Intel GPU exposes:

```text
h264_vaapi
```

and:

```text
hevc_vaapi
```

to Hermes.

This is important because video encoding is performed by dedicated GPU/media hardware rather than being entirely handled by the CPU.

The target path is therefore:

```text
CPU
 └── application / desktop rendering

Intel media hardware
 └── H.264 / HEVC encoding

Network
 └── compressed stream

Android hardware
 └── video decoding
```

This reduces CPU overhead and avoids the latency that a heavily loaded software encoder could introduce.

---

# 9. Why this can have low latency

The total delay can be thought of approximately as:

```text
capture
+
encode
+
network
+
decode
+
display
```

We are optimizing every stage.

### Capture

EVDI provides a dedicated virtual display rather than requiring an external camera or physical capture device.

### Encoding

Intel VAAPI provides hardware H.264/HEVC encoding.

### Network

The stream stays inside the local network.

There is no requirement to send the video through an external cloud server.

### Decoding

Modern Android devices normally have dedicated hardware video decoders.

Therefore the tablet does not need to decode the video entirely on the CPU.

---

# 10. Why an IP address does not make it faster

The important factor is not the IP address itself.

Latency depends on the entire pipeline:

```text
capture
→ encode
→ network
→ decode
→ display
```

Using a local IP helps because it allows the stream to remain inside the LAN.

But the actual latency depends on:

* Wi-Fi quality
* network congestion
* encoder latency
* bitrate
* resolution
* frame rate
* Android decoder latency
* tablet display refresh behaviour

---

# 11. Why we expect this to be substantially better than ordinary remote desktop

Traditional remote desktop software may perform additional desktop-level processing, compression and synchronization.

Our architecture is closer to a game-streaming pipeline:

```text
virtual display
      ↓
video encoder
      ↓
low-latency network stream
      ↓
hardware decoder
      ↓
display
```

That is a much more suitable architecture for a second-screen use case where responsiveness matters.

However, the exact latency must be measured on the actual laptop, network and tablet.

We should not assume that theoretical hardware capabilities automatically mean imperceptible latency.

---

# 12. Target configuration

The preferred initial test configuration is:

```text
Resolution:
1920 × 1080

Refresh rate:
60 Hz

Codec:
H.264

Encoder:
Intel VAAPI

Network:
5 GHz Wi-Fi or Ethernet + 5 GHz Wi-Fi

Client:
Artemis / Moonlight-compatible Android client
```

H.264 is a good first test because it generally provides excellent hardware support and relatively low decoding complexity.

HEVC can be tested afterwards.

---

# 13. Expected data path

The complete path is:

```text
                  LAPTOP

┌─────────────────────────────────────────────┐
│                                             │
│  Application / Game                         │
│           │                                 │
│           ▼                                 │
│  EVDI Virtual Monitor                       │
│           │                                 │
│           ▼                                 │
│  Hermes Capture                             │
│           │                                 │
│           ▼                                 │
│  Intel VAAPI                                │
│  H.264 / HEVC Encoder                       │
│           │                                 │
└───────────┼─────────────────────────────────┘
            │
            │ Local network
            ▼
┌─────────────────────────────────────────────┐
│              ANDROID TABLET                 │
│                                             │
│  Network                                    │
│      ↓                                      │
│  Hardware Video Decoder                     │
│      ↓                                      │
│  Artemis / Moonlight                        │
│      ↓                                      │
│  Tablet Display                             │
│                                             │
└─────────────────────────────────────────────┘
```

---

# 14. What has already been validated

The build has successfully demonstrated:

### EVDI

```text
EVDI kernel module
```

is loaded.

Hermes reports:

```text
EVDI available - real virtual displays supported!
```

and:

```text
Linux virtual display driver initialized successfully.
```

### Hardware encoding

Hermes reports:

```text
Found H.264 encoder: h264_vaapi [vaapi]
```

and:

```text
Found HEVC encoder: hevc_vaapi [vaapi]
```

### Web UI

Hermes provides:

```text
https://localhost:47990
```

### Remaining end-to-end validation

The final part still needs to be tested:

```text
EVDI virtual monitor
        ↓
Ubuntu sees second display
        ↓
Hermes streams it
        ↓
Android client receives it
        ↓
Tablet shows the virtual display
```

Only after this test can we call the complete second-monitor setup validated.

---

# 15. Starting Hermes

From the terminal:

```bash
cd ~/Apollo-Linux
./build/sunshine
```

Or use the installed desktop launcher:

```text
Hermes
```

The launcher intentionally uses:

```text
Terminal=true
```

during the initial setup so that startup errors remain visible.

Once everything is stable, this can be changed to a background launcher.

---

# 16. Checking the virtual monitor

With Hermes running:

```bash
xrandr --query
```

and:

```bash
xrandr --listmonitors
```

These commands can be used to check whether Ubuntu sees the additional virtual display.

---

# 17. Performance expectations

The goal is not to claim that the tablet will behave exactly like a physical DisplayPort/HDMI monitor.

There will always be some additional latency because the signal must be:

```text
captured
→ encoded
→ transmitted
→ decoded
→ displayed
```

A physical monitor avoids most of this pipeline.

The reason this architecture is promising is that the expensive parts are specifically designed to be fast:

```text
Intel hardware encoder
+
local network
+
Android hardware decoder
```

With a good local network, sensible bitrate and a capable tablet, the result should feel substantially more responsive than a traditional remote-desktop session.

The actual result should be measured rather than assumed.

---

# 18. Troubleshooting

## Hermes does not start

Check:

```bash
cd ~/Apollo-Linux
./build/sunshine
```

Look for errors in the terminal.

---

## EVDI is missing

Check:

```bash
lsmod | grep evdi
```

If nothing appears:

```bash
sudo modprobe evdi
```

---

## No virtual display appears

Check:

```bash
xrandr --query
```

and:

```bash
cat /sys/devices/evdi/count
```

Also make sure Hermes is running.

---

## VAAPI encoder is missing

Run:

```bash
vainfo
```

Check that the Intel media driver is installed:

```bash
dpkg -l | grep intel-media-va-driver
```

Hermes should ideally report:

```text
h264_vaapi
```

---

## CAP_SYS_ADMIN / KMS warning

A message such as:

```text
Failed to gain CAP_SYS_ADMIN
Couldn't get handle for DRM Framebuffer
```

does not automatically mean the EVDI/X11 configuration is broken.

The important checks for this setup are:

```text
EVDI available
Linux virtual display driver initialized successfully
h264_vaapi
```

---

# 19. Project philosophy

This project deliberately uses the simplest architecture that gives us a real virtual monitor:

```text
EVDI
+
Hermes
+
VAAPI
+
Android streaming client
```

We are not adding unnecessary components such as:

* CUDA
* NVIDIA-specific software
* cloud streaming services
* Gamescope
* physical DisplayLink hardware

The objective is to keep the path short:

```text
virtual display
→ hardware encode
→ local network
→ hardware decode
→ tablet
```

That short path is the main reason we expect the system to be responsive.

---

# 20. Final goal

The finished setup should make the Android tablet behave like a wireless second monitor:

```text
                 ┌─────────────────┐
                 │ Laptop display  │
                 └─────────────────┘

                 ┌─────────────────┐
                 │ Android tablet  │
                 │                 │
                 │ EVDI display    │
                 └─────────────────┘
```

The laptop remains responsible for the actual application rendering.

The tablet primarily receives and displays the compressed video representation of the virtual monitor.

This is the intended architecture of the project.

---

# Author

Developed by [itkawa](https://github.com/itkawa).

Repository: <https://github.com/itkawa/smart-device-display>

Bug reports and suggestions are welcome via [GitHub Issues](https://github.com/itkawa/smart-device-display/issues).

---

# License

Copyright (C) 2026 itkawa

This project is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.

You may use, modify, and redistribute it. Any distributed modified version must also be released under GPL-3.0.

Third-party components (EVDI, Apollo-Linux / Hermes, Sunshine, Moonlight, Artemis) are separate projects with their own licenses.
