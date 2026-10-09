# Mclash maintained HEV source

Upstream: https://github.com/heiher/hev-socks5-tunnel
Version: 2.17.1
Commit: 9a06bc6e7989da54e3d32ff701ef7a7ce4995d3a

This directory contains the source and bundled dependencies used for the Android JNI build.
Local changes are maintained directly in C source: optional socks5.dns-port routes TCP/UDP port 53 to Mihomo DNS; lwIP UDP sessions distinguish source and destination address/port.
Build this directory directly. No source patching or upstream download is needed.
Upstream licenses are retained with each dependency.
