import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding; // Alias import eliminates scope errors
import 'package:notes/db/entities/note.dart';
import 'package:notes/main.dart';
import 'package:notes/theme/app_theme.dart';
import 'package:notes/pages/map_picker_page.dart';

enum LocationSource { current, map }

class AddNotePage extends StatefulWidget {
  final Note? existingNote; /// Update or Add?

  const AddNotePage({super.key, this.existingNote});

  @override
  State<AddNotePage> createState() => _AddNotePageState(); // Typed State binding
}

class _AddNotePageState extends State<AddNotePage> {
  late final TextEditingController _textController;

  String? _selectedLocation;
  bool _isUsingCurrentLocation = false;
  bool _isLocating = false;

  final RxBool _isValidNote = false.obs;

  @override
  void initState() {
    super.initState();
    // Pre-fill fields if editing an existing note
    _textController = TextEditingController(text: widget.existingNote?.content ?? '');
    _selectedLocation = widget.existingNote?.location;
    _isUsingCurrentLocation = widget.existingNote?.locationStatus == 'PENDING';

    _isValidNote.value = _textController.text.trim().isNotEmpty;

    // 3. Attach the smart listener
    _textController.addListener(_validateInput);
  }

  @override
  void dispose() {
    super.dispose();
    _textController.dispose();
    _textController.removeListener(_validateInput);
  }

  void _validateInput() {
    final bool hasValidText = _textController.text.trim().isNotEmpty;

    // MICRO-OPTIMIZATION: Only update the Rx variable if the state actually flipped.
    // This prevents the Obx widget from rebuilding on every single keystroke.
    if (_isValidNote.value != hasValidText) {
      _isValidNote.value = hasValidText;
    }
  }


// In add_note_page.dart

  Future<void> _handleLocationPress() async {
    if (_isLocating) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final LocationSource? source = await Get.defaultDialog(
        title: 'Attach Location',
        middleText: 'How would you like to set your location?',
        backgroundColor: AppColors.background,
        titleStyle: const TextStyle(color: AppColors.primaryText),
        middleTextStyle: const TextStyle(color: AppColors.secondaryText),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.my_location, color: AppColors.primaryAccent),
            label: const Text('Use Current', style: TextStyle(color: AppColors.primaryAccent)),
            onPressed: () => Get.back(result: LocationSource.current),
          ),
          TextButton.icon(
            icon: const Icon(Icons.map, color: AppColors.primaryAccent),
            label: const Text('Choose on Map', style: TextStyle(color: AppColors.primaryAccent)),
            onPressed: () => Get.back(result: LocationSource.map),
          ),
        ],
      );

      if (source == LocationSource.current) {
        setState(() {
          _isUsingCurrentLocation = true;
          _selectedLocation = 'PENDING';
        });
      } else if (source == LocationSource.map) {
        _isUsingCurrentLocation = false;
        await _openMapPicker();
      }
    } catch (e) {
      Get.snackbar('Error', e.toString());
    }
  }

  Future<void> _saveNote() async {
    final cleanContent = _textController.text.trim();
    if (cleanContent.isEmpty) return;

    String? status;
    String? locationValue = _selectedLocation;

    if (_isUsingCurrentLocation) {
      status = 'PENDING';
      locationValue = 'PENDING';
    } else if (_selectedLocation != null) {
      status = 'RESOLVED';
    }

    try {
      final note = Note(
        id: widget.existingNote?.id, // Keep the same ID for updates
        content: _textController.text,
        location: locationValue,
        locationStatus: status,
        createdAt: widget.existingNote?.createdAt ?? DateTime.now().toIso8601String(),
      );

      if (widget.existingNote == null) {
        await database.noteDao.insertNote(note); // Create new
      } else {
        await database.noteDao.updateNote(note); // Update existing
      }

      Get.back(result: true);
    } catch (e) {
      Get.snackbar('Database Error', e.toString());
    }
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLocating = true);

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;

      // Save raw coordinates instead of a resolved address
      setState(() {
        _selectedLocation = '${position.latitude}, ${position.longitude}';
      });
    } on TimeoutException {
      if (!mounted) return;
      Get.snackbar('Timeout', 'The location is unavailable. Signal is too weak.', backgroundColor: Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      Get.snackbar('Error', 'The location is unavailable.', backgroundColor: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _openMapPicker() async {
    final String? pickedAddress = await Get.to<String>(
          () => const MapPickerPage(),
      transition: Transition.rightToLeft,
    );

    if (pickedAddress != null && pickedAddress.trim().isNotEmpty) {
      setState(() {
        _selectedLocation = pickedAddress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
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
          actions: [
            if (_isLocating)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryAccent,
                    ),
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  _selectedLocation != null ? Icons.location_on : Icons.location_on_outlined,
                  color: _selectedLocation != null ? AppColors.primaryAccent : AppColors.primaryText,
                ),
                onPressed: _handleLocationPress,
              ),

            // 6. Localized rebuild using Obx
            Obx(() {
              // The button is active ONLY if text is valid AND we aren't currently fetching GPS
              final bool canSave = _isValidNote.value && !_isLocating;

              return IconButton(
                icon: Icon(
                  Icons.check,
                  // Visually gray out the button when it cannot be pressed
                  color: canSave ? AppColors.primaryText : AppColors.secondaryText,
                  size: 28,
                ),
                // Passing null automatically disables the button tap and ripple effect
                onPressed: canSave ? _saveNote : null,
              );
            }),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedLocation != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.my_location, size: 14, color: AppColors.primaryAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _selectedLocation!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _selectedLocation = null),
                        child: const Icon(Icons.close, size: 16, color: AppColors.secondaryText),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textSelectionTheme: TextSelectionThemeData(
                        cursorColor: AppColors.primaryAccent,
                        selectionColor: AppColors.primaryAccent.withOpacity(0.3), // Light highlight when selecting text
                        selectionHandleColor: AppColors.primaryAccent, // The teardrop pointer
                      ),
                    ),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      expands: true,
                      autofocus: true,
                      cursorColor: AppColors.primaryAccent, // Also set here for good measure
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 18,
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Start typing',
                        hintStyle: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 18,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}