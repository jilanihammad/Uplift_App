import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../data/repositories/auth_repository.dart';
import '../data/datasources/remote/api_client.dart';
import '../services/config_service.dart';
import 'dependency_container.dart';

final GetIt getIt = GetIt.instance;

void setupRepositories() {
  // Get ConfigService from dependency container
  final configService = DependencyContainer().configService;

  // Register repositories
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      apiClient: ApiClient(
        configService: configService,
      ),
    ),
  );
}
