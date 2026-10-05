import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:notes/theme/app_theme.dart';

class MapPickerPage extends StatefulWidget {
  final LatLng? initialPosition;

  const MapPickerPage({super.key, this.initialPosition});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  late final MapController _mapController;
  late LatLng _centerPosition;

  Timer? _debounceTimer;
  String _addressPreview = 'Move map to select location';
  bool _isGeocoding = false;

  // Default fallback center (Cairo, Egypt) if no location given
  static const LatLng _defaultLocation = LatLng(30.0444, 31.2357);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _centerPosition = widget.initialPosition ?? _defaultLocation;

    // Initial reverse geocode for starting position
    _reverseGeocode(_centerPosition);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Debounces reverse geocoding to prevent lag while dragging
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _centerPosition = camera.center;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _reverseGeocode(_centerPosition);
    });
  }

  Future<void> _reverseGeocode(LatLng target) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);

    try {
      final geocodingInstance = Geocoding();
      List<Placemark> placemarks = await geocodingInstance.placemarkFromCoordinates(
        target.latitude,
        target.longitude,
      );

      if (!mounted) return;

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final locality = place.locality ?? place.subAdministrativeArea ?? '';
        final country = place.country ?? '';

        final formatted = [locality, country]
            .where((e) => e.trim().isNotEmpty)
            .join(', ');

        setState(() {
          _addressPreview = formatted.isNotEmpty
              ? formatted
              : '${target.latitude.toStringAsFixed(4)}, ${target.longitude.toStringAsFixed(4)}';
        });
      } else {
        setState(() {
          _addressPreview = '${target.latitude.toStringAsFixed(4)}, ${target.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressPreview = '${target.latitude.toStringAsFixed(4)}, ${target.longitude.toStringAsFixed(4)}';
      });
    } finally {
      if (mounted) {
        setState(() => _isGeocoding = false);
      }
    }
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final newCenter = LatLng(pos.latitude, pos.longitude);
      _mapController.move(newCenter, 16.0);
    } catch (_) {
      Get.snackbar(
        'Location Error',
        'Could not fetch current GPS location.',
        backgroundColor: AppColors.chipBackground,
        colorText: AppColors.primaryText,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.primaryText),
            onPressed: () => Get.back(),
          ),
          title: const Text(
            'Choose Location',
            style: TextStyle(color: AppColors.primaryText, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.my_location, color: AppColors.primaryAccent),
              onPressed: _moveToCurrentLocation,
            ),
          ],
        ),
        body: Stack(
          children: [
            // 1. Interactive Map Engine
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _centerPosition,
                initialZoom: 15.0,
                minZoom: 3.0,
                maxZoom: 18.0,
                onPositionChanged: _onPositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.notes',
                ),
              ],
            ),

            // 2. Fixed Center Pin Overlay (Zero Widget Rebuild Jank during drag)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36.0), // Align needle point to exact center
                child: Icon(
                  Icons.location_on,
                  size: 44,
                  color: AppColors.primaryAccent,
                ),
              ),
            ),

            // 3. Bottom Preview Bar & Confirm Button
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.place,
                          size: 18,
                          color: AppColors.primaryAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isGeocoding ? 'Loading address...' : _addressPreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primaryText,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (_isGeocoding)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryAccent,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          String finalResult = _addressPreview;

                          // Fallback to raw coordinates if the network is still resolving
                          // or if the map hasn't been interacted with yet.
                          if (_isGeocoding || _addressPreview == 'Move map to select location') {
                            finalResult = '${_centerPosition.latitude}, ${_centerPosition.longitude}';
                          }

                          Get.back(result: finalResult);
                        },
                        child: const Text(
                          'Confirm Location',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}