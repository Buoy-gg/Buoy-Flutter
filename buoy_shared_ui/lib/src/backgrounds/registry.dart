/// Ports packages/shared/src/ui/backgrounds/registry.tsx — the catalogue.
/// Adding a preset means adding one entry here — the switcher, the persisted
/// selection and every tool surface read from this list.
///
/// `nodes` / `views` are RN's honest cost figures (native animated nodes and
/// static views mounted); kept so the switcher can show them and so the two
/// catalogues read the same. A Flutter preset is one painter regardless.
library;

import 'package:flutter/widgets.dart' show BuildContext, Widget;

import 'types.dart';
import 'variants/hyperspace.dart';
import 'variants/underwater.dart';

class BackgroundPreset {
  const BackgroundPreset({
    required this.id,
    required this.label,
    required this.blurb,
    required this.nodes,
    required this.views,
    this.counterpart,
    this.builder,
  });

  final BackgroundId id;
  final String label;

  /// One line, shown under the name in the switcher.
  final String blurb;
  final int nodes;
  final int views;

  /// A paired look (night ⇄ day) the switcher offers as a one-tap toggle.
  final ({BackgroundId id, String label})? counterpart;

  /// Null = paints nothing (the "Off" preset).
  final BackgroundVariantBuilder? builder;
}

/// The presets this build can RENDER. Deep Field and Live Sky exist in the RN
/// catalogue (and in [BackgroundId], so a persisted pick round-trips) but have
/// no Flutter renderer yet — `getPreset` maps them to Off.
const List<BackgroundPreset> backgroundPresets = [
  BackgroundPreset(
    id: BackgroundId.off,
    label: 'Off',
    blurb: 'Plain black — no backdrop at all',
    nodes: 0,
    views: 1,
  ),
  BackgroundPreset(
    id: BackgroundId.hyperspace,
    label: 'Hyperspace',
    blurb: 'Lightspeed — crisp points streaming from a centre vanishing point',
    nodes: 1,
    views: 570,
    builder: _hyperspace,
  ),
  BackgroundPreset(
    id: BackgroundId.abyss,
    label: 'Abyss',
    blurb: 'A surface light fanning into the deep',
    nodes: 4,
    views: 230,
    builder: _abyss,
  ),
  BackgroundPreset(
    id: BackgroundId.bubbles,
    label: 'Bubbles',
    blurb: 'Bubbles wobbling up through the light',
    nodes: 4,
    views: 180,
    builder: _bubbles,
  ),
  BackgroundPreset(
    id: BackgroundId.jellyfish,
    label: 'Jellyfish',
    blurb: 'A bloom of glowing jellies, big and small, pulsing past',
    nodes: 15,
    views: 250,
    builder: _jellyfish,
  ),
];

Widget _hyperspace(BuildContext _, double w, double h, bool a) =>
    Hyperspace(width: w, height: h, animated: a);
Widget _abyss(BuildContext _, double w, double h, bool a) =>
    Abyss(width: w, height: h, animated: a);
Widget _bubbles(BuildContext _, double w, double h, bool a) =>
    Bubbles(width: w, height: h, animated: a);
Widget _jellyfish(BuildContext _, double w, double h, bool a) =>
    Jellyfish(width: w, height: h, animated: a);

/// RN `DEFAULT_BACKGROUND`: backgrounds are opt-in.
const BackgroundId defaultBackground = BackgroundId.off;

/// Index into [backgroundPresets]; an id this build can't render reads as 0.
int presetIndex(BackgroundId id) {
  final i = backgroundPresets.indexWhere((p) => p.id == id);
  return i < 0 ? 0 : i;
}

/// Wraps at both ends.
BackgroundPreset presetAt(int index) {
  final n = backgroundPresets.length;
  return backgroundPresets[((index % n) + n) % n];
}

BackgroundPreset getPreset(BackgroundId id) => backgroundPresets[presetIndex(id)];
