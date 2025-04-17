import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../data/repositories/auth_repository.dart';

final getIt = GetIt.instance;

void setupRepositories() {
  // Always use cloud backend URL
  final String baseUrl = 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';
            
  // Register AuthRepository
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(baseUrl: baseUrl),
  );
}