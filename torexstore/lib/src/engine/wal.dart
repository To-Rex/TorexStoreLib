import 'dart:io';
import 'dart:typed_data';

/// Write-Ahead Log (WAL) for crash-safe writes.
///
/// Every mutation is first written to the WAL file. After successful
/// persistence to the main storage file, the WAL entry is truncated.
/// On recovery (next open), any remaining WAL entries are replayed.
class WriteAheadLog {
  final String _directory;
  File? _walFile;
  int _sequence = 0;

  WriteAheadLog(this._directory);

  /// Full path to the WAL file
  String get _walPath => '$_directory/_wal.log';

  /// Initialize the WAL system
  Future<void> init() async {
    _walFile = File(_walPath);
    if (!await _walFile!.exists()) {
      await _walFile!.create(recursive: true);
    }
  }

  /// Log a write operation before it's applied.
  /// Returns a sequence number for this entry.
  Future<int> logWrite(String collection, String docId, Map<String, dynamic> fields) async {
    _sequence++;
    final entry = WalEntry(
      sequence: _sequence,
      operation: WalOperation.put,
      collection: collection,
      docId: docId,
      fields: fields,
    );
    await _appendEntry(entry);
    return _sequence;
  }

  /// Log a delete operation before it's applied.
  Future<int> logDelete(String collection, String docId) async {
    _sequence++;
    final entry = WalEntry(
      sequence: _sequence,
      operation: WalOperation.delete,
      collection: collection,
      docId: docId,
    );
    await _appendEntry(entry);
    return _sequence;
  }

  /// Mark entries up to [sequence] as committed (truncated).
  Future<void> commit(int sequence) async {
    final entries = await readUncommitted();
    final remaining = entries.where((e) => e.sequence > sequence).toList();

    if (remaining.isEmpty) {
      await _walFile!.writeAsBytes([], flush: true);
    } else {
      final buffer = BytesBuilder();
      for (final entry in remaining) {
        buffer.add(_serializeEntry(entry));
      }
      await _walFile!.writeAsBytes(buffer.toBytes(), flush: true);
    }
  }

  /// Read all uncommitted WAL entries (for recovery).
  Future<List<WalEntry>> readUncommitted() async {
    if (_walFile == null || !await _walFile!.exists()) return [];

    final bytes = await _walFile!.readAsBytes();
    if (bytes.isEmpty) return [];

    final entries = <WalEntry>[];
    int offset = 0;

    while (offset < bytes.length) {
      try {
        final result = _deserializeEntry(bytes, offset);
        entries.add(result.entry);
        offset = result.newOffset;
        if (result.entry.sequence > _sequence) {
          _sequence = result.entry.sequence;
        }
      } catch (_) {
        break; // Corrupted entry
      }
    }

    return entries;
  }

  /// Clear the entire WAL (used after full recovery).
  Future<void> clear() async {
    if (_walFile != null && await _walFile!.exists()) {
      await _walFile!.writeAsBytes([], flush: true);
    }
    _sequence = 0;
  }

  /// Check if WAL has uncommitted entries.
  Future<bool> hasUncommittedEntries() async {
    if (_walFile == null || !await _walFile!.exists()) return false;
    final bytes = await _walFile!.readAsBytes();
    return bytes.isNotEmpty;
  }

  /// Replay uncommitted entries via callback, then clear the WAL.
  /// Returns the number of entries replayed.
  Future<int> replay(
    void Function(String collection, String docId, WalOperation op, Map<String, dynamic>? fields) onEntry,
  ) async {
    final entries = await readUncommitted();
    if (entries.isEmpty) return 0;

    for (final entry in entries) {
      onEntry(entry.collection, entry.docId, entry.operation, entry.fields);
    }

    await clear();
    return entries.length;
  }

