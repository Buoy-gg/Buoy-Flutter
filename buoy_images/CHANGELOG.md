## 0.3.0

- Initial release of the Buoy Images tool for Flutter: a live registry of every
  image loaded through `BuoyImage` — cache verdict (memory/disk/network), load
  timing, decoded-vs-displayed oversize audit, estimated decoded/wasted memory,
  and a failure log — with per-image reload/retry, simulation overrides, and
  live streaming to Buoy Desktop + the MCP server (`get_images`, `image_action`,
  `set_image_simulation`).
