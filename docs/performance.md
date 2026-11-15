# Performance measurements

How much load Screen Spawner puts on the computer while the tablet is in use, and how the stream behaves over Wi-Fi. Measured on 15 November 2026 with [`tools/measure-load.py`](../tools/measure-load.py), 60 seconds per run.

## Setup

* **Laptop:** Lenovo V17 G4 IRU, Intel Core i7-1355U (12 threads), Intel Iris Xe graphics, Ubuntu 22.04, GNOME 42 on X11.
* **Displays:** laptop screen 1920×1080, HDMI monitor 1920×1080, tablet as the third display.
* **Stream:** Hermes 0.5.1 with Screen Spawner's patch, hardware encoding with VAAPI (HEVC), 1280×720 at up to 60 fps as requested by Moonlight, bitrate limit 10 Mbit/s.
* **Tablet:** Android with Moonlight, on the same Wi-Fi network as the laptop.
* **Wi-Fi:** one router with a 2.4 GHz network (channel 10, about 20 other networks nearby on overlapping channels) and a 5 GHz network (channel 36).
* **Video:** a fullscreen video, on the tablet in extended mode and on the laptop screen in mirrored mode.

## Load on the computer

| | Without Hermes | Extended, idle | Mirrored, idle | Extended, video | Mirrored, video |
|---|---|---|---|---|---|
| CPU, whole system | 4% | 6% | 7% | 13% | 14% |
| Hermes | — | 24% of one thread | 36% of one thread | 25% of one thread | 39–43% of one thread |
| Xorg and GNOME Shell | 7% of one thread | 7% | 7% | 23% | 22% |
| Screen Spawner app | 0% | 0% | 0% | 0% | 0% |
| Intel GPU busy | 5% | 14% | 15% | 44% | 39–44% |
| Intel GPU frequency | 300 MHz | ~1190 MHz | ~1230 MHz | ~1060 MHz | ~1190 MHz |
| CPU temperature, average | 44 °C | 45 °C | 45 °C | 45–47 °C | 47–48 °C |

Idle means the desktop with nothing moving. Without Hermes the tablet is not connected.

## The stream

| | Extended, video, 2.4 GHz | Mirrored, video, 2.4 GHz | Extended, video, 5 GHz | Mirrored, video, 5 GHz |
|---|---|---|---|---|
| Frames per second | 49 | 49 | 48 | 45 |
| Encoding time per frame | 2.9 ms | 2.9 ms | 2.8 ms | 2.4 ms |
| Dropped frames | 0 of 19 492 | 0 of 4 787 | 0 of 3 960 | 0 of 12 245 |
| Stream bitrate | 4.2 Mbit/s | 4.0 Mbit/s | 3.8 Mbit/s | 2.0 Mbit/s |
| Ping to the tablet, average / maximum | 9.2 / 53 ms | 7.7 / 44 ms | 2.7 / 11 ms | 2.8 / 25 ms |
| Pings over 20 ms | 27 of 300 | 17 of 300 | 0 of 300 | 1 of 300 |
| Stutter on the tablet | none noticed | none noticed | none noticed | none noticed |

The ping ran every 0.2 s during the same minute, from the laptop to the tablet. A frame at 60 fps has 16.7 ms; encoding takes under 3 ms.

## 25 minutes of video

A light video (water, snow, scrolling text) played on the tablet in extended mode for 25 minutes, over 2.4 GHz Wi-Fi. Measured for 30 seconds at the start and at the end:

| | Start | After 25 minutes |
|---|---|---|
| CPU temperature, average / maximum | 45 / 47 °C | 46 / 46 °C |
| CPU, whole system | 13% | 13% |
| Hermes | 24% of one thread | 25% of one thread |
| Intel GPU busy | 39% | 39% |
| Frames per second | 42 | 46 |
| Dropped frames since the tablet connected | 0 of 2 959 | 0 of 61 393 |

The laptop did not warm up over time, and the load did not grow.

## What this shows

* The computer has plenty of room: Screen Spawner adds 2–3% CPU when idle, and with a fullscreen video the whole system stays at 13–14%.
* No frame was dropped in any run, on either Wi-Fi band, and none in 25 minutes of continuous video; the temperature stayed at 45–46 °C.
* Mirrored mode costs Hermes about half as much again as extended mode, because it copies a 1920×1080 frame instead of a 1280×720 one; for the system as a whole the difference is about one percent.
* 2.4 GHz Wi-Fi worked without noticed stutter, but had occasional network delays of 20–50 ms; on 5 GHz there were practically none. 5 GHz Wi-Fi works best.
* While idle, Hermes still encodes about 52 frames per second of an unchanged desktop, which keeps the GPU near its highest frequency instead of 300 MHz. Sending fewer frames while nothing changes would save power on battery; this is planned as a change to Hermes.
