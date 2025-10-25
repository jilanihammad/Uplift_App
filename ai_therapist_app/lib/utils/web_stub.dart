// lib/utils/web_stub.dart
// This file provides stub implementations of platform-specific features for web

import 'dart:async';
import 'package:flutter/foundation.dart';

// Platform stub for web
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isWeb => true;
}

// File stub for web
class File {
  final String path;

  File(this.path);

  Future<bool> exists() async => false;

  bool existsSync() => false;

  Future<File> writeAsBytes(List<int> bytes) async {
    if (kDebugMode) {
      debugPrint('Web stub: Writing bytes to file at $path');
    }
    return this;
  }

  void deleteSync() {
    if (kDebugMode) {
      debugPrint('Web stub: Deleting file at $path');
    }
  }
}

// Directory stub for web
class Directory {
  final String path;

  Directory(this.path);

  Future<bool> exists() async => false;

  Future<Directory> create({bool recursive = false}) async {
    if (kDebugMode) {
      debugPrint('Web stub: Creating directory at $path');
    }
    return this;
  }

  String get parent => path;
}

// Permission handler stubs for web
class Permission {
  static Permission microphone = Permission._();

  Permission._();

  Future<PermissionStatus> request() async {
    return PermissionStatus.granted;
  }
}

enum PermissionStatus {
  granted,
  denied,
  restricted,
  limited,
  permanentlyDenied
}

// Process stub for web
class Process {
  static Future<ProcessResult> run(
      String command, List<String> arguments) async {
    if (kDebugMode) {
      debugPrint('Web stub: Running command $command with arguments $arguments');
    }
    return ProcessResult(0, 0, 'Web stub output', '');
  }
}

class ProcessResult {
  final int pid;
  final int exitCode;
  final String stdout;
  final String stderr;

  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);
}
