import 'package:ai_therapist_app/blocs/auth/auth_events.dart';
import 'package:ai_therapist_app/blocs/auth/auth_state.dart';
import 'package:ai_therapist_app/services/auth_service.dart';
import 'package:ai_therapist_app/services/onboarding_service.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide PhoneCodeSent;

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService;
  final OnboardingService _onboardingService;

  AuthBloc({
    required AuthService authService,
    required OnboardingService onboardingService,
  })  : _authService = authService,
        _onboardingService = onboardingService,
        super(AuthInitial()) {
    on<CheckAuthStatusEvent>(_checkAuthStatus);
    on<LoginEvent>(_login);
    on<RegisterEvent>(_register);
    on<LogoutEvent>(_logout);
    on<GoogleSignInEvent>(_googleSignIn);
    on<PhoneVerificationEvent>(_verifyPhone);
    on<PhoneCodeSubmitEvent>(_submitPhoneCode);
    on<PhoneCodeSentEvent>(_onPhoneCodeSent);
    on<PhoneVerificationFailedEvent>(_onPhoneVerificationFailed);
    on<PhoneCodeAutoRetrievalEvent>(_onPhoneCodeAutoRetrieval);
    on<PhoneCodeTimeoutEvent>(_onPhoneCodeTimeout);
  }

  Future<void> _checkAuthStatus(
      CheckAuthStatusEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final isLoggedIn = await _authService.isLoggedIn;
      if (isLoggedIn) {
        final userInfoDynamic = await _authService.getUserInfo();
        final userInfo = _convertToStringMap(userInfoDynamic);
        emit(AuthAuthenticated(userInfo: userInfo));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _login(LoginEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final success = await _authService.login(event.email, event.password);
      if (success) {
        final userInfoDynamic = await _authService.getUserInfo();
        final userInfo = _convertToStringMap(userInfoDynamic);
        emit(AuthAuthenticated(userInfo: userInfo));
      } else {
        emit(const AuthError(message: 'Login failed'));
      }
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _register(RegisterEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final success = await _authService.register(
        event.name,
        event.email,
        event.password,
      );
      if (success) {
        final userInfoDynamic = await _authService.getUserInfo();
        final userInfo = _convertToStringMap(userInfoDynamic);
        emit(AuthAuthenticated(userInfo: userInfo));
      } else {
        emit(const AuthError(message: 'Registration failed'));
      }
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _logout(LogoutEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _authService.logout();
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _googleSignIn(
      GoogleSignInEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final success = await _authService.signInWithGoogle();
      if (success) {
        final userInfoDynamic = await _authService.getUserInfo();
        final userInfo = _convertToStringMap(userInfoDynamic);
        emit(AuthAuthenticated(userInfo: userInfo));
      } else {
        emit(const AuthError(message: 'Google sign-in failed'));
      }
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _verifyPhone(
      PhoneVerificationEvent event, Emitter<AuthState> emit) async {
    emit(PhoneVerificationInProgress());
    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: event.phoneNumber,
        onVerificationCompleted: (PhoneAuthCredential credential) {
          add(PhoneCodeAutoRetrievalEvent(credential: credential));
        },
        onVerificationFailed: (FirebaseAuthException error) {
          add(PhoneVerificationFailedEvent(message: error.toString()));
        },
        onCodeSent: (verificationId, resendToken) {
          add(PhoneCodeSentEvent(
            verificationId: verificationId,
            resendToken: resendToken,
          ));
        },
        onCodeAutoRetrievalTimeout: (verificationId) {
          add(PhoneCodeTimeoutEvent(verificationId: verificationId));
        },
      );
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _submitPhoneCode(
      PhoneCodeSubmitEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final success = await _authService.signInWithPhoneAuthCredential(
        verificationId: event.verificationId,
        smsCode: event.smsCode,
      );
      if (success) {
        final userInfoDynamic = await _authService.getUserInfo();
        final userInfo = _convertToStringMap(userInfoDynamic);
        emit(AuthAuthenticated(userInfo: userInfo));
      } else {
        emit(const AuthError(message: 'Phone verification failed'));
      }
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  void _onPhoneCodeSent(PhoneCodeSentEvent event, Emitter<AuthState> emit) {
    emit(PhoneCodeSent(
      verificationId: event.verificationId,
      resendToken: event.resendToken,
    ));
  }

  void _onPhoneVerificationFailed(
      PhoneVerificationFailedEvent event, Emitter<AuthState> emit) {
    emit(AuthError(message: event.message));
  }

  Future<void> _onPhoneCodeAutoRetrieval(
      PhoneCodeAutoRetrievalEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final success = await _authService.signInWithCredential(event.credential);
      if (success) {
        final userInfoDynamic = await _authService.getUserInfo();
        final userInfo = _convertToStringMap(userInfoDynamic);
        emit(AuthAuthenticated(userInfo: userInfo));
      } else {
        emit(const AuthError(message: 'Auto-retrieval sign-in failed'));
      }
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  void _onPhoneCodeTimeout(
      PhoneCodeTimeoutEvent event, Emitter<AuthState> emit) {
    emit(PhoneCodeSent(
      verificationId: event.verificationId,
      resendToken: null,
    ));
  }

  // Helper method to convert dynamic map to string map
  Map<String, String> _convertToStringMap(Map<String, dynamic> dynamicMap) {
    Map<String, String> stringMap = {};
    dynamicMap.forEach((key, value) {
      stringMap[key] = value.toString();
    });
    return stringMap;
  }

  @override
  Future<void> close() {
    // Clean up any resources, subscriptions, or streams here
    // For example, if we added any StreamSubscriptions in the future:
    // _subscription?.cancel();
    return super.close();
  }
}
