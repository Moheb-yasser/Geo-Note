import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:notes/db/entities/note.dart';
import 'package:notes/main.dart';
import 'package:notes/theme/app_theme.dart';

class NoteCardItem extends StatefulWidget {
  final Note note;

  const NoteCardItem({super.key, required this.note});

  @override
  State<NoteCardItem> createState() => _NoteCardItemState();
}

class _NoteCardItemState extends State<NoteCardItem> {
  String? _displayLocation;
  bool _isLoadingLocation = false;
  bool _hasLocationError = false;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  void _resolveLocation() {
    final loc = widget.note.location;
    final status = widget.note.locationStatus;

    if (loc == null || loc.trim().isEmpty) return;

    // Check if the note is pending location resolution
    if (status == 'PENDING' || loc == 'PENDING') {
      _fetchCurrentLocationAndAddress();
      return;
    }

    // Check if location is raw coordinates "lat, lng"
    final parts = loc.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());

      if (lat != null && lng != null) {
        _fetchAddress(lat, lng);
        return;
      }
    }

    // Already resolved string address
    _displayLocation = loc;
  }

  /// Lightweight background task: acquires GPS -> reverse geocodes -> persists to SQLite
  Future<void> _fetchCurrentLocationAndAddress() async {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = true;
      _hasLocationError = false;
    });

    try {
      // 1. Fetch current GPS position (medium accuracy reduces battery & chip load)
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // 2. Reverse-geocode position to address
      List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      String resolvedAddress = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String locality = place.locality ?? place.subAdministrativeArea ?? '';
        String country = place.country ?? '';
        String formatted = [locality, country].where((e) => e.trim().isNotEmpty).join(', ');
        if (formatted.isNotEmpty) resolvedAddress = formatted;
      }

      if (!mounted) return;

      setState(() {
        _displayLocation = resolvedAddress;
        _isLoadingLocation = false;
      });

      // 3. Persist resolved address to local DB so future app loads stay RESOLVED
      if (widget.note.id != null) {
        final updatedNote = Note(
          id: widget.note.id,
          content: widget.note.content,
          location: resolvedAddress,
          locationStatus: 'RESOLVED',
          createdAt: widget.note.createdAt,
        );
        await database.noteDao.updateNote(updatedNote);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _hasLocationError = true;
      });
    }
  }

  Future<void> _fetchAddress(double lat, double lng) async {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = true;
      _hasLocationError = false;
    });

    try {
      List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(lat, lng);
      if (!mounted) return;

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        String locality = place.locality ?? place.subAdministrativeArea ?? '';
        String country = place.country ?? '';
        String formatted = [locality, country].where((e) => e.trim().isNotEmpty).join(', ');

        setState(() {
          _displayLocation = formatted.isNotEmpty ? formatted : '$lat, $lng';
        });
      } else {
        setState(() => _displayLocation = '$lat, $lng');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasLocationError = true);
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  String _formatDateTime(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return 'Unknown date';
    try {
      final dateTime = DateTime.parse(rawDate);
      return DateFormat('yyyy, MMM dd, hh:mm a').format(dateTime);
    } catch (_) {
      return rawDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasLocation = widget.note.location != null && widget.note.location!.trim().isNotEmpty;

    final List<String> nonLines = widget.note.content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final String mainText = nonLines.isNotEmpty ? nonLines[0] : '';
    final String secondaryText = nonLines.length > 1 ? nonLines[1] : '';

    return SizedBox(
      width: double.infinity,
      child: Card(
        color: AppColors.chipBackground,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mainText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              if (secondaryText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  secondaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (hasLocation)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _hasLocationError
                          ? InkWell(
                        onTap: _resolveLocation, // Retries location acquisition
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, size: 14, color: Colors.red),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Retry',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                          : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: _isLoadingLocation ? AppColors.secondaryText : AppColors.primaryAccent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _isLoadingLocation ? 'Loading...' : (_displayLocation ?? widget.note.location!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _isLoadingLocation ? AppColors.secondaryText : AppColors.primaryAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(widget.note.createdAt),
                      style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
                    ),
                  ],
                )
              else
                Text(
                  _formatDateTime(widget.note.createdAt),
                  style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}