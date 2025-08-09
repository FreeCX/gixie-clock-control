Gixie Clock Control
---

Reimplementation of [gixie-bright-control](https://github.com/FreeCX/gixie-bright-control) in [Zig](https://ziglang.org/).

## How to use
- create `config.json`
```jsonc
{
  // gixie clock websocket server
  "clock": {
    "host": "127.0.0.1",
    "port": 81
  },
  // to calculate of sunrise and sunset
  "position": {
    "latitude": 59.33258,
    "longitude": 18.06490,
    "elevation": 0,
    "timezone": 0
  },
  "control": {
    // nighttime brightness
    "min": 10,
    // daytime brightness
    "max": 250,
    // smooth transition step
    "step": 10
  }
}
```

- calculate sunrise and sunset
```bash
$ zig build run -- suninfo
```

- get/set gixie clock brightness
```bash
$ zig build run -- get
$ zig build run -- set 250
```

## Build for ARM
```bash
$ zig build -Darm=true -Doptimize=ReleaseSmall
# optional
$ upx -9 zig-out/bin/control
```

## How to get clock websocket command
- install [Gixie Clock](https://play.google.com/store/apps/details?id=uni.UNICB90ED7) app
- install [Wireshark](https://www.wireshark.org/)
- configure router for [Packet Sniffer](https://wiki.mikrotik.com/wiki/Manual:Tools/Packet_Sniffer)
- run and sniff
