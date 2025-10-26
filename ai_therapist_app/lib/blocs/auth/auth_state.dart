/// AuthState represents all possible authentication states (loading, authenticated, error, etc.) throughout the app.
/// These immutable state classes enable the UI to reactively update based on authentication status changes.
library;

import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final Map<String, String> userInfo;

  const AuthAuthenticated({required this.userInfo});

  @override
  List<Object> get props => [userInfo];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object> get props => [message];
}

class PhoneVerificationInProgress extends AuthState {}

class PhoneCodeSent extends AuthState {
  final String verificationId;
  final int? resendToken;

  const PhoneCodeSent({
    required this.verificationId,
    this.resendToken,
  });

  @override
  List<Object?> get props => [verificationId, resendToken];
}
