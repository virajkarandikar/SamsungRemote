# Samsung Remote

A native macOS app that turns your MacBook into a remote for Samsung smart TVs on the same Wi-Fi.

## Features

- **Find TV**: auto-discovers Samsung TVs on your network and connects, with one-time pairing
- D-pad with OK, back, home, menu, info and source
- Volume, mute, channel up/down and playback keys
- App launchers: Netflix, YouTube, Prime Video, Disney+, Spotify, Apple TV
- Text entry for the TV's on-screen keyboard
- Power off, and Wake-on-LAN to turn the TV on
- Keyboard shortcuts while the app is in front

| Key | Action |
| --- | --- |
| Arrow keys | D-pad |
| Return | OK |
| Esc | Back |
| H / M / I | Home / Menu / Info |
| Space | Play/pause |
| `=` / `-` | Volume up / down |
| `0` | Mute |
| `]` / `[` | Channel up / down |

## Requirements

- Apple Silicon or Intel Mac running macOS 13 or later (the prebuilt release is Apple Silicon only)
- A Samsung TV running Tizen (roughly 2016 and newer) on the same network as the Mac

## Install

**Prebuilt:** download the zip from [Releases](../../releases), unzip it and drag `SamsungRemote.app` to Applications. The app is not notarized, so on first launch right-click it and choose **Open**.

**From source:** needs the Xcode command line tools (`xcode-select --install`).

```sh
./build_app.sh
open SamsungRemote.app
```

## Usage

1. Open the app and allow **Local Network** access when macOS asks.
2. Click **Find TV**, or type the TV's IP address and click **Connect**.
3. The first time, the TV shows an Allow prompt. Accept it using the TV's own remote. The pairing token is saved, so you only do this once.

### Typing into the TV

Open a search box or any text field on the TV so its keyboard appears, type in the app's text box, then press Return or click **Send**. Some third-party TV apps don't accept text from remote apps.

### Turning the TV on

The Power button only turns the TV off, because a TV in standby has no network connection to send commands over. **Wake** sends a Wake-on-LAN packet instead. This needs "Power on with Mobile" (or similar) enabled in the TV's network settings, and the app must have connected to the TV once while it was on, so it knows the TV's MAC address.

## Troubleshooting

- **Find TV finds nothing:** check that the TV is on and on the same network as the Mac, and that Samsung Remote is enabled in System Settings → Privacy & Security → Local Network. You can always enter the IP manually.
- **TV denied the connection:** accept the prompt on the TV. If you dismissed it before, check Settings → General → External Device Manager → Device Connection Manager on the TV.
- **Wake does nothing:** enable network power-on in the TV's settings.

## How it works

The app uses Samsung's remote-control WebSocket API (`wss://<tv>:8002/api/v2/channels/samsung.remote.control`). The TV uses a self-signed certificate, so the app accepts it for the TV connection only. Discovery tries SSDP first and falls back to probing port 8001 on every address in the Mac's /24 subnet. The pairing token is stored in the app's preferences.

## Project layout

```
Sources/SamsungRemote/
  SamsungRemoteApp.swift   app entry point
  ContentView.swift        remote UI
  TVClient.swift           TV connection, commands, discovery, Wake-on-LAN
make_icon.swift            generates the app icon
build_app.sh               builds and packages SamsungRemote.app
```

## Limitations

Samsung Tizen TVs only. Other brands (LG, Sony, Roku, Android TV) use different protocols.
