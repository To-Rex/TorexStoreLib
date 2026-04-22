import 'dart:typed_data';

/// A document in the TorexStore database
///
/// Documents are stored as binary key-value pairs.
/// Supports string, integer, float, boolean, and null values.
class TorexDocument {
  /// Unique document ID
  final String id;

  /// Field data
  final Map<String, dynamic> _fields;

  /// Create a new document
  TorexDocument({
    required this.id,
    required Map<String, dynamic> fields,
  }) : _fields = Map.unmodifiable(fields);

  /// Create a document from a map
  factory TorexDocument.fromMap(String id, Map<String, dynamic> map) {
    return TorexDocument(id: id, fields: map);
  }

  /// Get a field value
  dynamic operator [](String key) => _fields[key];

  /// Get all field names
  Iterable<String> get keys => _fields.keys;

  /// Get all field values
  Iterable<dynamic> get values => _fields.values;

  /// Get all entries
  Iterable<MapEntry<String, dynamic>> get entries => _fields.entries;

  /// Check if a field exists
  bool containsKey(String key) => _fields.containsKey(key);

  /// Number of fields
  int get length => _fields.length;

  /// Check if document has no fields
  bool get isEmpty => _fields.isEmpty;

  /// Convert to a plain map (without id)
  Map<String, dynamic> toMap() => Map.from(_fields);

  /// Convert to a plain map with id included
  Map<String, dynamic> toMapWithId() => {'id': id, ..._fields};

  /// Serialize document fields to binary format
  Uint8List toBytes() {
    final entries = _fields.entries.toList();
    final buffer = BytesBuilder();

    // Number of fields
    buffer.add(_uint32ToBytes(entries.length));

    for (final entry in entries) {
      // Field name
      final nameBytes = Uint8List.fromList(entry.key.codeUnits);
      buffer.add(_uint16ToBytes(nameBytes.length));
      buffer.add(nameBytes);

      // Value
      _writeValue(buffer, entry.value);
    }

    return buffer.toBytes();
  }

  /// Deserialize document from binary format
  static Map<String, dynamic> fromBytes(Uint8List data) {
    final fields = <String, dynamic>{};
    int offset = 0;

    // Read number of fields
    final numFields = _bytesToUint32(data, offset);
    offset += 4;

    for (int i = 0; i < numFields; i++) {
      // Read field name length
      final nameLen = _bytesToUint16(data, offset);
      offset += 2;

      // Read field name
      final name = String.fromCharCodes(data.sublist(offset, offset + nameLen));
      offset += nameLen;

      // Read value type
      final valueType = data[offset];
      offset += 1;

      // Read value
      final result = _readValue(data, offset, valueType);
      fields[name] = result.value;
      offset = result.newOffset;
    }

    return fields;
  }

  void _writeValue(BytesBuilder buffer, dynamic value) {
    if (value == null) {
      buffer.addByte(0); // Null
    } else if (value is String) {
      buffer.addByte(1); // String
      final bytes = Uint8List.fromList(value.codeUnits);
      buffer.add(_uint32ToBytes(bytes.length));
      buffer.add(bytes);
    } else if (value is int) {
      buffer.addByte(2); // Integer
      buffer.add(_int64ToBytes(value));
    } else if (value is double) {
      buffer.addByte(3); // Float
      buffer.add(_float64ToBytes(value));
    } else if (value is bool) {
      buffer.addByte(4); // Boolean
      buffer.addByte(value ? 1 : 0);
    } else {
      buffer.addByte(0); // Fallback to null
    }
  }

  static _ValueResult _readValue(Uint8List data, int offset, int type) {
    switch (type) {
      case 0: // Null
        return _ValueResult(null, offset);
      case 1: // String
        final len = _bytesToUint32(data, offset);
        offset += 4;
        final value = String.fromCharCodes(data.sublist(offset, offset + len));
        return _ValueResult(value, offset + len);
      case 2: // Integer
        final value = _bytesToInt64(data, offset);
        return _ValueResult(value, offset + 8);
      case 3: // Float
        final value = _bytesToFloat64(data, offset);
        return _ValueResult(value, offset + 8);
      case 4: // Boolean
        final value = data[offset] != 0;
        return _ValueResult(value, offset + 1);
      default:
        return _ValueResult(null, offset);
    }
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

  @override
  String toString() => 'TorexDocument(id: $id, fields: $_fields)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TorexDocument && id == other.id && _fields == other._fields;

  @override
  int get hashCode => Object.hash(id, _fields);
}

class _ValueResult {
  final dynamic value;
  final int newOffset;
  _ValueResult(this.value, this.newOffset);
}
