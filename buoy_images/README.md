# buoy_images

Image debugger for Flutter — part of the [Buoy](https://buoy.gg) devtools suite.

A live registry of every image the app loads through `BuoyImage`: cache verdict
(memory / disk / network), load timing, decoded-vs-displayed **oversize audit**
(are you decoding a 4K bitmap into a 120pt thumbnail?), estimated decoded /
wasted memory, and a failure log with the HTTP status where available. Per-image
**hard reload / retry** and **simulation overrides** (force error / loading /
blank / URL swap, plus app-wide offline / cold-start / blank-images modes) let
you reproduce image bugs on device. Streams live to Buoy Desktop and the MCP
server (`get_images`, `image_action`, `set_image_simulation`).

Image HTTP traffic in Flutter is fetched by `dart:io` image loaders and never
surfaces the layout size or cache origin the network inspector needs — this tool
is the visibility layer for images.

## Why a widget wrapper?

Flutter has no app-wide `Image` decorator hook (unlike React Native's
`unstable_setImageComponentDecorator`). Capture is therefore opt-in at the
widget level: use `BuoyImage` in place of `Image` / `CachedNetworkImage`. It
wraps your `ImageProvider`, measures the rendered box for the oversize audit,
and owns the props so reload/retry and simulations work.

```dart
BuoyImage(
  provider: CachedNetworkImageProvider(url), // or NetworkImage(url), AssetImage(...)
  width: 140,
  height: 140,
  fit: BoxFit.contain,
  placeholder: (context) => const CircularProgressIndicator(),
  errorWidget: (context, error) => const Icon(Icons.broken_image),
)
```

Registration is automatic when you mount the `BuoyDevTools` umbrella widget;
call `registerBuoyImages()` once before `runApp` to wire it standalone.

Debug builds only — release builds render the child untouched.
