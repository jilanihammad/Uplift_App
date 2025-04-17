import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../data/repositories/auth_repository.dart';

final GetIt getIt = GetIt.instance;

void setupRepositories() {
  // Use cloud backend URL directly without conditional
  final String baseUrl = 'https://ai-therapist-backend-fuukqlcsha-uc.a.run.app';
            
  // Register repositories
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(baseUrl: baseUrl),
  );
}