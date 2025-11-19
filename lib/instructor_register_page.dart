// instructor_register_page.dart
// Ignore build-context-synchronously warnings in this registration flow where
// we carefully check `mounted` before using `context` after awaits.
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'auth_service.dart'; // Handles Firebase Auth and Firestore write (You must have this file)
import 'user_type_enum.dart'; // Imports the separated UserType enum (You must have this file)

class InstructorRegisterPage extends StatefulWidget {
  const InstructorRegisterPage({super.key});

  @override
  State<InstructorRegisterPage> createState() => _InstructorRegisterPageState();
}

class _InstructorRegisterPageState extends State<InstructorRegisterPage> {
  // --- Service and Key ---
  // Ensure you have an AuthService class with a registerAndSaveUser method
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  // --- Text Controllers ---
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // A variable to hold the selected dropdown value
  String? _selectedDepartment;

  // A list to hold the dropdown options
  final List<String> _departmentOptions = [
    'Department of Food Processing and Technology',
    'Department of Technology Livelihood and Education',
    'Department of Information Technology',
  ];

  // --- User Type Constant ---
  final UserType _userType = UserType.instructor; // Fixed type for this page

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instructor Sign Up'),
        // Added Back button to the Selector Page
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
                'Register as an Instructor',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // --- Common Fields ---
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

              // --- Department Dropdown ---
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                hint: const Text('Select Department'),
                decoration: const InputDecoration(
                  labelText: 'Department',
                  prefixIcon: Icon(Icons.business_outlined),
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: _departmentOptions.map((String department) {
                  return DropdownMenuItem<String>(
                    value: department,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(department),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedDepartment = newValue;
                  });
                },
                validator: (value) =>
                    value == null || value.isEmpty ? 'Please select a department' : null,
              ),
              const SizedBox(height: 32),

              // --- Primary Action Button ---
              ElevatedButton(
                onPressed: _registerUser,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Register Instructor Account',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 16),

              // --- Secondary Action Button (Return to Selector) ---
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

  /// Handles the registration logic by calling the AuthService
  void _registerUser() async {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Processing registration...')),
      );

      try {
        await _authService.registerAndSaveUser(
          _emailController.text.trim(),
          _passwordController.text.trim(),
          _nameController.text.trim(),
          _userType.name, // 'instructor'
          _selectedDepartment!,
          {
            'department': _selectedDepartment!,
          },
        );

        // --- MODIFICATION: Replaced SnackBar with an AlertDialog ---
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // Check if the widget is still mounted before showing a dialog
        if (!mounted) return;

        // Show the success dialog
        await showDialog(
          context: context,
          barrierDismissible: false, // User must press OK
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Registration Successful'),
              content: const Text('Your instructor account has been created.'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    // This will pop the dialog AND all pages
                    // until it gets back to the first route (login.dart)
                    Navigator.of(dialogContext).popUntil((route) => route.isFirst);
                  },
                ),
              ],
            );
          },
        );
        // --- END MODIFICATION ---

        // (Original SnackBar and Navigator.popUntil were here)

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
  }

  // Dispose controllers to prevent memory leaks
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}