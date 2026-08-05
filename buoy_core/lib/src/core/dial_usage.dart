/// Dial usage — recency-weighted usage tracking for the dial menu, ported
/// from @buoy-gg/floating-tools-core `dialUsage.ts`. Pure scoring/ranking
/// logic; no Flutter or platform code.
///
/// The dial menu ranks tools by how recently and frequently they are used.
/// Each press adds 1 point to a tool's score; that score decays exponentially
/// over time (half-life ~3 days) so the ordering reflects "what I'm using
/// most lately" rather than all-time totals.
library;

import 'dart:math' as math;

/// Half-life of a usage score, in milliseconds (~3 days). After this much
/// time, an untouched tool's score halves.
const int usageHalfLifeMs = 3 * 24 * 60 * 60 * 1000;

/// Scores at or below this value are treated as zero. Entries that decay
/// below it can be safely pruned from storage.
const double usageMinScore = 0.01;

/// A single tool's usage record. Serializes to the same JSON shape the RN
/// package persists (`{score, lastUsed}`), so state survives a framework
/// switch on a shared backend.
class UsageEntry {
  const UsageEntry({required this.score, required this.lastUsed});

  /// Decayed usage score as of [lastUsed].
  final double score;

  /// Epoch ms timestamp of the most recent press.
  final int lastUsed;

  Map<String, Object?> toJson() => {'score': score, 'lastUsed': lastUsed};

  static UsageEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final score = json['score'];
    final lastUsed = json['lastUsed'];
    if (score is! num || lastUsed is! num) return null;
    return UsageEntry(score: score.toDouble(), lastUsed: lastUsed.toInt());
  }
}

/// Decay a stored score forward to [now] (epoch ms). Never negative; a
/// clock-skewed future [lastUsed] returns the score unboosted.
double decayScore(UsageEntry? entry, int now) {
  if (entry == null || entry.score <= 0) return 0;
  final elapsed = now - entry.lastUsed;
  if (elapsed <= 0) return entry.score;
  return entry.score * math.pow(0.5, elapsed / usageHalfLifeMs);
}

/// Record a single press of [id], returning a new usage map. The existing
/// score is decayed forward to [now] before adding 1, so a burst of presses
/// accumulates while stale scores naturally fade.
Map<String, UsageEntry> recordUsage(
  Map<String, UsageEntry> map,
  String id,
  int now,
) {
  final decayed = decayScore(map[id], now);
  return {...map, id: UsageEntry(score: decayed + 1, lastUsed: now)};
}

/// Rank tool ids by decayed usage score, highest first. The sort is stable:
/// tools with equal scores (including never-used tools, which score 0) keep
/// their original order in [orderedIds].
List<String> rankToolIds(
  List<String> orderedIds,
  Map<String, UsageEntry> map,
  int now,
) {
  final scored = [
    for (var i = 0; i < orderedIds.length; i++)
      (id: orderedIds[i], index: i, score: decayScore(map[orderedIds[i]], now)),
  ];
  scored.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    return a.index.compareTo(b.index);
  });
  return [for (final entry in scored) entry.id];
}

/// Drop entries whose decayed score has fallen below [usageMinScore],
/// keeping the persisted map from growing unbounded.
Map<String, UsageEntry> pruneUsage(Map<String, UsageEntry> map, int now) {
  return {
    for (final entry in map.entries)
      if (decayScore(entry.value, now) > usageMinScore) entry.key: entry.value,
  };
}
