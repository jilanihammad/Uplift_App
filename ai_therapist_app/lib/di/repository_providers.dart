import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../domain/repositories/auth_repository.dart';

final getIt = GetIt.instance;

void setupRepositories() {
  // Base URL based on environment
  const baseUrl = kDebugMode ? 'http://10.0.2.2:8000' : 'https://your-production-api.com';
            
  // Register the AuthRepository
  getIt.registerLazySingleton(
    () => AuthRepository(baseUrl: baseUrl),
  );
}