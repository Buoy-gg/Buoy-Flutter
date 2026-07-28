/// Ports packages/env-tools/src/env/components/EnvVarSection.tsx — a list of
/// [EnvVarRow]s owning single-row expand state (tap toggles; tapping another
/// collapses the first). The modal renders it with an empty title (the section
/// header is drawn by the modal), so the RN "Required Variables" empty branch is
/// not reachable here — only the plain list path is ported.
library;

import 'package:flutter/material.dart';

import '../env_types.dart';
import 'env_var_row.dart';

class EnvVarSection extends StatefulWidget {
  const EnvVarSection({super.key, required this.vars});

  final List<EnvVarInfo> vars;

  @override
  State<EnvVarSection> createState() => _EnvVarSectionState();
}

class _EnvVarSectionState extends State<EnvVarSection> {
  String? _expandedKey;

  @override
  Widget build(BuildContext context) {
    if (widget.vars.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final v in widget.vars)
          EnvVarRow(
            key: ValueKey(v.key),
            envVar: v,
            isExpanded: _expandedKey == v.key,
            onPress: (envVar) => setState(() {
              _expandedKey = _expandedKey == envVar.key ? null : envVar.key;
            }),
          ),
      ],
    );
  }
}
