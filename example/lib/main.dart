import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:net_logs/net_logs.dart';

void main() {
  runApp(const NetLogsExampleApp());
}

class NetLogsExampleApp extends StatefulWidget {
  const NetLogsExampleApp({super.key});

  @override
  State<NetLogsExampleApp> createState() => _NetLogsExampleAppState();
}

class _NetLogsExampleAppState extends State<NetLogsExampleApp> {
  final _interceptor = NetLogsInterceptor();
  late final NetLogsServer _server;
  late final Dio _dio;
  bool _serverRunning = false;
  final _results = <String>[];

  @override
  void initState() {
    super.initState();
    _server = NetLogsServer(interceptor: _interceptor);
    _dio = Dio()..interceptors.add(_interceptor);
  }

  @override
  void dispose() {
    _server.stop();
    _interceptor.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    await _server.start();
    setState(() => _serverRunning = true);
  }

  Future<void> _stopServer() async {
    await _server.stop();
    setState(() => _serverRunning = false);
  }

  Future<void> _makeGetRequest() async {
    _addResult('GET https://jsonplaceholder.typicode.com/posts/1');
    try {
      final res = await _dio.get(
        'https://jsonplaceholder.typicode.com/posts/1',
        options: Options(extra: {'requestName': 'Fetch Post'}),
      );
      _addResult('  -> ${res.statusCode} (${res.data['title']})');
    } catch (e) {
      _addResult('  -> ERROR: $e');
    }
  }

  Future<void> _makePostRequest() async {
    _addResult('POST https://jsonplaceholder.typicode.com/posts');
    try {
      final res = await _dio.post(
        'https://jsonplaceholder.typicode.com/posts',
        data: {'title': 'foo', 'body': 'bar', 'userId': 1},
        options: Options(extra: {'requestName': 'Create Post'}),
      );
      _addResult('  -> ${res.statusCode} (id: ${res.data['id']})');
    } catch (e) {
      _addResult('  -> ERROR: $e');
    }
  }

  Future<void> _makeErrorRequest() async {
    _addResult('GET https://jsonplaceholder.typicode.com/invalid');
    try {
      await _dio.get('https://jsonplaceholder.typicode.com/invalid');
    } catch (e) {
      _addResult('  -> ERROR: ${e.runtimeType}');
    }
  }

  void _addResult(String line) {
    setState(() => _results.insert(0, line));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Net Logs Example'),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Open http://localhost:${_server.port} in your browser '
                'to see the network log dashboard.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _serverRunning ? _stopServer : _startServer,
                      icon: Icon(_serverRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(_serverRunning ? 'Stop Server' : 'Start Server'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_serverRunning)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Dashboard at http://localhost:${_server.port}',
                        style: const TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _makeGetRequest,
                    child: const Text('GET /posts/1'),
                  ),
                  FilledButton.tonal(
                    onPressed: _makePostRequest,
                    child: const Text('POST /posts'),
                  ),
                  FilledButton.tonal(
                    onPressed: _makeErrorRequest,
                    child: const Text('GET /invalid (error)'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          'Make a request to see results here',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            _results[i],
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: _results[i].startsWith('  -> ERROR')
                                  ? Colors.red[300]
                                  : Colors.grey[300],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
