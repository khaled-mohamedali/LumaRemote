# Luma Remote

A native SwiftUI remote for LG webOS TVs, written for an **LG 32LM577BPUA** (webOS 4.5,
2019). No ads, subscriptions, analytics, accounts or third-party code. It talks only to
your TV on your local network.

## Open and run

1. Open `LumaRemote.xcodeproj` in **Xcode 16 or later** (Xcode 26 recommended; the project
   uses folder-synchronized groups and Swift 6 with default `MainActor` isolation).
2. Select the **LumaRemote** target › *Signing & Capabilities* › choose your Team. A free
   Apple ID works for installing on your own iPhone.
3. Run on your iPhone (iOS 17+). On first connect iOS asks for **Local Network** access.
   Allow it; without it no connection is possible.
4. Tap **Enter IP address**, type your TV's IP, **Test connection**, then **Save & Pair**.
   By default the TV shows a **pairing code** that you type on the iPhone, so no TV remote
   is needed. Choose **Accept on TV** instead if you prefer pressing Accept with the remote.

If the `.xcodeproj` gives you trouble, `project.yml` can regenerate it:
`brew install xcodegen && xcodegen`.

## Architecture

```
SwiftUI Views ──▶ ViewModels (RemoteViewModel, DevicesViewModel, KeyboardViewModel)
                       │  no socket code above this line
                       ▼
                 WebOSService ── state machine: connect → hello → register → subscribe
                 │      │      ├─ CapabilityStore (what the TV actually supports)
                 │      │      └─ reconnect / keep-alive / power-off handling
                 ▼      ▼
            SSAPSocket  PointerInputSocket   (URLSessionWebSocketTask)
                 │
     TVTrustDelegate (TLS trust-on-first-use) · TCPProbe · NetworkMonitor · WakeOnLAN
     DiscoveryService (Bonjour + subnet scan) · TVProber (unpaired "hello" test)
     KeychainStore (client keys) · DeviceStore / Preferences (UserDefaults)
```

```
LumaRemote/
  App/            LumaRemoteApp, AppModel (composition root, scene lifecycle)
  Models/         SavedDevice, TVState, RemoteKey, CapabilityStore
  ViewModels/     RemoteViewModel, DevicesViewModel, KeyboardViewModel
  Views/          Remote/ Devices/ Apps/ Inputs/ Settings/ RootView
  Services/
    WebOS/        SSAPSocket, WebOSService, SSAPRegistration, SSAPEndpoint, JSONValue, errors
    Networking/   TVTrustDelegate, TCPProbe, NetworkMonitor, IPv4, WakeOnLAN
    Discovery/    DiscoveryService, TVProber
    Persistence/  KeychainStore, DeviceStore, Preferences
  Components/     Theme, buttons, rockers, status, toast
  Resources/      Assets.xcassets
LumaRemoteTests/  Swift Testing unit tests (protocol parsing, IP math, WoL, endpoint order)
tools/mock_tv.py  Mock webOS TV for Simulator testing
```

## Protocol findings (SSAP)

Cross-checked against Home Assistant's maintained `aiowebostv` and `lgtv2`.

| Topic | Finding | What the app does |
|---|---|---|
| Endpoint | Older firmware: `ws://IP:3000`. Firmware from ~2022–23 on (including updates to 2019 models): only `wss://IP:3001`, with a certificate from LG's private CA (identical on every LG TV). | Tries `wss:3001` then `ws:3000` (TCP probe first for precise errors), remembers what worked. Port/scheme overridable per TV. |
| TLS | System trust can't validate LG's cert. | Trust-on-first-use: pins the cert's SHA-256 per TV and refuses a different one ("Reset certificate trust" after a firmware update). Only the configured TV IP is trusted. |
| Handshake | `hello` → (newer firmware) `system/getSystemInfo` before registering → `register` with `pairingType: PROMPT` and a permission manifest. First reply `{"pairingType":"PROMPT"}`, then `registered` with `client-key`, or `error` if declined. | Exactly this. Prompt waits up to 60 s. An unrecognised stored key causes a new prompt, which the UI explains. |
| Pairing method | The TV's `hello` lists supported `pairingTypes` (e.g. `PIN`, `PROMPT`, `COMBINED`). With `pairingType: PIN` the TV shows a code; the client sends it via `ssap://pairing/setPin` `{"pin": "…"}` and the TV then answers the original register with `registered`. Confirmed in bscpylgtv. | Code pairing by default (per-TV setting). Skipped if `hello` doesn't list `PIN`; falls back to the Accept prompt if the TV refuses it. A wrong code restarts registration so the TV shows a fresh code (3 tries). |
| Manifest | aiowebostv now sends an unsigned manifest; older clients use one signed with LG's test key. | Tries the current manifest; if the TV rejects the *manifest* (not the user), retries with the signed legacy one and remembers which worked. |
| Commands | Request/response JSON over the main socket; errors like `404 no such service or method`, `401 insufficient permissions`. | Confirmed commands (volume, mute, channel, media, inputs, apps, text, power-off) await the reply. A 404 hides that control. |
| Buttons | `getPointerInputSocket` returns a second socket; frames `type:button\nname:HOME\n\n`. **Never acknowledged.** | Navigation, Home, Back, digits, colour keys etc. The UI never claims these "succeeded"; it only reports failures to send. |
| Power on | Not possible over SSAP. Needs Wake-on-LAN with *Mobile TV On › Turn on via Wi-Fi* enabled on the TV (supported on 2019 webOS 4.5 models). | MAC learned from `connectionmanager/getinfo` (or entered manually). See limitations. |
| Discovery | LG's official discovery is SSDP (`urn:lge-com:service:webos-second-screen:1`), which needs Apple's restricted multicast entitlement on iOS. | Not used. Bonjour (`_airplay._tcp`, `_hap._tcp`) plus a /24 subnet scan of ports 3001/3000, each confirmed with `hello`. Manual IP always works. |

