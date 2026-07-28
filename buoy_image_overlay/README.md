# buoy_image_overlay

Buoy image-overlay tool for Flutter — a 1:1 port of
[`@buoy-gg/image-overlay`](https://buoy.gg). Pin a design mockup on top of your
running app at adjustable opacity for pixel-perfect UI comparison.

Two modes:

- **Free Placement** — load an image and drag / aspect-lock-resize it anywhere,
  with opacity, horizontal/vertical flip, and a position lock.
- **Component Match** — overlay the image onto a widget you've tagged with
  `BuoyImageTarget`, with a dashed highlight, opacity / scale / offset controls,
  and optional Auto Track that re-measures the target as it moves.

Pure UI: no data capture and (matching the RN package) no desktop-sync adapter.

## Usage

```dart
import 'package:buoy_image_overlay/buoy_image_overlay.dart';

// Usually the `buoy` umbrella registers this for you. To register directly:
registerBuoyImageOverlay();

// (Optional) tag widgets so Component Match can find + measure them:
BuoyImageTarget(
  label: 'ProfileCard',
  child: MyProfileCard(),
);
```

Open the Buoy dial → **IMG**, pick a mode, paste or type an image URL, and load.
The overlay renders over your app via `buoy_core`'s `BuoyOverlayHost` and stays
put while you navigate. State lives for the app session (it resets on restart),
matching the RN tool.

## Image sources

- **URL** — `http(s)` image URLs.
- **`data:` URIs** — base64-encoded images.
- **Paste from Clipboard** — pastes an image URL / `data:` URI from the
  clipboard (text). Image-bytes paste is not supported (needs a native
  clipboard plugin), matching the RN tool's optional-dependency behavior.
