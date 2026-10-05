import 'package:floor/floor.dart';

@Entity(tableName: 'notes')
class Note {
  @PrimaryKey(autoGenerate: true)
  final int? id;

  final String content;

  final String? location;

  final String? locationStatus;

  final String? createdAt;

  const Note({
    this.id,
    required this.content,
    this.location,
    this.locationStatus,
    this.createdAt,
  });
}