## Physical remote (AKB75675304) mapping

Shown in-app under **More › Physical Remote Mapping**. Summary:
- **Confirmed by the TV:** Power off, Volume ±, Mute, Channel ±, Input selection, playback,
  Netflix / Prime Video shortcuts (only if installed), app launching, text input.
- **Sent as button events (unacknowledged):** arrows, OK, Home, Back, Exit, Settings (MENU),
  Info, 0–9, dash, colour keys.
- **Experimental (amber dot, can be hidden):** Guide, List, Quick Settings. They exist on
  the IR remote but aren't documented for the network API.
- **Not available over the network:** Quick Access (long-press a number), power *on* without
  Wake-on-LAN.

## Testing

### Unit tests
`⌘U` in Xcode. Tests cover registration message shape, reply parsing (success / 404 / 401 /
`returnValue:false`), old vs new firmware audio payloads, IPv4 parsing and subnet clamping,
magic packets, and endpoint ordering.

### Mock TV (Simulator)
```bash
pip3 install websockets
```
```bash
python3 tools/mock_tv.py
```
Add a TV with your Mac's IP and Connection = **Plain (ws)**. Scenario flags:

| Scenario | How |
|---|---|
| TV on and reachable | default |
| Pairing rejected | `--pair reject` |
| Pairing never answered | `--pair ignore` |
| Code pairing (code printed in the terminal) | default; `--pin 12345678` for a fixed code |
| TV without code pairing | `--no-pin` |
| Invalid / forgotten registration key | `--forget-keys` |
| Firmware lacks a command | `--unsupported media.controls/play,tv/channelUp` |
| No tuner / no button socket | `--no-tuner` / `--no-pointer` |
| TV restarted | Ctrl-C the script, start it again |
| TV turned off | press Power in the app |
| TV unreachable / invalid IP | stop the script, or enter `192.168.1.999` / an unused IP |
| iPhone off Wi-Fi, app suspended | toggle Wi-Fi in Control Center; background and reopen the app |

### On the real TV (checklist)
1. Test connection shows "LG webOS TV found" and the connection type (wss · 3001 or ws · 3000).
2. Accept the prompt; Device Information shows model 32LM577BPUA and the webOS version.
3. Volume/mute update the VOL number (confirms the subscription works).
4. Arrows/OK/Home move the TV UI (confirms the button socket).
5. Apps tab lists the TV's apps; Inputs lists HDMI1/HDMI2 (+ TV if Live TV exists).
6. Keyboard: open YouTube search on the TV and type.
7. Power off, then Wake TV (after enabling *Turn on via Wi-Fi*).
8. Background the app for a minute, return: it reconnects without a new prompt.

## Limitations, stated plainly

- **Not compiled yet.** This code was written in a Linux environment without Xcode. It was
  reviewed carefully for Swift 6 correctness, and the protocol flow was checked against
  the mock TV, but expect to fix a few compile errors on the first build.
- **Wake-on-LAN on iPhone:** iOS blocks broadcast UDP unless an app has Apple's Multicast
  Networking entitlement (an application to Apple). Without it the app also sends the packet
  straight to the TV's IP, which works while your router still remembers the TV. It may fail
  after the TV has been off for a long time.
- **Button events are unacknowledged** by webOS. The app can confirm a button was sent,
  not that the TV acted on it.
- **Automatic discovery** may still miss your TV if it advertises no Bonjour services and
  sits outside your phone's /24 subnet. Manual IP entry always works. Reserve the TV's IP in
  your router so it doesn't change.

## Privacy & security

- The pairing key lives only in the iOS Keychain (`ThisDeviceOnly`) and is never logged.
  Registration payloads are redacted from logs.
- The TV's own "Accept" prompt is always used. Nothing bypasses it.
- ATS allows plain connections to local-network addresses only (`NSAllowsLocalNetworking`).
- No network traffic leaves your LAN.
