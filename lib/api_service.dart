import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

// Service to handle API calls and fetch configurations
class ApiService {
  Future<Map<String, dynamic>> fetchConfigurations() async {
    final response = await http.get(Uri.parse(apiUrl));
    if (response.statusCode == 200) {
      final List<dynamic> jsonResponse = jsonDecode(response.body);
      Map<String, dynamic> configMap = {};
      
      // Convert the list of configuration objects to a map using the 'name' key
      for (var item in jsonResponse) {
        if (item is Map<String, dynamic>) {
          configMap[item['name']] = item;
        }
      }
      return configMap;
    } else {
      throw Exception('Failed to load configurations');
    }
  }
}