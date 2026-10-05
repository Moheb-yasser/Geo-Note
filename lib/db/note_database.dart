import 'package:notes/db/daos/note_dao.dart';
import 'package:notes/db/entities/note.dart';
import 'package:floor/floor.dart';

// required package imports
import 'dart:async';
import 'package:sqflite/sqflite.dart' as sqflite;

part 'note_database.g.dart'; // the generated code will be there

@Database(version: 1, entities: [Note])
abstract class NoteDatabase extends FloorDatabase{

  NoteDao get noteDao;
}