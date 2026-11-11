#!/usr/bin/env python3
"""
Mock LG webOS TV (SSAP) for testing Luma Remote in the iOS Simulator.

    pip install websockets
    python3 tools/mock_tv.py                       # ws://<your-mac-ip>:3000, accept pairing after 2 s
    python3 tools/mock_tv.py --pair reject         # user presses "Decline"
    python3 tools/mock_tv.py --pair ignore         # prompt never answered (pairing timeout)
    python3 tools/mock_tv.py --unsupported media.controls/play,tv/channelUp
    python3 tools/mock_tv.py --no-tuner --no-pointer
    python3 tools/mock_tv.py --forget-keys         # simulates a factory reset: stored key rejected
    python3 tools/mock_tv.py --no-pin              # TV that only offers the Accept prompt

Code pairing: when the app asks for PIN pairing, the "TV" prints a code here; type it
in the app. A wrong code ends that pairing attempt (the app then requests a new code).

In Luma Remote: Add TV › Enter IP address › your Mac's IP, Connection: Plain (ws).
Stop the script (Ctrl-C) and restart it to simulate the TV restarting.

This mirrors the message shapes of real webOS firmware closely enough to exercise the
app's state machine; it is not a full emulation.
"""
import argparse
import asyncio
import json
import secrets
import socket

import websockets

STATE = {
    "volume": 12,
    "mute": False,
    "foreground": "com.webos.app.livetv",
    "channel": {"channelNumber": "7-1", "channelName": "KABC"},
    "keys": set(),
}
LAUNCH_POINTS = [
    {"id": "com.webos.app.livetv", "title": "Live TV"},
    {"id": "youtube.leanback.v4", "title": "YouTube"},
    {"id": "netflix", "title": "Netflix"},
    {"id": "amazon", "title": "Prime Video"},
    {"id": "com.webos.app.browser", "title": "Web Browser"},
]
INPUTS = [
    {"id": "HDMI_1", "label": "HDMI1", "port": 1, "appId": "com.webos.app.hdmi1", "connected": True},
    {"id": "HDMI_2", "label": "HDMI2", "port": 2, "appId": "com.webos.app.hdmi2", "connected": False},
]
SUBSCRIBERS = {}  # uri -> list of (ws, id)


def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def payload_for(uri):
    if uri == "audio/getStatus":
        return {"returnValue": True, "mute": STATE["mute"], "volume": STATE["volume"], "scenario": "mastervolume_tv_speaker"}
    if uri == "com.webos.applicationManager/getForegroundAppInfo":
        return {"returnValue": True, "appId": STATE["foreground"]}
    if uri == "com.webos.service.tvpower/power/getPowerState":
        return {"returnValue": True, "state": "Active"}
    if uri == "com.webos.applicationManager/listLaunchPoints":
        return {"returnValue": True, "launchPoints": LAUNCH_POINTS}
    if uri == "tv/getExternalInputList":
        return {"returnValue": True, "devices": INPUTS}
    if uri == "tv/getCurrentChannel":
        return {"returnValue": True, **STATE["channel"]}
    if uri == "com.webos.service.ime/registerRemoteKeyboard":
        return {"returnValue": True, "currentWidget": {"focus": False}}
    return None


async def push(uri):
    for ws, sid in list(SUBSCRIBERS.get(uri, [])):
        try:
            await ws.send(json.dumps({"type": "response", "id": sid, "payload": payload_for(uri)}))
        except websockets.ConnectionClosed:
            SUBSCRIBERS[uri].remove((ws, sid))


