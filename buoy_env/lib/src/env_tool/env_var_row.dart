/// Ports packages/env-tools/src/env/components/EnvVarRow.tsx — one env var as an
/// expandable [CompactRow]: status dot/label/sublabel, the key formatted as
/// `section › subsection`, an optional expected-type [TypeBadge], and an
/// expanded body with Value / (wrong-type) Type+Expected badges / (wrong-value)
/// Expected / (description) Info.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../env_types.dart';
import '../env_validation.dart';

/// (label, color, sublabel) per status — EnvVarRow.getStatusConfig.
({String label, Color color, String sublabel}) _statusConfig(
    EnvVarStatus status) {
  switch (status) {
    case EnvVarStatus.requiredPresent:
      return (label: 'Valid', color: BuoyColors.success, sublabel: 'Required');
    case EnvVarStatus.requiredMissing:
      return (label: 'Missing', color: BuoyColors.error, sublabel: 'Required');
    case EnvVarStatus.requiredWrongValue:
      return (
        label: 'Wrong',
        color: BuoyColors.warning,
        sublabel: 'Invalid value'
      );
    case EnvVarStatus.requiredWrongType:
      return (
        label: 'Type Error',
        color: BuoyColors.info,
        sublabel: 'Wrong type'
      );
    case EnvVarStatus.optionalPresent:
      return (
        label: 'Set',
        color: BuoyColors.textSecondary,
        sublabel: 'Optional'
      );
  }
}

/// EnvVarRow.formatValue — null/absent → "undefined".
String _formatValue(String? value) => value ?? 'undefined';

class EnvVarRow extends StatelessWidget {
  const EnvVarRow({
    super.key,
    required this.envVar,
    this.isExpanded = false,
    this.onPress,
  });

  final EnvVarInfo envVar;
  final bool isExpanded;
  final ValueChanged<EnvVarInfo>? onPress;

  @override
  Widget build(BuildContext context) {
    final config = _statusConfig(envVar.status);
    // primaryText like React Query: "section › subsection", lowercased parts.
    final primaryText =
        envVar.key.split('_').map((p) => p.toLowerCase()).join(' › ');

    return CompactRow(
      statusDotColor: config.color,
      statusLabel: config.label,
      statusSublabel: config.sublabel,
      primaryText: primaryText,
      expandedContent: _expandedContent(),
      isExpanded: isExpanded,
      expandedGlowColor: config.color,
      customBadge: envVar.expectedType != null
          ? TypeBadge(type: envVar.expectedType!.wire)
          : null,
      showChevron: true,
      onPress: onPress != null ? () => onPress!(envVar) : null,
    );
  }

  Widget _expandedContent() {
    final rows = <Widget>[
      _row(
        'Value:',
        Text(
          _formatValue(envVar.value),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: BuoyColors.textSecondary,
            fontFamily: 'monospace',
          ),
        ),
      ),
    ];

    if (envVar.status == EnvVarStatus.requiredWrongType &&
        envVar.expectedType != null) {
      rows.add(_row(
        'Type:',
        TypeBadge(type: getEnvVarType(envVar.value).wire),
      ));
      rows.add(_row('Expected:', TypeBadge(type: envVar.expectedType!.wire)));
    }

    if (envVar.status == EnvVarStatus.requiredWrongValue &&
        envVar.expectedValue != null) {
      rows.add(_row(
        'Expected:',
        Text(
          envVar.expectedValue!,
          style: const TextStyle(
            fontSize: 11,
            color: BuoyColors.warning,
            fontFamily: 'monospace',
          ),
        ),
      ));
    }

    if (envVar.description != null) {
      rows.add(_row(
        'Info:',
        Text(
          envVar.description!,
          style: const TextStyle(
            fontSize: 11,
            color: BuoyColors.textSecondary,
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          rows[i],
        ],
      ],
    );
  }

  /// expandedRow: label (10/w600/muted/minWidth 60) + value, gap 8.
  Widget _row(String label, Widget value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: BuoyColors.textMuted,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: value)),
      ],
    );
  }
}
