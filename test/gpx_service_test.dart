import 'package:cyclecomp/gpx_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpxService', () {
    test('parses namespaced tracks and route points', () {
      const gpx = '''
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
          <trk><trkseg>
            <trkpt lat="-6.2" lon="106.8"><ele>12.5</ele><time>2026-11-11T03:00:00Z</time></trkpt>
            <trkpt lat="-6.21" lon="106.81" />
          </trkseg></trk>
        </gpx>
      ''';

      final points = GpxService.parse(gpx);

      expect(points, hasLength(2));
      expect(points.first.latitude, -6.2);
      expect(points.first.elevation, 12.5);
      expect(points.first.time, DateTime.utc(2026, 11, 11, 3));
      expect(points.last.longitude, 106.81);
    });

    test('round-trips planned routes as GPX route points', () {
      const points = [
        GpxPoint(latitude: -6.2, longitude: 106.8),
        GpxPoint(latitude: -6.21, longitude: 106.81),
      ];

      final encoded = GpxService.encode(
        name: 'Rute',
        points: points,
        isRoute: true,
      );
      final decoded = GpxService.parse(encoded);

      expect(encoded, contains('<rtept'));
      expect(decoded, hasLength(2));
      expect(decoded.last.latitude, points.last.latitude);
      expect(decoded.last.longitude, points.last.longitude);
    });

    test('rejects invalid coordinates and empty routes', () {
      expect(
        () => GpxService.parse(
          '<gpx><trk><trkseg><trkpt lat="91" lon="0"/></trkseg></trk></gpx>',
        ),
        throwsFormatException,
      );
      expect(
        () => GpxService.encode(name: 'Rute', points: const [], isRoute: true),
        throwsArgumentError,
      );
    });
  });

  test('calculates distance between GPS points', () {
    const jakarta = GpxPoint(latitude: -6.2088, longitude: 106.8456);
    const nearby = GpxPoint(latitude: -6.2098, longitude: 106.8456);

    expect(jakarta.distanceTo(nearby), inInclusiveRange(100, 120));
  });
}
