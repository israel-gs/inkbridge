# InkBridge

InkBridge turns an Android device with a stylus (S Pen or any compatible input) into a wireless drawing tablet for macOS: the Android client captures raw stylus events (position, pressure, tilt, buttons) and streams them over Wi-Fi (UDP) or USB via `adb reverse` (TCP) to the macOS server, which injects them as native tablet events using `CGEventPost` so that pressure-sensitive drawing apps — Photoshop, Procreate for Mac, Krita — receive real brush modulation without any additional driver.

For architecture decisions, wire-protocol specification, and SDD artifacts, see [`openspec/`](openspec/).
