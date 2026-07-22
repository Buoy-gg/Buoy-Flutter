import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';

/// Ports of shared-ui's FilterComponents.tsx pieces used by the network
/// filter view: AddFilterButton (dashed), AddFilterInput, FilterList rows.

class AddFilterButton extends StatelessWidget {
  const AddFilterButton({
    super.key,
    required this.onPress,
    this.color = BuoyColors.primary,
    this.label = 'Add Filter',
  });

  final VoidCallback onPress;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: BuoyColors.input,
          borderRadius: BorderRadius.circular(10),
          // RN uses a dashed border; Flutter Border has no dash — solid at
          // the same 40-alpha reads near-identically at 1px.
          border: Border.all(color: color.hexAlpha(0x40)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(Icons.add, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddFilterInput extends StatefulWidget {
  const AddFilterInput({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.placeholder = 'Add filter...',
    this.color = BuoyColors.primary,
  });

  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final String placeholder;
  final Color color;

  @override
  State<AddFilterInput> createState() => _AddFilterInputState();
}

class _AddFilterInputState extends State<AddFilterInput> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Controller listener, not onChanged — the hardware-keyboard input path
    // can update the editing value without the user-edit callback.
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BuoyColors.input,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.hexAlpha(0x40)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 13, color: BuoyColors.text),
              cursorColor: color,
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: color.hexAlpha(0x40),
                ),
              ),
            ),
          ),
          if (_controller.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TouchableOpacity(
                activeOpacity: 0.2,
                onTap: _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.hexAlpha(0x15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.hexAlpha(0x40)),
                  ),
                  child: Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TouchableOpacity(
              activeOpacity: 0.2,
              onTap: widget.onCancel,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: BuoyColors.hover,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: color.hexAlpha(0x60),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// FilterList — the active-pattern rows (monospace value, optional trailing
/// meta like the CONTAINS/EXACT badge, X to remove; tapping the row removes).
class FilterList extends StatelessWidget {
  const FilterList({
    super.key,
    required this.filters,
    required this.onRemoveFilter,
    this.color = BuoyColors.primary,
    this.itemMetaBuilder,
  });

  final List<String> filters;
  final ValueChanged<String> onRemoveFilter;
  final Color color;
  final Widget Function(String filter)? itemMetaBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        for (final filter in filters)
          TouchableOpacity(
            activeOpacity: 0.8,
            onTap: () => onRemoveFilter(filter),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: BuoyColors.hover,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BuoyColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      filter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: color,
                      ),
                    ),
                  ),
                  if (itemMetaBuilder != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 8),
                      child: itemMetaBuilder!(filter),
                    )
                  else
                    const SizedBox(width: 8),
                  Icon(Icons.close, size: 12, color: color.hexAlpha(0x80)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
