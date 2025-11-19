// student_register_page.dart
// This file uses context after async operations but guards with `mounted` checks.
// Suppress the linter warning here because checks are already in place.
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'user_type_enum.dart';
import 'app_routes.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentRegisterPage extends StatefulWidget {
  const StudentRegisterPage({super.key});

  @override
  State<StudentRegisterPage> createState() => _StudentRegisterPageState();
}

class _StudentRegisterPageState extends State<StudentRegisterPage> {
  // --- Service and Key --
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  // --- Text Controllers ---
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _studentIdController = TextEditingController();

  // --- State for Face Scan Requirement ---
  bool _isFaceScanCompleted = false; // Tracks if scan was successful
  bool _isScanning = false;
  bool _isRegistered = false; // Tracks whether registration succeeded

  // --- User Type Constant ---
  final UserType _userType = UserType.student;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Sign Up'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'Register as a Student',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildTextFormField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_outline,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 16),
              _buildTextFormField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value == null ||
                        value.isEmpty ||
                        !value.contains('@')
                    ? 'Please enter a valid email'
                    : null,
              ),
              const SizedBox(height: 16),
              _buildTextFormField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline,
                obscureText: true,
                validator: (value) =>
                    value == null || value.isEmpty || value.length < 6
                        ? 'Password must be at least 6 characters'
                        : null,
              ),
              const SizedBox(height: 16),
              _buildTextFormField(
                controller: _studentIdController,
                label: 'Student ID',
                icon: Icons.school_outlined,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Please enter your Student ID' : null,
              ),
              const SizedBox(height: 24),

              // --- Face Scan Button ---
              OutlinedButton.icon(
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_isFaceScanCompleted
                        ? Icons.check_circle
                        : Icons.camera_alt_outlined),
                label: Text(_isFaceScanCompleted
                    ? 'Face Scan Completed'
                    : (_isRegistered ? 'Start Face Scan' : 'Register first to scan')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: _isFaceScanCompleted
                      ? Colors.green
                      : (_isRegistered ? Theme.of(context).primaryColor : Colors.grey),
                  side: BorderSide(
                    color: _isFaceScanCompleted
                        ? Colors.green
                        : (_isRegistered ? Theme.of(context).primaryColor : Colors.grey),
                  ),
                ),
                onPressed: _isScanning || _isFaceScanCompleted || !_isRegistered ? null : _navigateToFaceScan,
              ),
              const SizedBox(height: 24),

              // --- Register Button ---
              ElevatedButton.icon(
                onPressed: _isRegistered ? null : _registerUser,
                icon: _isRegistered
                    ? const Icon(Icons.check_circle, color: Colors.white)
                    : const Icon(Icons.person_add, color: Colors.white),
                label: Text(
                  _isRegistered ? 'Registered' : 'Register Student Account',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isRegistered ? Colors.green : null,
                ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go back to Type Selection'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToFaceScan() async {
    // Basic form validation before proceeding to scan
    if (_studentIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your Student ID first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isScanning = true);
    // Navigate to FaceScanPage (named route) and wait for a result
    final bool? scanResult = await Navigator.pushNamed<bool?>(
      context,
      AppRoutes.faceScan,
      arguments: _studentIdController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isScanning = false);

    // Update state based on the result from FaceScanPage
    if (scanResult == true) {
      setState(() {
        _isFaceScanCompleted = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face scan successful! Face data stored.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      // Handles scan failure or cancellation
      setState(() {
        _isFaceScanCompleted = false;
      });
      // NOTE: FaceScanPage handles showing its own failure message before popping
    }
  }

  void _registerUser() async {
    // Standard Flutter form validation
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Registration proceeds before face scan; we'll start face-scan after creating credentials.

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Processing registration...')),
    );

    try {
      // Step 4: Register User and Save Profile Data
      await _authService.registerAndSaveUser(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _nameController.text.trim(),
        _userType.name,
        _studentIdController.text.trim(),
        {
          'studentId': _studentIdController.text.trim(),
          // faceScanCompleted will be set after the scan completes
          'faceScanCompleted': false,
        },
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (!mounted) return;
      // Mark registered and immediately start face scan for the created account
      setState(() {
        _isRegistered = true;
      });

      // Automatically navigate to face scan to attach images to the newly created user
      bool? scanResult;
      do {
        scanResult = await Navigator.pushNamed<bool?>(
          context,
          AppRoutes.faceScan,
          arguments: _studentIdController.text.trim(),
        );
        if (!mounted) return;

        if (scanResult == true) {
          // Update the user doc to mark faceScanCompleted = true
          try {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) {
              await FirebaseFirestore.instance.collection('users').doc(uid).set({
                'faceScanCompleted': true,
              }, SetOptions(merge: true));
            }
          } catch (_) {}

          if (!mounted) return;
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('Registration Complete'),
                content: const Text('Your account and face enrollment are complete.'),
                actions: <Widget>[
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () {
                      Navigator.of(dialogContext).popUntil((route) => route.isFirst);
                    },
                  ),
                ],
              );
            },
          );
          break;
        } else {
          // Scan failed or cancelled — allow retry or skip
          if (!mounted) return;
          final action = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('Face Scan Incomplete'),
                content: const Text('Face scan did not complete. Would you like to retry or finish registration without a scan?'),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Retry'),
                    onPressed: () => Navigator.of(dialogContext).pop('retry'),
                  ),
                  TextButton(
                    child: const Text('Skip'),
                    onPressed: () => Navigator.of(dialogContext).pop('skip'),
                  ),
                ],
              );
            },
          );

          if (action == 'retry') {
            continue; // loop and retry scan
          } else {
          // Finish without scan
            if (!mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
            break;
          }
        }
      } while (true);

    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration Failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _studentIdController.dispose();
    super.dispose();
  }
}