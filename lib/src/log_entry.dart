import 'dart:convert';

class LogEntry {
  final int id;
  final DateTime timestamp;
  final String method;
  final String url;
  final String? name;
  final Map<String, String> requestHeaders;
  final Map<String, String> queryParameters;
  final String? requestBody;
  final int? statusCode;
  final Map<String, String>? responseHeaders;
  final String? responseBody;
  final Duration? duration;
  final String? error;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    this.name,
    required this.requestHeaders,
    this.queryParameters = const {},
    this.requestBody,
    this.statusCode,
    this.responseHeaders,
    this.responseBody,
    this.duration,
    this.error,
  });

  String get displayName => name ?? url;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'method': method,
      'url': url,
      'name': name,
      'requestHeaders': requestHeaders,
      'queryParameters': queryParameters,
      'requestBody': _tryFormatBody(requestBody),
      'statusCode': statusCode,
      'responseHeaders': responseHeaders,
      'responseBody': _tryFormatBody(responseBody),
      'durationMs': duration?.inMilliseconds,
      'error': error,
    };
  }

  static String? _tryFormatBody(String? body) {
    if (body == null) return null;
    try {
      final decoded = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return body;
    }
  }
}
