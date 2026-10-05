import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:notes/db/entities/note.dart';
import 'package:notes/main.dart';
import 'package:notes/theme/app_theme.dart';
import 'package:notes/components/note_card.dart';
import 'add_note_page.dart';
import 'package:shake/shake.dart';

class ViewNote extends StatefulWidget {
  const ViewNote({super.key});

  @override
  State<ViewNote> createState() => _ViewNoteState();
}

class _ViewNoteState extends State<ViewNote> {
  final notes = <Note>[].obs;
  final isLoading = false.obs;
  final hasMore = true.obs;

  final ScrollController scrollController = ScrollController();
  static const int _limit = 15;
  int _offset = 0;

  /// Shake detector reference
  ShakeDetector? _shakeDetector;

  /// Cooldown lock to prevent multiple spammed dialogs during a vigorous shake
  bool _isProcessingShake = false;

  @override
  void initState() {
    super.initState();
    fetchNotes();
    scrollController.addListener(_onScroll);

    /// Start listening to hardware sensor on page init
    _initShakeDetector();
  }

  void _initShakeDetector() {
    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: _onShakeDetected,
      shakeThresholdGravity: 2.7,
      shakeSlopTimeMS: 500,
      shakeCountResetTime: 1500,
      minimumShakeCount: 2,
    );
  }

  /// Callback signature matching PhoneShakeCallback (requires ShakeEvent parameter)
  void _onShakeDetected(ShakeEvent event) {
    // Cooldown & empty check
    if (_isProcessingShake || notes.isEmpty) return;

    // Hand off execution asynchronously without blocking the hardware sensor listener thread
    _handleShakeAction();
  }

  /// Asynchronous dialog & database handler
  /// Asynchronous optimistic delete handler
  Future<void> _handleShakeAction() async {
    // Cooldown & empty check
    if (_isProcessingShake || notes.isEmpty) return;
    _isProcessingShake = true;

    // 1. Cache the current state in memory for the Undo operation
    final cachedNotes = List<Note>.from(notes);

    // 2. Optimistic UI update: Instantly clear the UI list
    notes.clear();
    _offset = 0;
    hasMore.value = false;

    try {
      // 3. Immediately wipe the database
      await database.noteDao.deleteAllNotes();
      await database.noteDao.resetNoteSequence();

      // 4. Display the non-blocking Undo Snackbar
      Get.snackbar(
        'All Notes Cleared',
        'Your workspace is empty',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.chipBackground,
        colorText: AppColors.secondaryText,
        duration: const Duration(seconds: 5), // Slightly longer for bulk actions
        margin: const EdgeInsets.all(16),
        mainButton: TextButton(
          onPressed: () async {
            // Dismiss the snackbar instantly upon tapping Undo
            if (Get.isSnackbarOpen) {
              Get.closeCurrentSnackbar();
            }

            try {
              // A. Re-insert all cached notes back into SQLite.
              // Note: If you have an insertAllNotes(List<Note>) in your DAO, use it here for better performance.
              for (var note in cachedNotes) {
                await database.noteDao.insertNote(note);
              }

              // B. Refresh the UI from the database to ensure sequences and IDs are synced
              await refreshNotes();

              Get.snackbar('Restored', 'All notes have been restored.', snackPosition: SnackPosition.BOTTOM);
            } catch (e) {
              Get.snackbar('Error', 'Could not restore notes.');
              await refreshNotes(); // Fallback to source of truth
            }
          },
          child: const Text(
            'UNDO',
            style: TextStyle(
              color: AppColors.primaryAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } catch (e) {
      // If the SQLite deletion fails, revert the optimistic UI removal
      notes.assignAll(cachedNotes);
      Get.snackbar('Error', 'Failed to delete notes: $e');
    } finally {
      // Release the lock after the operation (or after the snackbar triggers)
      _isProcessingShake = false;
    }
  }

  Future refreshNotes() async {
    notes.clear();
    _offset = 0;
    hasMore.value = true;
    await fetchNotes();
  }

  void _onScroll() {
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200) {
      fetchNotes();
    }
  }

  Future<void> fetchNotes() async {
    if (isLoading.value || !hasMore.value) return;

    isLoading.value = true;
    try {
      final fetchedNotes = await database.noteDao.getNotesPaged(_limit, _offset);
      if (fetchedNotes.length < _limit) {
        hasMore.value = false;
      }
      notes.addAll(fetchedNotes.cast<Note>());
      _offset += fetchedNotes.length;
    } catch (e) {
      Get.snackbar('Error', e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void dispose() {
    // Correctly stop listening to prevent background sensor battery drain
    _shakeDetector?.stopListening();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Obx(() {
                  if (notes.isEmpty && isLoading.value) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryAccent),
                    );
                  }

                  if (notes.isEmpty) {
                    return const Center(
                      child: Text(
                        'No notes found',
                        style: TextStyle(color: AppColors.secondaryText),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: notes.length + (hasMore.value ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == notes.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Center(
                            child: CircularProgressIndicator(color: AppColors.primaryAccent),
                          ),
                        );
                      }

                      final currentNote = notes[index];

                      return Dismissible(
                        key: ValueKey(currentNote.id.toString()),
                        direction: DismissDirection.horizontal,

                        // Swipe Right Background (UPDATE)
                        background: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          child: const Icon(Icons.edit, color: Colors.white, size: 28),
                        ),

                        // Swipe Left Background (DELETE)
                        secondaryBackground: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white, size: 28),
                        ),

                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            // SWIPE RIGHT: Trigger Update Action
                            final result = await Get.to(() => AddNotePage(existingNote: currentNote));
                            if (result == true) {
                              await refreshNotes();
                            }
                            return false; // Prevent visual dismissal
                          } else if (direction == DismissDirection.endToStart) {
                            // SWIPE LEFT: Instantly allow visual dismissal
                            return true;
                          }
                          return false;
                        },
                        onDismissed: (direction) async {
                          if (direction == DismissDirection.endToStart) {
                            // 1. Cache the exact object and its index in memory for the Undo operation
                            final deletedNote = currentNote;
                            final deletedIndex = index;

                            // 2. Optimistic UI update: Instantly remove from GetX list
                            notes.removeAt(index);

                            try {
                              // 3. Immediately delete from the database
                              await database.noteDao.deleteNote(deletedNote);

                              // 4. Display non-blocking Undo Snackbar
                              Get.snackbar(
                                'Deleted',
                                'Note has been removed',
                                snackPosition: SnackPosition.BOTTOM,
                                backgroundColor: AppColors.chipBackground,
                                colorText: AppColors.secondaryText,
                                duration: const Duration(seconds: 4),
                                margin: const EdgeInsets.all(16),
                                mainButton: TextButton(
                                  onPressed: () async {
                                    if (Get.isSnackbarOpen) {
                                      Get.closeCurrentSnackbar();
                                    }

                                    try {
                                      await database.noteDao.insertNote(deletedNote);
                                      notes.insert(deletedIndex, deletedNote);
                                    } catch (e) {
                                      Get.snackbar('Error', 'Could not restore note.');
                                      await refreshNotes();
                                    }
                                  },
                                  child: const Text(
                                    'UNDO',
                                    style: TextStyle(
                                      color: AppColors.primaryAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            } catch (e) {
                              // If initial SQLite deletion fails, revert optimistic UI removal
                              notes.insert(deletedIndex, deletedNote);
                              Get.snackbar('Error', 'Failed to delete note');
                            }
                          }
                        },
                        child: NoteCardItem(note: currentNote),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final result = await Get.to(() => const AddNotePage());

            if (result == true) {
              await refreshNotes();
            }
          },
          backgroundColor: AppColors.primaryAccent,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}