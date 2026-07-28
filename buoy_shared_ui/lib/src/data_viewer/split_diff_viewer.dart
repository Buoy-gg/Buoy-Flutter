/// Ports packages/shared/src/dataViewer/SplitDiffViewer.tsx — the side-by-side
/// PREV | CUR line diff with word-level highlighting. Dumb component: computes
/// [computeLineDiff] and renders both columns in one scroll view.
///
/// RN numerics preserved: fixed height 400, gutter 35 / marker 20, content
/// font 10 monospace lineHeight 16, header PREV/CUR 10/700 uppercase.
library;

import 'package:flutter/material.dart';

import 'diff_summary.dart';
import 'diff_themes.dart';
import 'line_diff.dart';

/// RN `SplitDiffViewerOptions`.
class SplitDiffViewerOptions {
  const SplitDiffViewerOptions({
    this.hideLineNumbers = false,
    this.disableWordDiff = false,
    this.showDiffOnly = false,
    this.compareMethod = DiffCompareMethod.words,
    this.contextLines = 3,
  });

  final bool hideLineNumbers;
  final bool disableWordDiff;
  final bool showDiffOnly;
  final DiffCompareMethod compareMethod;
  final int contextLines;
}

class SplitDiffViewer extends StatelessWidget {
  const SplitDiffViewer({
    super.key,
    required this.oldValue,
    required this.newValue,
    this.theme = devToolsDefaultTheme,
    this.options = const SplitDiffViewerOptions(),
    this.showThemeName = false,
    this.height = 400,
  });

  final Object? oldValue;
  final Object? newValue;
  final DiffTheme theme;
  final SplitDiffViewerOptions options;
  final bool showThemeName;
  final double height;

