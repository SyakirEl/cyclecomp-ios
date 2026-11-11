import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapkit_flutter/mapkit_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'gpx_service.dart';

void main() {
  runApp(const CycleCompApp());
}

class CycleCompApp extends StatelessWidget {
  const CycleCompApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD8FF5F);
    return MaterialApp(
      title: 'CycleComp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101411),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF1B211D),
        ),
        useMaterial3: true,
      ),
      home: const RideHomePage(),
    );
  }
}

enum RideMode { record, route }

class RideHomePage extends StatefulWidget {
  const RideHomePage({super.key});

  @override
  State<RideHomePage> createState() => _RideHomePageState();
}

class _RideHomePageState extends State<RideHomePage> {
  static const _accent = Color(0xFFD8FF5F);
  static final _jakarta = CLLocationCoordinate2D(
    latitude: -6.2088,
    longitude: 106.8456,
  );

  RideMode _mode = RideMode.record;
  final List<GpxPoint> _ridePoints = [];
  final List<GpxPoint> _routePoints = [];
  MKMapViewController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _timer;
  Stopwatch? _stopwatch;
  Duration _elapsed = Duration.zero;
  double _distanceMeters = 0;
  double _speedKmh = 0;
  bool _isRecording = false;
  bool _isBusy = false;

  List<GpxPoint> get _visiblePoints =>
      _mode == RideMode.route ? _routePoints : _ridePoints;

