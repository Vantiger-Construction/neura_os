import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// An in-memory file returned by a fake `FilePickerPlatform` (file_picker 13).
///
/// [declaredLength] is the size the platform reports before any read, or null
/// when the platform cannot tell. Bytes are only produced by
/// [readAsByteStream], so tests exercise the same streamed, capped read path
/// as the app.
final class FakePickedFile extends PlatformFile {
  FakePickedFile(this.name, Stream<List<int>> bytes, {this.declaredLength})
      : _bytes = bytes;

  /// A file whose content is [bytes] and whose reported length matches it.
  factory FakePickedFile.fromBytes(String name, List<int> bytes) =>
      FakePickedFile(name, Stream.value(bytes), declaredLength: bytes.length);

  @override
  final String name;
  final Stream<List<int>> _bytes;
  final int? declaredLength;

  @override
  Uri get uri => Uri.parse('content://synthetic/$name');

  @override
  XFile get xFile =>
      throw UnsupportedError('FakePickedFile is read through its stream.');

  @override
  int? lengthSync() => declaredLength;

  @override
  Future<int?> length() async => declaredLength;

  @override
  Future<Uint8List> readAsBytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in readAsByteStream()) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Stream<Uint8List> readAsByteStream() => _bytes
      .map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
}