async def handle_main(ws, args, host, port):
    registered = False
    pending_pin = None  # (register message id, code) while a code is "on screen"
    async for raw in ws:
        msg = json.loads(raw)
        mtype, mid = msg.get("type"), msg.get("id")
        uri = (msg.get("uri") or "").replace("ssap://", "")
        reply = lambda payload, t="response": ws.send(json.dumps({"type": t, "id": mid, "payload": payload}))

        if mtype == "hello":
            await ws.send(json.dumps({"type": "hello", "id": mid, "payload": {
                "deviceType": "tv", "deviceOS": "webOS", "deviceOSVersion": "4.1.0",
                "deviceOSReleaseVersion": "4.5.0", "deviceUUID": "mock-0001",
                "pairingTypes": ["PROMPT"] if args.no_pin else ["PIN", "PROMPT", "COMBINED"]}}))
            continue

        if mtype == "register":
            key = msg["payload"].get("client-key")
            if key and key in STATE["keys"] and not args.forget_keys:
                registered = True
                print("✓ registered with stored key (no prompt)")
                await ws.send(json.dumps({"type": "registered", "id": mid, "payload": {"client-key": key}}))
                continue
            if msg["payload"].get("pairingType") == "PIN":
                if args.no_pin:
                    print("✗ PIN pairing requested but not supported")
                    await ws.send(json.dumps({"type": "error", "id": mid, "error": "400 unsupported pairing type", "payload": {}}))
                    continue
                code = args.pin or "".join(secrets.choice("0123456789") for _ in range(8))
                pending_pin = (mid, code)
                print(f"🔢 TV shows pairing code: {code}")
                await reply({"pairingType": "PIN", "returnValue": True})
                continue
            print("… showing pairing prompt on TV (mode: %s)" % args.pair)
            await reply({"pairingType": "PROMPT", "returnValue": True})
            await asyncio.sleep(args.pair_delay)
            if args.pair == "accept":
                key = secrets.token_hex(16)
                STATE["keys"].add(key)
                registered = True
                print("✓ user accepted; issued new client-key")
                await ws.send(json.dumps({"type": "registered", "id": mid, "payload": {"client-key": key}}))
            elif args.pair == "reject":
                print("✗ user declined")
                await ws.send(json.dumps({"type": "error", "id": mid, "error": "403 User denied access", "payload": {}}))
            continue

        if uri == "pairing/setPin":
            entered = str((msg.get("payload") or {}).get("pin", ""))
            if not pending_pin:
                await ws.send(json.dumps({"type": "error", "id": mid, "error": "500 no pairing in progress", "payload": {}}))
            elif entered == pending_pin[1]:
                reg_id = pending_pin[0]
                pending_pin = None
                key = secrets.token_hex(16)
                STATE["keys"].add(key)
                registered = True
                print("✓ correct code; issued new client-key")
                await reply({"returnValue": True})
                await ws.send(json.dumps({"type": "registered", "id": reg_id, "payload": {"client-key": key}}))
            else:
                print(f"✗ wrong code entered: {entered}")
                pending_pin = None
                await ws.send(json.dumps({"type": "error", "id": mid, "error": "500 Application error: invalid PIN", "payload": {}}))
            continue

        if not registered:
            if uri == "system/getSystemInfo":
                await reply({"returnValue": True, "modelName": "32LM577BPUA", "receiverType": "atsc"})
            else:
                await ws.send(json.dumps({"type": "error", "id": mid, "error": "401 insufficient permissions", "payload": {}}))
            continue

        if uri in args.unsupported or (args.no_tuner and uri.startswith("tv/c")) or (args.no_pointer and "networkinput" in uri):
            print("✗ unsupported:", uri)
            await ws.send(json.dumps({"type": "error", "id": mid, "error": "404 no such service or method", "payload": {}}))
            continue

        if mtype == "subscribe":
            data = payload_for(uri)
            if data is None:
                await ws.send(json.dumps({"type": "error", "id": mid, "error": "404 no such service or method", "payload": {}}))
            else:
                SUBSCRIBERS.setdefault(uri, []).append((ws, mid))
                await reply({**data, "subscribed": True})
            continue

        print("→", uri, msg.get("payload") or "")
        if uri == "api/getServiceList":
            await reply({"returnValue": True, "services": [{"name": n, "version": 1} for n in
                         ["api", "audio", "media.controls", "system", "system.launcher", "tv", "webapp"]]})
        elif uri == "system/getSystemInfo":
            await reply({"returnValue": True, "modelName": "32LM577BPUA", "receiverType": "atsc"})
        elif uri == "com.webos.service.update/getCurrentSWInformation":
            await reply({"returnValue": True, "product_name": "webOSTV 4.5", "model_name": "HE_DTV_W19K_AFADATAA",
                         "major_ver": "05", "minor_ver": "40.25", "country": "US"})
        elif uri == "com.webos.service.connectionmanager/getinfo":
            await reply({"returnValue": True, "wifiInfo": {"macAddress": "a8:23:fe:00:00:01"},
                         "wiredInfo": {"macAddress": "a8:23:fe:00:00:02"}})
        elif uri == "com.webos.service.networkinput/getPointerInputSocket":
            await reply({"returnValue": True, "socketPath": f"ws://{host}:{port}/resources/{secrets.token_hex(8)}/netinput.pointer.sock"})
        elif uri in ("audio/volumeUp", "audio/volumeDown"):
            STATE["volume"] = max(0, min(100, STATE["volume"] + (1 if uri.endswith("Up") else -1)))
            await reply({"returnValue": True})
            await push("audio/getStatus")
        elif uri == "audio/setMute":
            STATE["mute"] = bool(msg["payload"].get("mute"))
            await reply({"returnValue": True})
            await push("audio/getStatus")
        elif uri in ("tv/channelUp", "tv/channelDown"):
            await reply({"returnValue": True})
        elif uri == "system.launcher/launch":
            STATE["foreground"] = msg["payload"]["id"]
            await reply({"returnValue": True, "id": STATE["foreground"]})
            await push("com.webos.applicationManager/getForegroundAppInfo")
        elif uri == "tv/switchInput":
            match = [i for i in INPUTS if i["id"] == msg["payload"]["inputId"]]
            if match:
                STATE["foreground"] = match[0]["appId"]
                await reply({"returnValue": True})
                await push("com.webos.applicationManager/getForegroundAppInfo")
            else:
                await reply({"returnValue": False, "errorText": "invalid input"})
        elif uri.startswith("media.controls/") or uri.startswith("com.webos.service.ime/"):
            await reply({"returnValue": True})
        elif uri == "system/turnOff":
            print("⏻ TV turning off")
            await reply({"returnValue": True})
            await ws.close()
            return
        else:
            await ws.send(json.dumps({"type": "error", "id": mid, "error": "404 no such service or method", "payload": {}}))


