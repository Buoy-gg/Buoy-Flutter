import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_network/buoy_network.dart';
import 'package:buoy_network/src/network_tool/network_filter.dart';

/// The image filter is ON BY DEFAULT, so a false positive silently hides a
/// request the developer is looking for. Detection is the risky part, not the
/// filtering.

NetworkCaptureEvent event({
  String url = 'https://api.dev/users',
  String? contentType,
  String method = 'GET',
  int? status = 200,
}) {
  final e = NetworkCaptureEvent(
    id: 'e1',
    method: method,
    url: url,
    timestamp: 1,
    requestClient: 'dio',
  )..status = status;
  if (contentType != null) {
    e.responseHeaders = {'content-type': contentType};
  }
  return e;
}

void main() {
  group('isImageEvent', () {
    test('an image content-type is an image', () {
      expect(isImageEvent(event(contentType: 'image/png')), isTrue);
      expect(isImageEvent(event(contentType: 'image/jpeg')), isTrue);
      expect(isImageEvent(event(contentType: 'image/svg+xml')), isTrue);
    });

    test('a non-image content-type is NOT, whatever the URL says', () {
      // A JSON endpoint that happens to live at /thumbnail.png is still JSON,
      // and hiding it would be the exact false positive that makes an
      // on-by-default filter dangerous.
      expect(
        isImageEvent(
          event(
            url: 'https://api.dev/thumbnail.png',
            contentType: 'application/json',
          ),
        ),
        isFalse,
      );
    });

    test('with no content-type yet, the extension decides', () {
      // In-flight requests and 304s carry no content-type — and in-flight is
      // exactly when the spam is most disruptive.
      expect(isImageEvent(event(url: 'https://cdn.dev/a/b/9.png')), isTrue);
      expect(isImageEvent(event(url: 'https://cdn.dev/x.JPEG')), isTrue);
      expect(isImageEvent(event(url: 'https://cdn.dev/x.webp')), isTrue);
      expect(isImageEvent(event(url: 'https://api.dev/users')), isFalse);
    });

    test('the QUERY STRING never counts as an extension', () {
      // `?next=/logo.png` must not hide a real API call.
      expect(
        isImageEvent(event(url: 'https://api.dev/users?next=/logo.png')),
        isFalse,
      );
    });

    test('a pending image is caught before its response arrives', () {
      expect(
        isImageEvent(event(url: 'https://cdn.dev/sprite.png', status: null)),
        isTrue,
      );
    });

    test('a dot in a path segment is not an extension', () {
      expect(isImageEvent(event(url: 'https://api.dev/v1.2/users')), isFalse);
      expect(isImageEvent(event(url: 'https://api.dev/files/report.')), isFalse);
    });
  });

  group('filterNetworkEvents', () {
    final events = [
      event(url: 'https://api.dev/users'),
      event(url: 'https://cdn.dev/a.png', contentType: 'image/png'),
      event(url: 'https://cdn.dev/b.jpg'),
    ];

    test('images are hidden by DEFAULT', () {
      const filter = NetworkFilter();
      expect(filter.hideImages, isTrue);
      final visible = filterNetworkEvents(events, filter);
      expect(visible, hasLength(1));
      expect(visible.single.url, 'https://api.dev/users');
    });

    test('turning it off shows them again', () {
      final visible = filterNetworkEvents(
        events,
        const NetworkFilter().copyWith(hideImages: false),
      );
      expect(visible, hasLength(3));
    });

    test('it does not light the "you changed a filter" indicator', () {
      // On-by-default plus counted-as-active would leave the dot lit forever,
      // which makes the dot meaningless.
      expect(const NetworkFilter().hasActiveFacets, isFalse);
      expect(
        const NetworkFilter().copyWith(hideImages: false).hasActiveFacets,
        isFalse,
      );
      expect(
        const NetworkFilter(status: NetworkStatusFilter.error).hasActiveFacets,
        isTrue,
      );
    });

    test('it composes with the other facets rather than replacing them', () {
      final mixed = [
        event(url: 'https://api.dev/a', method: 'POST'),
        event(url: 'https://api.dev/b'),
        event(url: 'https://cdn.dev/c.png', method: 'POST'),
      ];
      final visible = filterNetworkEvents(
        mixed,
        const NetworkFilter(methods: ['POST']),
      );
      expect(visible, hasLength(1));
      expect(visible.single.url, 'https://api.dev/a');
    });
  });
}
