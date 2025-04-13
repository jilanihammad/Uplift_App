import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_therapist_app/blocs/auth/auth_bloc.dart';
import 'package:ai_therapist_app/blocs/auth/auth_events.dart';
import 'package:ai_therapist_app/blocs/auth/auth_state.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({Key? key}) : super(key: key);

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _verificationId;
  String _phoneNumber = '';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _verifyPhoneNumber() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _phoneNumber = _phoneController.text;
      });

      context.read<AuthBloc>().add(
            PhoneVerificationEvent(phoneNumber: _phoneNumber),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthLoading) {
          setState(() {
            _isLoading = true;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }

        if (state is AuthAuthenticated) {
          // Navigate to home screen when authenticated
          context.go('/home');
        } else if (state is PhoneCodeSent) {
          _verificationId = state.verificationId;
          // Show OTP entry dialog
          _showOtpDialog(context);
        } else if (state is AuthError) {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Login with Phone Number')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Uplift',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter your phone number to continue',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+1 234 567 8900',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyPhoneNumber,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send Verification Code'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading ? null : () => context.go('/login'),
                  child: const Text('Use Email Instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOtpDialog(BuildContext context) {
    final otpController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Enter Verification Code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'We sent a verification code to $_phoneNumber',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpController,
                  decoration: const InputDecoration(
                    labelText: 'Verification Code',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isVerifying
                    ? null
                    : () {
                        if (otpController.text.isNotEmpty && _verificationId != null) {
                          setState(() {
                            isVerifying = true;
                          });
                          
                          // Verify OTP
                          context.read<AuthBloc>().add(
                                PhoneCodeSubmitEvent(
                                  verificationId: _verificationId!,
                                  smsCode: otpController.text,
                                ),
                              );
                          
                          Navigator.pop(context);
                        }
                      },
                child: isVerifying
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      )
                    : const Text('Verify'),
              ),
            ],
          );
        },
      ),
    );
  }
} 