import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../data/repositories/auth_repository.dart';
import '../data/datasources/remote/api_client.dart';
import '../services/config_service.dart';
import 'service_locator.dart';

final GetIt getIt = GetIt.instance;

void setupRepositories() {
  // Get ConfigService from service locator
  final configService = serviceLocator<ConfigService>();

  // Register repositories
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      apiClient: ApiClient(
        configService: configService,
      ),
    ),
  );
}
