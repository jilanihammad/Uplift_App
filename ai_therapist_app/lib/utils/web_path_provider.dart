// lib/utils/web_path_provider.dart
// This file provides mock implementations of path_provider methods for web platform

import 'dart:async';
import 'package:flutter/foundation.dart';

/// A web-compatible implementation of getApplicationDocumentsDirectory
/// that returns a mock directory path for web.
class WebDirectory {
  final String path;
  WebDirectory(this.path);
}

/// Get a directory where files can be stored
Future<WebDirectory> getApplicationDocumentsDirectory() async {
  if (kDebugMode) {
    print('Using web mock for getApplicationDocumentsDirectory');
  }
  return WebDirectory('/mock/documents');
}

/// Get a temporary directory
Future<WebDirectory> getTemporaryDirectory() async {
  if (kDebugMode) {
    print('Using web mock for getTemporaryDirectory');
  }
  return WebDirectory('/mock/temp');
}

/// Get the external storage directory
Future<WebDirectory?> getExternalStorageDirectory() async {
  if (kDebugMode) {
    print('Using web mock for getExternalStorageDirectory');
  }
  return WebDirectory('/mock/external');
}

/// Get the downloads directory
Future<WebDirectory?> getDownloadsDirectory() async {
  if (kDebugMode) {
    print('Using web mock for getDownloadsDirectory');
  }
  return WebDirectory('/mock/downloads');
}