  @override
  Widget build(BuildContext context) {
    final lineDiffs = computeLineDiff(
      oldValue,
      newValue,
      DiffComputeOptions(
        compareMethod: options.compareMethod,
        disableWordDiff: options.disableWordDiff,
        showDiffOnly: options.showDiffOnly,
        contextLines: options.contextLines,
      ),
    );

    final added = lineDiffs.where((d) => d.type == DiffType.added).length;
    final removed = lineDiffs.where((d) => d.type == DiffType.removed).length;
    final modified = lineDiffs.where((d) => d.type == DiffType.modified).length;

    return Container(
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderColor),
      ),
      child: Column(
        children: [
          if (showThemeName)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.panelBackground,
                border: Border(bottom: BorderSide(color: theme.borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(theme.name,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.accentColor ?? theme.unchangedText,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(theme.description,
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.unchangedText.withValues(alpha: 0.8),
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          // Header (PREV | CUR).
          Container(
            decoration: BoxDecoration(
              color: theme.headerBackground,
              border: Border(bottom: BorderSide(color: theme.borderColor)),
            ),
            child: Row(
              children: [
                Expanded(child: _headerCell('PREV')),
                Container(width: 1, height: 30, color: theme.dividerColor),
                Expanded(child: _headerCell('CUR')),
              ],
            ),
          ),
          DiffSummary(
            added: added,
            removed: removed,
            modified: modified,
            theme: theme,
          ),
          Expanded(
            child: lineDiffs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text(
                        options.showDiffOnly
                            ? 'No differences found'
                            : 'No content to display',
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.emptyStateText,
                            fontStyle: FontStyle.italic,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var idx = 0; idx < lineDiffs.length; idx++)
                          _row(lineDiffs[idx], idx, lineDiffs),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: theme.accentColor ?? theme.unchangedText,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
      );

  bool _showSeparator(int idx, List<LineDiffInfo> diffs) {
    if (!options.showDiffOnly || idx == 0) return false;
    final prev = diffs[idx - 1];
    final curr = diffs[idx];
    final leftGap = curr.leftLineNumber != null &&
        prev.leftLineNumber != null &&
        curr.leftLineNumber! - prev.leftLineNumber! > 1;
    final rightGap = curr.rightLineNumber != null &&
        prev.rightLineNumber != null &&
        curr.rightLineNumber! - prev.rightLineNumber! > 1;
    return leftGap || rightGap;
  }

  Widget _row(LineDiffInfo diff, int idx, List<LineDiffInfo> diffs) {
    final isRemoved = diff.type == DiffType.removed;
    final isAdded = diff.type == DiffType.added;
    final isModified = diff.type == DiffType.modified;
    final isDefault = diff.type == DiffType.unchanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showSeparator(idx, diffs))
          Container(
            height: 20,
            width: double.infinity,
            alignment: Alignment.center,
            color: theme.separatorBackground,
            child: Text('• • •',
                style: TextStyle(
                    fontSize: 8,
                    color: theme.separatorText,
                    fontFamily: 'monospace',
                    letterSpacing: 2)),
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: (isRemoved || isModified || isDefault)
                      ? _lineSide(
                          diff.leftLineNumber,
                          diff.leftContent,
                          isModified ? DiffType.removed : diff.type,
                          isRemoved || isModified ? '-' : ' ',
                        )
                      : _lineSide(null, null, DiffType.unchanged, ' ',
                          empty: true),
                ),
              ),
              Container(width: 1, color: theme.dividerColor),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: (isAdded || isModified || isDefault)
                      ? _lineSide(
                          diff.rightLineNumber,
                          diff.rightContent,
                          isModified ? DiffType.added : diff.type,
                          isAdded || isModified ? '+' : ' ',
                        )
                      : _lineSide(null, null, DiffType.unchanged, ' ',
                          empty: true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ({Color background, Color text, Color markerBg}) _diffColors(DiffType type) {
    switch (type) {
      case DiffType.added:
        return (
          background: theme.addedBackground,
          text: theme.addedText,
          markerBg: theme.markerAddedBackground,
        );
      case DiffType.removed:
        return (
          background: theme.removedBackground,
          text: theme.removedText,
          markerBg: theme.markerRemovedBackground,
        );
      default:
        return (
          background: theme.unchangedBackground,
          text: theme.unchangedText,
          markerBg: const Color(0x00000000),
        );
    }
  }

  List<Widget> _lineSide(
    int? lineNumber,
    Object? content,
    DiffType type,
    String marker, {
    bool empty = false,
  }) {
    if (empty) {
      return [
        if (!options.hideLineNumbers)
          Container(
            width: 35,
            color: theme.contextBackground,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: const Text(' ', style: TextStyle(fontSize: 9)),
          ),
        Container(width: 20, color: theme.contextBackground),
        Expanded(child: Container(color: theme.contextBackground)),
      ];
    }

    final colors = _diffColors(type);
    return [
      if (!options.hideLineNumbers)
        Container(
          width: 35,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: theme.lineNumberBackground,
            border:
                Border(right: BorderSide(color: theme.lineNumberBorder)),
          ),
          child: Text(
            lineNumber != null ? '$lineNumber' : ' ',
            style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: theme.lineNumberText),
          ),
        ),
      Container(
        width: 20,
        color: colors.markerBg,
        alignment: Alignment.center,
        child: Text(marker,
            style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: theme.markerText)),
      ),
      Expanded(
        child: Container(
          color: colors.background,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: content is List<WordDiff>
              ? Text.rich(
                  TextSpan(children: _wordSpans(content)),
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 16 / 10,
                      color: colors.text),
                )
              : Text(
                  (content as String?)?.isNotEmpty == true
                      ? content as String
                      : ' ',
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 16 / 10,
                      color: colors.text),
                ),
        ),
      ),
    ];
  }

  List<InlineSpan> _wordSpans(List<WordDiff> words) {
    return [
      for (final word in words)
        TextSpan(
          text: word.value,
          style: TextStyle(
            backgroundColor: switch (word.type) {
              DiffType.added => theme.addedWordHighlight,
              DiffType.removed => theme.removedWordHighlight,
              _ => const Color(0x00000000),
            },
          ),
        ),
    ];
  }
}
