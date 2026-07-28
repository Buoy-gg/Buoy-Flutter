/// Ports packages/shared/src/dataViewer/DiffSummary.tsx — the +new/−gone/
/// ≈modified counts bar the [SplitDiffViewer] shows above the rows. Renders
/// nothing when there are no changes.
library;

import 'package:flutter/widgets.dart';

import 'diff_themes.dart';

class DiffSummary extends StatelessWidget {
  const DiffSummary({
    super.key,
    required this.added,
    required this.removed,
    required this.modified,
    required this.theme,
  });

  final int added;
  final int removed;
  final int modified;
  final DiffTheme theme;

  @override
  Widget build(BuildContext context) {
    if (added == 0 && removed == 0 && modified == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.summaryBackground,
        border: Border(top: BorderSide(color: theme.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (added > 0)
            _badge('+', added, 'new', theme.addedBackground,
                theme.summaryAddedText),
          if (removed > 0) ...[
            if (added > 0) const SizedBox(width: 12),
            _badge('−', removed, 'gone', theme.removedBackground,
                theme.summaryRemovedText),
          ],
          if (modified > 0) ...[
            if (added > 0 || removed > 0) const SizedBox(width: 12),
            _badge('≈', modified, 'modified', theme.modifiedBackground,
                theme.summaryModifiedText),
          ],
        ],
      ),
    );
  }

  Widget _badge(String icon, int count, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: fg)),
          const SizedBox(width: 3),
          Text('$count',
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: fg)),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: fg)),
        ],
      ),
    );
  }
}
