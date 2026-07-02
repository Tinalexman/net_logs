import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'log_entry.dart';

class NetLogsInterceptor extends Interceptor {
  final List<LogEntry> _logs = [];
  final StreamController<LogEntry> _logController = StreamController<LogEntry>.broadcast();
  int _counter = 0;
  bool _enabled = true;

  bool get enabled => _enabled;
  Stream<LogEntry> get logStream => _logController.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);

  void setEnabled(bool value) {
    _enabled = value;
  }

  void clear() {
    _logs.clear();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_enabled) {
      return handler.next(options);
    }

    final now = DateTime.now();
    final entry = LogEntry(
      id: ++_counter,
      timestamp: now,
      method: options.method,
      url: options.uri.toString(),
      name: options.extra['requestName'] as String?,
      requestHeaders: options.headers.map((k, v) => MapEntry(k, '$v')),
      queryParameters: options.queryParameters.map((k, v) => MapEntry(k, '$v')),
      requestBody: _getRequestBody(options),
    );

    options.extra['_net_log_entry'] = entry;
    options.extra['_net_log_start'] = now;

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!_enabled) {
      return handler.next(response);
    }

    final start = response.requestOptions.extra['_net_log_start'] as DateTime?;
    final entry = response.requestOptions.extra['_net_log_entry'] as LogEntry;

    final captured = LogEntry(
      id: entry.id,
      timestamp: entry.timestamp,
      method: entry.method,
      url: entry.url,
      name: entry.name,
      requestHeaders: entry.requestHeaders,
      queryParameters: entry.queryParameters,
      requestBody: entry.requestBody,
      statusCode: response.statusCode,
      responseHeaders: _headersToMap(response.headers.map),
      responseBody: _getResponseBody(response),
      duration: start != null ? DateTime.now().difference(start) : null,
    );

    _logs.add(captured);
    _logController.add(captured);

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!_enabled) {
      return handler.next(err);
    }

    final start = err.requestOptions.extra['_net_log_start'] as DateTime?;
    final entry = err.requestOptions.extra['_net_log_entry'] as LogEntry;

    final captured = LogEntry(
      id: entry.id,
      timestamp: entry.timestamp,
      method: entry.method,
      url: entry.url,
      name: entry.name,
      requestHeaders: entry.requestHeaders,
      queryParameters: entry.queryParameters,
      requestBody: entry.requestBody,
      statusCode: err.response?.statusCode,
      responseHeaders: err.response != null ? _headersToMap(err.response!.headers.map) : null,
      responseBody: err.response != null ? _getResponseBody(err.response!) : err.message,
      duration: start != null ? DateTime.now().difference(start) : null,
      error: err.message,
    );

    _logs.add(captured);
    _logController.add(captured);

    handler.next(err);
  }

  static Map<String, String> _headersToMap(Map<String, List<String>> headers) {
    return headers.map((key, value) => MapEntry(key, value.join(', ')));
  }

  static String? _getRequestBody(RequestOptions options) {
    final data = options.data;
    if (data == null) return null;
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return '$data';
    }
  }

  static String? _getResponseBody(Response response) {
    final data = response.data;
    if (data == null) return null;
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return '$data';
    }
  }

  void dispose() {
    _logController.close();
  }
}
