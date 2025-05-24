/// AuthEvent defines all user-triggered actions related to authentication (login, register, logout, etc.).
/// These events are dispatched from UI widgets to AuthBloc, maintaining clean separation between UI and authentication logic.

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class CheckAuthStatusEvent extends AuthEvent {}

class LoginEvent extends AuthEvent {
  final String email;
  final String password;

  const LoginEvent({
    required this.email,
    required this.password,
  });

  @override
  List<Object> get props => [email, password];
}

class RegisterEvent extends AuthEvent {
  final String name;
  final String email;
  final String password;

  const RegisterEvent({
    required this.name,
    required this.email,
    required this.password,
  });

  @override
  List<Object> get props => [name, email, password];
}

class LogoutEvent extends AuthEvent {}

class GoogleSignInEvent extends AuthEvent {}

class PhoneVerificationEvent extends AuthEvent {
  final String phoneNumber;

  const PhoneVerificationEvent({required this.phoneNumber});

  @override
  List<Object> get props => [phoneNumber];
}

class PhoneCodeSentEvent extends AuthEvent {
  final String verificationId;
  final int? resendToken;

  const PhoneCodeSentEvent({
    required this.verificationId,
    this.resendToken,
  });

  @override
  List<Object?> get props => [verificationId, resendToken];
}

class PhoneVerificationFailedEvent extends AuthEvent {
  final String message;

  const PhoneVerificationFailedEvent({required this.message});

  @override
  List<Object> get props => [message];
}

class PhoneCodeAutoRetrievalEvent extends AuthEvent {
  final PhoneAuthCredential credential;

  const PhoneCodeAutoRetrievalEvent({required this.credential});

  @override
  List<Object?> get props => [credential];
}

class PhoneCodeTimeoutEvent extends AuthEvent {
  final String verificationId;

  const PhoneCodeTimeoutEvent({required this.verificationId});

  @override
  List<Object> get props => [verificationId];
}

class PhoneCodeSubmitEvent extends AuthEvent {
  final String verificationId;
  final String smsCode;

  const PhoneCodeSubmitEvent({
    required this.verificationId,
    required this.smsCode,
  });

  @override
  List<Object> get props => [verificationId, smsCode];
}