  double get _routeDistance {
    var distance = 0.0;
    for (var index = 1; index < _routePoints.length; index++) {
      distance += _routePoints[index - 1].distanceTo(_routePoints[index]);
    }
    return distance;
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_positionSubscription?.cancel());
    super.dispose();
  }

  void _showMessage(String message, {bool settingsAction = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: settingsAction
              ? SnackBarAction(
                  label: 'Pengaturan',
                  onPressed: () => unawaited(Geolocator.openAppSettings()),
                )
              : null,
        ),
      );
  }

  Future<void> _startRide() async {
    if (_isBusy || _isRecording) return;
    setState(() => _isBusy = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage('Aktifkan Layanan Lokasi di iPhone untuk mulai merekam.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'Izin lokasi ditolak. Izinkan CycleComp mengakses lokasi di Pengaturan.',
          settingsAction: true,
        );
        return;
      }
      if (permission != LocationPermission.always) {
        _showMessage(
          'Agar rute tetap terekam saat layar terkunci, izinkan akses lokasi '
          'Always di Pengaturan iPhone.',
          settingsAction: true,
        );
        return;
      }

      _ridePoints.clear();
      _distanceMeters = 0;
      _speedKmh = 0;
      _elapsed = Duration.zero;
      _stopwatch = Stopwatch()..start();
      setState(() => _isRecording = true);

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecording) return;
        setState(() => _elapsed = _stopwatch?.elapsed ?? Duration.zero);
      });

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: AppleSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              activityType: ActivityType.fitness,
              distanceFilter: 3,
              allowBackgroundLocationUpdates: true,
              showBackgroundLocationIndicator: true,
              pauseLocationUpdatesAutomatically: false,
            ),
          ).listen(
            _onPosition,
            onError: (Object error) {
              _timer?.cancel();
              _stopwatch?.stop();
              if (mounted) setState(() => _isRecording = false);
              _showMessage('GPS berhenti: $error');
            },
          );
    } catch (error) {
      _showMessage('Tidak bisa memulai rekaman: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _onPosition(Position position) {
    if (!mounted || !_isRecording || position.accuracy > 50) return;

    final point = GpxPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      elevation: position.altitude,
      time: position.timestamp,
    );
    if (_ridePoints.isNotEmpty) {
      final segment = _ridePoints.last.distanceTo(point);
      if (segment < 2) return;
      _distanceMeters += segment;
    }

    _ridePoints.add(point);
    _speedKmh = position.speed.isFinite
        ? (position.speed * 3.6).clamp(0, 150)
        : 0;
    setState(() {});

    final controller = _mapController;
    if (_ridePoints.length == 1 && controller != null) {
      unawaited(
        controller.setCenter(
          CLLocationCoordinate2D(
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        ),
      );
    }
  }

  Future<void> _finishRide() async {
    if (_isBusy) return;
    _timer?.cancel();
    _stopwatch?.stop();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _elapsed = _stopwatch?.elapsed ?? _elapsed;
      _speedKmh = 0;
      _isBusy = true;
    });

    try {
      if (_ridePoints.length < 2) {
        _showMessage('Belum cukup titik GPS untuk menyimpan rute gowes.');
        return;
      }
      final file = await GpxService.save(
        name: 'Gowes CycleComp',
        points: _ridePoints,
        isRoute: false,
      );
      await _shareGpx(file, 'Aktivitas gowes CycleComp');
      _showMessage('Aktivitas disimpan sebagai GPX di iPhone.');
    } catch (error) {
      _showMessage('Gagal menyimpan aktivitas: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _onMapTap(CLLocationCoordinate2D coordinate) {
    if (_mode != RideMode.route || _isRecording) return;
    setState(() {
      _routePoints.add(
        GpxPoint(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude,
        ),
      );
    });
  }

  void _undoRoutePoint() {
    if (_routePoints.isEmpty) return;
    setState(_routePoints.removeLast);
  }

  void _clearRoute() {
    if (_routePoints.isEmpty) return;
    setState(_routePoints.clear);
  }

  Future<void> _saveRoute() async {
    if (_routePoints.length < 2 || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      final file = await GpxService.save(
        name: 'Rute CycleComp',
        points: _routePoints,
        isRoute: true,
      );
      await _shareGpx(file, 'Rute CycleComp');
      _showMessage('Rute disimpan sebagai GPX di iPhone.');
    } catch (error) {
      _showMessage('Gagal menyimpan rute: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _importGpx() async {
    if (_isBusy || _isRecording) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['gpx'],
        dialogTitle: 'Pilih rute GPX',
      );
      if (file == null) return;
      final contents = await file.readAsBytes();
      final points = GpxService.parse(utf8.decode(contents));
      if (points.length < 2) {
        throw const FormatException('GPX harus berisi minimal dua titik.');
      }
      setState(() {
        _routePoints
          ..clear()
          ..addAll(points);
        _mode = RideMode.route;
      });
      final first = points.first;
      final controller = _mapController;
      if (controller != null) {
        await controller.setCenter(
          CLLocationCoordinate2D(
            latitude: first.latitude,
            longitude: first.longitude,
          ),
        );
      }
      _showMessage('GPX berhasil dimuat: ${file.name}');
    } catch (error) {
      _showMessage('Tidak bisa membuka file GPX: $error');
    }
  }

  Future<void> _shareGpx(File file, String subject) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: subject),
    );
  }

  Set<MKPolyline> _buildPolylines() {
    if (_visiblePoints.length < 2) return {};
    return {
      MKPolyline(
        id: MKPolylineId(
          _mode == RideMode.route ? 'planned-route' : 'ride-track',
        ),
        coordinates: _visiblePoints
            .map(
              (point) => CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude,
              ),
            )
            .toList(),
        strokeColor: _accent,
        lineWidth: 6,
      ),
    };
  }

  Set<MKPointAnnotation> _buildAnnotations() {
    if (_visiblePoints.isEmpty) return {};
    final first = _visiblePoints.first;
    final annotations = <MKPointAnnotation>{
      MKPointAnnotation(
        id: const MKAnnotationId('route-start'),
        coordinate: CLLocationCoordinate2D(
          latitude: first.latitude,
          longitude: first.longitude,
        ),
        title: 'Mulai',
      ),
    };
    if (_visiblePoints.length > 1) {
      final last = _visiblePoints.last;
      annotations.add(
        MKPointAnnotation(
          id: const MKAnnotationId('route-finish'),
          coordinate: CLLocationCoordinate2D(
            latitude: last.latitude,
            longitude: last.longitude,
          ),
          title: 'Selesai',
        ),
      );
    }
    return annotations;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MKMapView(
              initialCamera: MKMapCamera(
                centerCoordinate: _jakarta,
                distance: 6500,
              ),
              showsCompass: false,
              showsScale: true,
              polylines: _buildPolylines(),
              annotations: _buildAnnotations(),
              onMapCreated: (controller) => _mapController = controller,
              onTap: _onMapTap,
              onDidFailLoadingMap: (message) {
                _showMessage('Apple Maps gagal dimuat: $message');
              },
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                if (_mode == RideMode.route && !_isRecording) _buildRouteHint(),
                const Spacer(),
                _buildControlPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF101411).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.pedal_bike, color: _accent),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CycleComp',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(
                  'RIDE YOUR WAY',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 9,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _ModeButton(
            mode: _mode,
            onChanged: (mode) {
              if (_isRecording) return;
              setState(() => _mode = mode);
            },
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: Icons.file_upload_outlined,
            label: 'Impor GPX',
            onPressed: _importGpx,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF101411).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              _routePoints.isEmpty
                  ? 'Ketuk peta untuk mulai menggambar rute'
                  : '${_routePoints.length} titik · jalur digambar manual',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF101411),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: _mode == RideMode.route ? _buildRoutePanel() : _buildRidePanel(),
      ),
    );
  }

  Widget _buildRidePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'AKTIVITAS GOWES',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_isRecording)
              const Row(
                children: [
                  _RecordingDot(),
                  SizedBox(width: 6),
                  Text(
                    'MEREKAM',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'JARAK',
                value: _formatDistance(_distanceMeters),
                unit: _distanceMeters < 1000 ? 'm' : 'km',
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'DURASI',
                value: _formatDuration(_elapsed),
                unit: '',
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'KECEPATAN',
                value: _speedKmh.toStringAsFixed(1),
                unit: 'km/j',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _isBusy
                ? null
                : _isRecording
                ? _finishRide
                : _startRide,
            icon: Icon(
              _isRecording ? Icons.stop_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              _isBusy
                  ? 'MENYIMPAN...'
                  : _isRecording
                  ? 'AKHIRI GOWES'
                  : 'MULAI REKAM',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _isRecording ? const Color(0xFFD95959) : _accent,
              foregroundColor: _isRecording
                  ? Colors.white
                  : const Color(0xFF141810),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'GPX disimpan di iPhone dan bisa dibagikan setelah gowes.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRoutePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'PANJANG RUTE',
                value: _formatDistance(_routeDistance),
                unit: _routeDistance < 1000 ? 'm' : 'km',
              ),
            ),
            Expanded(
              child: _Metric(
                label: 'TITIK',
                value: '${_routePoints.length}',
                unit: '',
              ),
            ),
            IconButton(
              tooltip: 'Urungkan titik terakhir',
              onPressed: _routePoints.isEmpty ? null : _undoRoutePoint,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Hapus rute',
              onPressed: _routePoints.isEmpty ? null : _clearRoute,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _routePoints.length < 2 || _isBusy ? null : _saveRoute,
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(
              _isBusy ? 'MENYIMPAN...' : 'SIMPAN & BAGIKAN GPX',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: const Color(0xFF141810),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Jalur digambar dengan garis lurus antar titik, tanpa layanan routing.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static String _formatDistance(double meters) => meters >= 1000
      ? (meters / 1000).toStringAsFixed(2)
      : meters.toStringAsFixed(0);

  static String _formatDuration(Duration duration) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:'
        '${twoDigits(duration.inMinutes.remainder(60))}:'
        '${twoDigits(duration.inSeconds.remainder(60))}';
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.mode, required this.onChanged});

  final RideMode mode;
  final ValueChanged<RideMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101411).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeOption(
              label: 'Gowes',
              icon: Icons.pedal_bike,
              selected: mode == RideMode.record,
              onPressed: () => onChanged(RideMode.record),
            ),
            _ModeOption(
              label: 'Rute',
              icon: Icons.route,
              selected: mode == RideMode.route,
              onPressed: () => onChanged(RideMode.route),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: selected ? const Color(0xFFD8FF5F) : Colors.white70,
        backgroundColor: selected ? Colors.white.withValues(alpha: 0.08) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF101411).withValues(alpha: 0.92),
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(color: Colors.white60, fontSize: 10),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFFD8FF5F),
        shape: BoxShape.circle,
      ),
    );
  }
}