  Future<void> _appendEntry(WalEntry entry) async {
    final bytes = _serializeEntry(entry);
    await _walFile!.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  Uint8List _serializeEntry(WalEntry entry) {
    final buffer = BytesBuilder();

    // Magic byte for validation
    buffer.addByte(0xAB);

    // Sequence number (u32)
    buffer.add(_uint32ToBytes(entry.sequence));

    // Operation type (1 byte)
    buffer.addByte(entry.operation == WalOperation.put ? 1 : 2);

    // Collection name
    final collBytes = Uint8List.fromList(entry.collection.codeUnits);
    buffer.add(_uint16ToBytes(collBytes.length));
    buffer.add(collBytes);

    // Document ID
    final idBytes = Uint8List.fromList(entry.docId.codeUnits);
    buffer.add(_uint16ToBytes(idBytes.length));
    buffer.add(idBytes);

    // Fields (only for put operations)
    if (entry.operation == WalOperation.put && entry.fields != null) {
      final fieldBytes = _serializeFields(entry.fields!);
      buffer.add(_uint32ToBytes(fieldBytes.length));
      buffer.add(fieldBytes);
    } else {
      buffer.add(_uint32ToBytes(0));
    }

    // CRC8 checksum
    final data = buffer.toBytes();
    final checksum = _crc8(data);
    final result = BytesBuilder();
    result.add(data);
    result.addByte(checksum);

    return result.toBytes();
  }

  _EntryDecodeResult _deserializeEntry(Uint8List bytes, int offset) {
    int pos = offset;

    if (bytes[pos] != 0xAB) {
      throw FormatException('Invalid WAL magic byte');
    }
    pos++;

    final sequence = _bytesToUint32(bytes, pos);
    pos += 4;

    final opByte = bytes[pos];
    pos++;
    final operation = opByte == 1 ? WalOperation.put : WalOperation.delete;

    final collLen = _bytesToUint16(bytes, pos);
    pos += 2;
    final collection = String.fromCharCodes(bytes.sublist(pos, pos + collLen));
    pos += collLen;

    final idLen = _bytesToUint16(bytes, pos);
    pos += 2;
    final docId = String.fromCharCodes(bytes.sublist(pos, pos + idLen));
    pos += idLen;

    final fieldsLen = _bytesToUint32(bytes, pos);
    pos += 4;

    Map<String, dynamic>? fields;
    if (fieldsLen > 0) {
      final fieldsBytes = bytes.sublist(pos, pos + fieldsLen);
      fields = _deserializeFields(Uint8List.fromList(fieldsBytes));
      pos += fieldsLen;
    }

    final entryBytes = bytes.sublist(offset, pos);
    final expectedChecksum = bytes[pos];
    final actualChecksum = _crc8(Uint8List.fromList(entryBytes));
    if (expectedChecksum != actualChecksum) {
      throw FormatException('WAL checksum mismatch');
    }
    pos++;

    return _EntryDecodeResult(
      entry: WalEntry(
        sequence: sequence,
        operation: operation,
        collection: collection,
        docId: docId,
        fields: fields,
      ),
      newOffset: pos,
    );
  }

  Uint8List _serializeFields(Map<String, dynamic> fields) {
    final buffer = BytesBuilder();
    final entries = fields.entries.toList();

    buffer.add(_uint32ToBytes(entries.length));

    for (final entry in entries) {
      final nameBytes = Uint8List.fromList(entry.key.codeUnits);
      buffer.add(_uint16ToBytes(nameBytes.length));
      buffer.add(nameBytes);
      _writeValue(buffer, entry.value);
    }

    return buffer.toBytes();
  }

  Map<String, dynamic> _deserializeFields(Uint8List bytes) {
    final fields = <String, dynamic>{};
    int offset = 0;

    final numFields = _bytesToUint32(bytes, offset);
    offset += 4;

    for (int i = 0; i < numFields; i++) {
      final nameLen = _bytesToUint16(bytes, offset);
      offset += 2;
      final name = String.fromCharCodes(bytes.sublist(offset, offset + nameLen));
      offset += nameLen;

      final valueType = bytes[offset];
      offset++;

      final result = _readValue(bytes, offset, valueType);
      fields[name] = result.value;
      offset = result.newOffset;
    }

    return fields;
  }

  void _writeValue(BytesBuilder buffer, dynamic value) {
    if (value == null) {
      buffer.addByte(0);
    } else if (value is String) {
      buffer.addByte(1);
      final bytes = Uint8List.fromList(value.codeUnits);
      buffer.add(_uint32ToBytes(bytes.length));
      buffer.add(bytes);
    } else if (value is int) {
      buffer.addByte(2);
      buffer.add(_int64ToBytes(value));
    } else if (value is double) {
      buffer.addByte(3);
      buffer.add(_float64ToBytes(value));
    } else if (value is bool) {
      buffer.addByte(4);
      buffer.addByte(value ? 1 : 0);
    } else {
      buffer.addByte(0);
    }
  }

  _ValueResult _readValue(Uint8List data, int offset, int type) {
    switch (type) {
      case 0:
        return _ValueResult(null, offset);
      case 1:
        final len = _bytesToUint32(data, offset);
        offset += 4;
        final value = String.fromCharCodes(data.sublist(offset, offset + len));
        return _ValueResult(value, offset + len);
      case 2:
        final value = _bytesToInt64(data, offset);
        return _ValueResult(value, offset + 8);
      case 3:
        final value = _bytesToFloat64(data, offset);
        return _ValueResult(value, offset + 8);
      case 4:
        final value = data[offset] != 0;
        return _ValueResult(value, offset + 1);
      default:
        return _ValueResult(null, offset);
    }
  }

  int _crc8(List<int> data) {
    int crc = 0xFF;
    for (final byte in data) {
      crc ^= byte & 0xFF;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ 0x07) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }
    }
    return crc;
  }

  static Uint8List _uint32ToBytes(int value) {
    final bytes = ByteData(4);
    bytes.setUint32(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static int _bytesToUint32(Uint8List data, int offset) {
    return ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.little);
  }

  static Uint8List _uint16ToBytes(int value) {
    final bytes = ByteData(2);
    bytes.setUint16(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static int _bytesToUint16(Uint8List data, int offset) {
    return ByteData.sublistView(data, offset, offset + 2).getUint16(0, Endian.little);
  }

  static Uint8List _int64ToBytes(int value) {
    final bytes = ByteData(8);
    bytes.setInt64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static int _bytesToInt64(Uint8List data, int offset) {
    return ByteData.sublistView(data, offset, offset + 8).getInt64(0, Endian.little);
  }

  static Uint8List _float64ToBytes(double value) {
    final bytes = ByteData(8);
    bytes.setFloat64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static double _bytesToFloat64(Uint8List data, int offset) {
    return ByteData.sublistView(data, offset, offset + 8).getFloat64(0, Endian.little);
  }
}

/// WAL operation types
enum WalOperation { put, delete }

/// A recovered WAL entry (public for engine access)
class WalEntry {
  final int sequence;
  final WalOperation operation;
  final String collection;
  final String docId;
  final Map<String, dynamic>? fields;

  const WalEntry({
    required this.sequence,
    required this.operation,
    required this.collection,
    required this.docId,
    this.fields,
  });
}

class _EntryDecodeResult {
  final WalEntry entry;
  final int newOffset;
  const _EntryDecodeResult({required this.entry, required this.newOffset});
}

class _ValueResult {
  final dynamic value;
  final int newOffset;
  const _ValueResult(this.value, this.newOffset);
}
