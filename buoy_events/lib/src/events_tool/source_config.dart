/// Ports the per-source display config shared by the item, filters, and detail
/// (RN `SOURCE_CONFIG` / `getSourceDisplayConfig` / `SOURCE_BADGE_LABELS`).
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

/// Label + accent color for a granular event source.
class SourceConfig {
  const SourceConfig(this.label, this.color, this.badgeLabel);
  final String label;
  final Color color;
  final String badgeLabel;
}

const Map<String, SourceConfig> kSourceConfig = {
  EventSourceIds.storageAsync:
      SourceConfig('Storage', Color(0xFF8B5CF6), 'STORAGE'),
  EventSourceIds.storageMmkv: SourceConfig('MMKV', Color(0xFFF59E0B), 'MMKV'),
  EventSourceIds.redux: SourceConfig('Redux', Color(0xFF3B82F6), 'REDUX'),
  EventSourceIds.network: SourceConfig('Network', Color(0xFF10B981), 'NET'),
  EventSourceIds.reactQuery: SourceConfig('Query', Color(0xFFEC4899), 'QUERY'),
  EventSourceIds.reactQueryQuery:
      SourceConfig('Query', Color(0xFFEC4899), 'QUERY'),
  EventSourceIds.reactQueryMutation:
      SourceConfig('Mutation', Color(0xFFF97316), 'MUTATION'),
  EventSourceIds.route: SourceConfig('Route', Color(0xFF06B6D4), 'ROUTE'),
  EventSourceIds.zustand: SourceConfig('Zustand', Color(0xFF764ABC), 'ZUSTAND'),
  EventSourceIds.jotai: SourceConfig('Jotai', Color(0xFF14B8A6), 'JOTAI'),
  EventSourceIds.render: SourceConfig('Render', Color(0xFFF472B6), 'RENDER'),
};

SourceConfig sourceConfigFor(String source) =>
    kSourceConfig[source] ??
    SourceConfig(source, const Color(0xFF6B7280), source.toUpperCase());

/// RN `getStatusColor`.
Color statusColor(EventStatus status) => switch (status) {
      EventStatus.success => const Color(0xFF10B981),
      EventStatus.error => const Color(0xFFEF4444),
      EventStatus.pending => const Color(0xFFF59E0B),
      EventStatus.neutral => const Color(0xFF6B7280),
    };

/// Display sources shown as filter badges (RN `ALL_DISPLAY_SOURCES`).
const List<String> kAllDisplaySources = [
  EventSourceIds.storageAsync,
  EventSourceIds.redux,
  EventSourceIds.network,
  EventSourceIds.reactQueryQuery,
  EventSourceIds.reactQueryMutation,
  EventSourceIds.route,
  EventSourceIds.zustand,
  EventSourceIds.jotai,
  EventSourceIds.render,
];

/// A display source → the granular sources it matches (RN
/// `SOURCE_TO_EVENT_SOURCES`).
const Map<String, List<String>> kSourceToEventSources = {
  EventSourceIds.storageAsync: [
    EventSourceIds.storageAsync,
    EventSourceIds.storageMmkv,
  ],
  EventSourceIds.storageMmkv: [EventSourceIds.storageMmkv],
  EventSourceIds.redux: [EventSourceIds.redux],
  EventSourceIds.network: [EventSourceIds.network],
  EventSourceIds.reactQuery: [
    EventSourceIds.reactQuery,
    EventSourceIds.reactQueryQuery,
  ],
  EventSourceIds.reactQueryQuery: [
    EventSourceIds.reactQuery,
    EventSourceIds.reactQueryQuery,
  ],
  EventSourceIds.reactQueryMutation: [EventSourceIds.reactQueryMutation],
  EventSourceIds.route: [EventSourceIds.route],
  EventSourceIds.zustand: [EventSourceIds.zustand],
  EventSourceIds.jotai: [EventSourceIds.jotai],
  EventSourceIds.render: [EventSourceIds.render],
};

/// A display source → its store discovery id (RN `displaySourceToStoreId`).
const Map<String, String> kDisplaySourceToStoreId = {
  EventSourceIds.storageAsync: 'storage',
  EventSourceIds.storageMmkv: 'storage',
  EventSourceIds.redux: 'redux',
  EventSourceIds.network: 'network',
  EventSourceIds.reactQuery: 'react-query',
  EventSourceIds.reactQueryQuery: 'react-query',
  EventSourceIds.reactQueryMutation: 'react-query',
  EventSourceIds.route: 'route-events',
  EventSourceIds.zustand: 'zustand',
  EventSourceIds.jotai: 'jotai',
  EventSourceIds.render: 'render',
};
