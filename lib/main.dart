import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:notes/pages/view_note.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

import 'db/note_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initDatabase();
  runApp(const MyApp());
}

Future<void> initDatabase() async{
  await copyDatabase();

  final dir = await getApplicationDocumentsDirectory();

  final path = join(dir.path,'notes.db');


  database = await $FloorNoteDatabase.databaseBuilder(path).build();

}

late final NoteDatabase database;

Future<void> copyDatabase() async {
  final dir = await getApplicationDocumentsDirectory();

  final path = join(dir.path,'notes.db');

  if(File(path).existsSync()) return;
  ByteData data = await rootBundle.load(join("assets","databases/notes.db"));
  List<int> bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  await File(path).writeAsBytes(bytes, flush: true);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(home: ViewNote(),
      debugShowCheckedModeBanner: false,);
  }
}