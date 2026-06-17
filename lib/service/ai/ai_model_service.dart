import 'dart:convert';
import 'package:http/http.dart' as http;

/// Sanitize the base URL by removing known API endpoint segments.
String _sanitizeBaseUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return url;

  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  const removable = {
    'chat', 'messages', 'completions', 'responses', 'invoke', 'openai',
  };

  final segments = uri.pathSegments.toList(growable: true);
  while (segments.isNotEmpty &&
      removable.contains(segments.last.toLowerCase())) {
    segments.removeLast();
  }

  final cleaned = uri.replace(pathSegments: segments);
  final result = cleaned.toString();
  return result.endsWith('/') ? result.substring(0, result.length - 1) : result;
}

/// Fetches the list of available model IDs from an OpenAI-compatible /models endpoint.
///
/// Returns a sorted list of model ID strings on success, or throws an exception
/// with a descriptive message on failure.
Future<List<String>> fetchAiModels({
  required String url,
  required String apiKey,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final baseUrl = _sanitizeBaseUrl(url);
  final modelsUrl =
      baseUrl.endsWith('/') ? '${baseUrl}models' : '$baseUrl/models';

  final response = await http.get(
    Uri.parse(modelsUrl),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
  ).timeout(timeout);

  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  final data = jsonDecode(response.body);
  final List<dynamic> models = data['data'] ?? [];

  if (models.isEmpty) {
    return [];
  }

  final ids =
      models.map<String>((m) => (m['id'] ?? m.toString()) as String).toList();
  ids.sort();
  return ids;
}
