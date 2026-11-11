import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

class GpxPoint {
  const GpxPoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.time,
  });

  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? time;

  double distanceTo(GpxPoint other) {
    const earthRadius = 6371000.0;
    final latitudeDelta = _toRadians(other.latitude - latitude);
    final longitudeDelta = _toRadians(other.longitude - longitude);
    final a =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(_toRadians(latitude)) *
            math.cos(_toRadians(other.latitude)) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}

class GpxService {
  static const _namespace = 'http://www.topografix.com/GPX/1/1';

  static List<GpxPoint> parse(String contents) {
    final document = XmlDocument.parse(contents);
    final pointElements = document.descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'trkpt' || element.name.local == 'rtept',
        )
        .toList();
    if (pointElements.isEmpty) {
      throw const FormatException(
        'File GPX tidak berisi titik rute atau trek.',
      );
    }

    return pointElements
        .map((element) {
          final latitude = double.tryParse(element.getAttribute('lat') ?? '');
          final longitude = double.tryParse(element.getAttribute('lon') ?? '');
          if (latitude == null ||
              longitude == null ||
              !latitude.isFinite ||
              !longitude.isFinite ||
              latitude < -90 ||
              latitude > 90 ||
              longitude < -180 ||
              longitude > 180) {
            throw const FormatException('Koordinat dalam GPX tidak valid.');
          }

          final elevation = _childText(element, 'ele');
          final time = _childText(element, 'time');
          return GpxPoint(
            latitude: latitude,
            longitude: longitude,
            elevation: elevation == null ? null : double.tryParse(elevation),
            time: time == null ? null : DateTime.tryParse(time),
          );
        })
        .toList(growable: false);
  }

  static String encode({
    required String name,
    required List<GpxPoint> points,
    required bool isRoute,
  }) {
    if (points.length < 2) {
      throw ArgumentError.value(
        points.length,
        'points',
        'At least two points are required.',
      );
    }
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'gpx',
      attributes: const {
        'version': '1.1',
        'creator': 'CycleComp',
        'xmlns': _namespace,
      },
      nest: () {
        builder.element(
          isRoute ? 'rte' : 'trk',
          nest: () {
            builder.element('name', nest: () => builder.text(name));
            if (isRoute) {
              for (final point in points) {
                _writePoint(builder, 'rtept', point);
              }
            } else {
              builder.element(
                'trkseg',
                nest: () {
                  for (final point in points) {
                    _writePoint(builder, 'trkpt', point);
                  }
                },
              );
            }
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true);
  }

  static Future<File> save({
    required String name,
    required List<GpxPoint> points,
    required bool isRoute,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final activities = Directory(
      '${directory.path}${Platform.pathSeparator}Activities',
    );
    await activities.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final prefix = isRoute ? 'route' : 'ride';
    final file = File(
      '${activities.path}${Platform.pathSeparator}${prefix}_$timestamp.gpx',
    );
    await file.writeAsString(
      encode(name: name, points: points, isRoute: isRoute),
      flush: true,
    );
    return file;
  }

  static void _writePoint(XmlBuilder builder, String tag, GpxPoint point) {
    builder.element(
      tag,
      attributes: {
        'lat': point.latitude.toStringAsFixed(7),
        'lon': point.longitude.toStringAsFixed(7),
      },
      nest: () {
        if (point.elevation != null && point.elevation!.isFinite) {
          builder.element(
            'ele',
            nest: () => builder.text('${point.elevation}'),
          );
        }
        if (point.time != null) {
          builder.element(
            'time',
            nest: () => builder.text(point.time!.toUtc().toIso8601String()),
          );
        }
      },
    );
  }

  static String? _childText(XmlElement element, String name) {
    for (final child in element.childElements) {
      if (child.name.local == name) return child.innerText;
    }
    return null;
  }
}
