// Throwaway verification harness — NOT part of the app. Confirms real
// Firebase Phone Auth actually delivers an SMS before anything is built
// on top of that assumption. Delete once verified.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

const _testPhoneNumber = '+2348168777063';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _PhoneTestApp());
}

class _PhoneTestApp extends StatelessWidget {
  const _PhoneTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: _PhoneTestScreen());
  }
}

class _PhoneTestScreen extends StatefulWidget {
  const _PhoneTestScreen();

  @override
  State<_PhoneTestScreen> createState() => _PhoneTestScreenState();
}

class _PhoneTestScreenState extends State<_PhoneTestScreen> {
  String _status = 'Starting…';
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _log(String message) {
    // Printed to the browser console AND shown on screen, so a puppeteer
    // console listener and a screenshot both capture the outcome.
    // ignore: avoid_print
    print('[PHONE_TEST] $message');
    setState(() => _status = message);
  }

  Future<void> _run() async {
    try {
      _log('Initializing Firebase…');
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      _log('Calling verifyPhoneNumber for $_testPhoneNumber…');
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _testPhoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) {
          _log('RESULT: verificationCompleted (auto-retrieved) — smsCode=${credential.smsCode}');
        },
        verificationFailed: (FirebaseAuthException e) {
          _log('RESULT: verificationFailed — code=${e.code} message=${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _log('RESULT: codeSent — verificationId=$verificationId (SMS dispatched by Firebase)');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _log('RESULT: codeAutoRetrievalTimeout — verificationId=$verificationId');
        },
      );
    } catch (e, st) {
      _log('RESULT: THREW — $e');
      // ignore: avoid_print
      print(st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Phone auth test: $_testPhoneNumber',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              if (_verificationId != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'verificationId captured — SMS should be on its way',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
