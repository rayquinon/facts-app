// student_register_page.dart
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'user_type_enum.dart';
import 'face_scan_page.dart'; // NEW: Import the dedicated scan page

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
                    : 'Start Face Scan'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor:
                      _isFaceScanCompleted ? Colors.green : Theme.of(context).primaryColor,
                  side: BorderSide(
                    color: _isFaceScanCompleted
                        ? Colors.green
                        : Theme.of(context).primaryColor,
                  ),
                ),
                onPressed: _isScanning || _isFaceScanCompleted ? null : _navigateToFaceScan,
              ),
              const SizedBox(height: 24),

              // --- Register Button ---
              ElevatedButton(
                onPressed: _registerUser,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Register Student Account',
                  style: TextStyle(fontSize: 16),
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
    // Navigate to FaceScanPage and wait for a result
    final bool? scanResult = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FaceScanPage(userIdentifier: _studentIdController.text.trim())),
    );
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

    // Custom check for face scan completion
    if (!_isFaceScanCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please complete the face scan before registering.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Processing registration...')),
    );

    try {
      // Step 4: Register User and Save Profile Data (after face data is already stored)
      await _authService.registerAndSaveUser(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _nameController.text.trim(),
        _userType.name,
        _studentIdController.text.trim(),
        {
          'studentId': _studentIdController.text.trim(),
          'faceScanCompleted': true,
        },
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (!mounted) return;

      // --- START MODIFICATION ---
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Registration Successful'),
            content: const Text('Your student account has been created.'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  // Pop all pages
                  // until it gets back to the first route (login.dart)
                  Navigator.of(dialogContext).popUntil((route) => route.isFirst);
                },
              ),
            ],
          );
        },
      );
      // --- END MODIFICATION ---

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