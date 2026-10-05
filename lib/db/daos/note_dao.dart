import 'package:floor/floor.dart';
import 'package:notes/db/entities/note.dart';

@dao
abstract class NoteDao {
  @Query('select * from notes limit :limit offset :offset')
  Future<List<Note>> getNotesPaged(int limit, int offset);

  @insert
  Future<int> insertNote(Note note);

  @update
  Future<void> updateNote(Note note);

  @delete
  Future<void> deleteNote(Note note);

  @Query('delete from notes')
  Future<void> deleteAllNotes();

  @Query('delete from sqlite_sequence where name = "notes"')
  Future<void> resetNoteSequence();

}