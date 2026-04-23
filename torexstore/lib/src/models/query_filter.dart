/// Query filter for building database queries
///
/// Provides a fluent API for constructing queries:
/// ```dart
/// final filter = QueryFilter.eq('age', 25);
/// final filter = QueryFilter.and([
///   QueryFilter.gt('age', 18),
///   QueryFilter.eq('city', 'Tashkent'),
/// ]);
/// ```
class QueryFilter {
  final String _type;
  final String? _field;
  final dynamic _value;
  final dynamic _value2;
  final List<QueryFilter>? _conditions;

  const QueryFilter._({
    required String type,
    String? field,
    dynamic value,
    dynamic value2,
    List<QueryFilter>? conditions,
  })  : _type = type,
        _field = field,
        _value = value,
        _value2 = value2,
        _conditions = conditions;

  /// Equal to
  factory QueryFilter.eq(String field, dynamic value) => QueryFilter._(
        type: 'eq',
        field: field,
        value: value,
      );

  /// Not equal to
  factory QueryFilter.ne(String field, dynamic value) => QueryFilter._(
        type: 'ne',
        field: field,
        value: value,
      );

  /// Greater than
  factory QueryFilter.gt(String field, dynamic value) => QueryFilter._(
        type: 'gt',
        field: field,
        value: value,
      );

  /// Less than
  factory QueryFilter.lt(String field, dynamic value) => QueryFilter._(
        type: 'lt',
        field: field,
        value: value,
      );

  /// Greater than or equal
  factory QueryFilter.gte(String field, dynamic value) => QueryFilter._(
        type: 'gte',
        field: field,
        value: value,
      );

  /// Less than or equal
  factory QueryFilter.lte(String field, dynamic value) => QueryFilter._(
        type: 'lte',
        field: field,
        value: value,
      );

  /// Range query (inclusive start, exclusive end)
  factory QueryFilter.range(String field, dynamic start, dynamic end) =>
      QueryFilter._(
        type: 'range',
        field: field,
        value: start,
        value2: end,
      );

  /// Logical AND
  factory QueryFilter.and(List<QueryFilter> conditions) => QueryFilter._(
        type: 'and',
        conditions: conditions,
      );

  /// Logical OR
  factory QueryFilter.or(List<QueryFilter> conditions) => QueryFilter._(
        type: 'or',
        conditions: conditions,
      );

  /// Match all
  static const QueryFilter all = QueryFilter._(type: 'all');

  /// Get the filter type
  String get type => _type;

  /// Get the field name
  String? get field => _field;

  /// Get the value
  dynamic get value => _value;

  /// Get the second value (for range queries)
  dynamic get value2 => _value2;

  /// Get nested conditions
  List<QueryFilter>? get conditions => _conditions;

  @override
  String toString() {
    switch (_type) {
      case 'all':
        return 'QueryFilter.all()';
      case 'and':
        return 'QueryFilter.and($_conditions)';
      case 'or':
        return 'QueryFilter.or($_conditions)';
      default:
        return 'QueryFilter.$_type($_field, $_value${_value2 != null ? ', $_value2' : ''})';
    }
  }
}