async def handle_pointer(ws):
    async for raw in ws:
        fields = dict(line.split(":", 1) for line in raw.strip().splitlines() if ":" in line)
        print("🔘 button", fields.get("name"))


async def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", type=int, default=3000)
    p.add_argument("--pair", choices=["accept", "reject", "ignore"], default="accept")
    p.add_argument("--pair-delay", type=float, default=2.0)
    p.add_argument("--unsupported", default="", help="comma-separated SSAP URIs to answer with 404")
    p.add_argument("--no-tuner", action="store_true")
    p.add_argument("--no-pointer", action="store_true")
    p.add_argument("--forget-keys", action="store_true")
    p.add_argument("--no-pin", action="store_true", help="TV doesn't offer code pairing")
    p.add_argument("--pin", default="", help="fixed pairing code instead of a random one")
    args = p.parse_args()
    args.unsupported = {u.strip().replace("ssap://", "") for u in args.unsupported.split(",") if u.strip()}
    host = local_ip()

    async def router(ws):
        path = ws.request.path
        try:
            if "netinput.pointer.sock" in path:
                await handle_pointer(ws)
            else:
                await handle_main(ws, args, host, args.port)
        except websockets.ConnectionClosed:
            pass

    async with websockets.serve(router, "0.0.0.0", args.port, max_size=16 * 1024 * 1024):
        print(f"Mock LG webOS TV listening on ws://{host}:{args.port}  (pairing: {args.pair})")
        await asyncio.Future()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
