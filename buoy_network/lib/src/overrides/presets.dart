/// Ports packages/network/src/network/overrides/presets.ts — turning a captured
/// request into a rule draft.
library;

import 'dart:convert';

import '../network_capture.dart';
import 'override_rule.dart';
import 'override_rules_store.dart';

/// The pattern for a rule built from a real request.
///
/// The query string is dropped and replaced with `*`, which is not a
/// simplification — it's the difference between a rule that works and one that
/// silently never fires. Plenty of clients cache-bust
/// (`?timestamp=1785783081234`), carry a request id, or page; pinning the exact
/// URL means the next call to the same endpoint doesn't match. Found exactly
/// that way on RN: an "Offline" rule on a Pokémon request sat at 0 hits because
/// the app appends a timestamp to every call.
///
/// The path stays exact, so this still means "this endpoint" and not "this
/// host" — and the editor shows the pattern, so narrowing it back down is one
/// edit away.
String patternForUrl(String url) {
  final query = url.indexOf('?');
  return query == -1 ? url : '${url.substring(0, query)}*';
}

/// Render a captured body as editable text.
String _bodyToText(Object? data) {
  if (data == null) return '';
  if (data is String) return data;
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return '';
  }
}

/// Prefill a rule from a captured request.
///
/// Seeds the REAL response as the body so the common edit — change two fields
/// of a payload you just saw — starts from something true rather than nothing.
OverrideRule draftFromEvent(NetworkCaptureEvent event) {
  final status = event.status;
  return OverrideRule(
    id: OverrideRulesStore.instance.nextId(),
    enabled: true,
    urlPattern: patternForUrl(event.url),
    methods: [event.method.toUpperCase()],
    kind: OverrideRuleKind.respond,
    status: status != null && status >= statusMin ? status : 200,
    statusText: event.statusText,
    body: _bodyToText(event.responseData),
    times: null,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// A blank rule for the "+" path.
OverrideRule blankDraft() => OverrideRule(
  id: OverrideRulesStore.instance.nextId(),
  enabled: true,
  urlPattern: '',
  kind: OverrideRuleKind.respond,
  status: 500,
  body: '',
  times: null,
  createdAt: DateTime.now().millisecondsSinceEpoch,
);
