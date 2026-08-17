## 0.3.1

- `data:` URIs are summarized rather than sent whole — a base64 image can be
  megabytes, and 100 records ride on every snapshot. Long URIs are truncated,
  error strings are capped, and the insight lists get the same treatment.

## 0.3.0

- Initial release of the Buoy Images tool for Flutter: a live registry of every
  image loaded through `BuoyImage` — cache verdict (memory/disk/network), load
  timing, decoded-vs-displayed oversize audit, estimated decoded/wasted memory,
  and a failure log — with per-image reload/retry, simulation overrides, and
  live streaming to Buoy Desktop + the MCP server (`get_images`, `image_action`,
  `set_image_simulation`).
