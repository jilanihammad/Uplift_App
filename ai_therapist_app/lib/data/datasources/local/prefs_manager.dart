// lib/data/datasources/local/prefs_manager.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PrefsManager {
  late SharedPreferences _prefs;
  
  // Initialize shared preferences
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  // Save a boolean value
  Future<bool> setBool(String key, bool value) async {
    return await _prefs.setBool(key, value);
  }
  
  // Get a boolean value
  bool? getBool(String key) {
    return _prefs.getBool(key);
  }
  
  // Save a string value
  Future<bool> setString(String key, String value) async {
    return await _prefs.setString(key, value);
  }
  
  // Get a string value
  String? getString(String key) {
    return _prefs.getString(key);
  }
  
  // Save an integer value
  Future<bool> setInt(String key, int value) async {
    return await _prefs.setInt(key, value);
  }
  
  // Get an integer value
  int? getInt(String key) {
    return _prefs.getInt(key);
  }
  
  // Save a JSON object
  Future<bool> setJson(String key, Map<String, dynamic> value) async {
    return await _prefs.setString(key, jsonEncode(value));
  }
  
  // Get a JSON object
  Map<String, dynamic>? getJson(String key) {
    final String? jsonString = _prefs.getString(key);
    if (jsonString == null) return null;
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
  
  // Save a list of strings
  Future<bool> setStringList(String key, List<String> value) async {
    return await _prefs.setStringList(key, value);
  }
  
  // Get a list of strings
  List<String>? getStringList(String key) {
    return _prefs.getStringList(key);
  }
  
  // Remove a value
  Future<bool> remove(String key) async {
    return await _prefs.remove(key);
  }
  
  // Clear all values
  Future<bool> clear() async {
    return await _prefs.clear();
  }
}