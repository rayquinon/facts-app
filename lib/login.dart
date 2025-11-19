// login.dart
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // Not needed; removed
// Navigation destinations are registered via named routes in `app_routes.dart`.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_routes.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _lastFetchedUid;
  String? _lastFetchedRole;

  static const String _hardcodedAdminEmail = 'admin@gmail.com';
  static const String _hardcodedAdminPassword = 'admin123';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      // Check if already loading to prevent double-submission on Enter key
      if (_isLoading) return; 

      setState(() {
        _isLoading = true;
      });

      try {
        final String email = _emailController.text.trim();
        final String password = _passwordController.text.trim();
        final bool isHardcodedAdmin =
            email.toLowerCase() == _hardcodedAdminEmail && password == _hardcodedAdminPassword;

        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final uid = cred.user?.uid;
        if (uid == null) throw Exception('Failed to obtain user id after login');

        if (isHardcodedAdmin) {
          if (mounted) {
            setState(() {
              _lastFetchedUid = uid;
              _lastFetchedRole = 'admin';
            });
            Navigator.pushReplacementNamed(context, AppRoutes.adminPage);
          }
          return;
        }

        // Fetch user profile from Firestore to determine role
        DocumentSnapshot<Map<String, dynamic>>? userDoc;
        Map<String, dynamic>? data;
        try {
          userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          data = userDoc.data();
        } on FirebaseException catch (e) {
          debugPrint('Firestore server read failed: ${e.code} ${e.message}');
          // If Firestore is offline, try reading from local cache
          if (e.code == 'unavailable') {
            try {
              userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get(const GetOptions(source: Source.cache));
              data = userDoc.data();
              debugPrint('Loaded user doc from cache for $uid');
            } catch (e2) {
              debugPrint('Cache read also failed: $e2');
              // Offer the user a choice to retry or continue to complete profile
              if (mounted) {
                final choice = await showDialog<String>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Offline'),
                    content: const Text('Unable to reach Firestore and no cached profile found. Retry or complete your profile manually?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, 'retry'), child: const Text('Retry')),
                      TextButton(onPressed: () => Navigator.pop(c, 'complete'), child: const Text('Complete Profile')),
                    ],
                  ),
                );
                if (choice == 'retry') {
                  // try server once more (will throw to outer catch if fails)
                  userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                  data = userDoc.data();
                } else if (choice == 'complete') {
                  if (!mounted) return;
                  Navigator.pushReplacementNamed(context, AppRoutes.userTypeSelector);
                  return;
                } else {
                  return;
                }
              } else {
                return;
              }
            }
          } else {
            rethrow;
          }
        }
        final role = (data != null && data['userType'] != null) ? data['userType'].toString().toLowerCase() : null;

        // Save debug info
        setState(() {
          _lastFetchedUid = uid;
          _lastFetchedRole = role;
        });

        if (!mounted) return;

        if (role == null || role.isEmpty) {
          // Offer a path to complete profile if userType is missing
          if (mounted) {
            final choice = await showDialog<String>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Account Role Missing'),
                content: const Text('Your account does not have a defined role (userType). You can complete your profile now or contact the administrator.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, 'admin'), child: const Text('Contact Admin')),
                  TextButton(onPressed: () => Navigator.pop(c, 'complete'), child: const Text('Complete Profile')),
                ],
              ),
            );

            if (choice == 'complete') {
              // Send the user to the type selector to finish onboarding
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, AppRoutes.userTypeSelector);
            }
          }
          return;
        }

        // Route based on declared role
        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, AppRoutes.adminPage);
        } else if (role == 'student') {
          Navigator.pushReplacementNamed(context, AppRoutes.studentHome);
        } else if (role == 'instructor') {
          Navigator.pushReplacementNamed(context, AppRoutes.instructorHome);
        } else {
          // Unknown role: offer to complete profile or contact admin
          if (mounted) {
            final choice = await showDialog<String>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Unknown Account Role'),
                content: Text('Your account role "$role" is not recognized. You can complete your profile or contact the administrator.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, 'admin'), child: const Text('Contact Admin')),
                  TextButton(onPressed: () => Navigator.pop(c, 'complete'), child: const Text('Complete Profile')),
                ],
              ),
            );

            if (choice == 'complete') {
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, AppRoutes.userTypeSelector);
            }
          }
          return;
        }
      } on FirebaseAuthException catch (e) {
        String message;
        if (e.code == 'user-not-found') {
          message = 'No user found for that email.';
        } else if (e.code == 'wrong-password') {
          message = 'Wrong password provided.';
        } else if (e.code == 'invalid-email') {
          message = 'The email address is not valid.';
          } else {
          message = 'An error occurred. Please try again.';
          debugPrint(e.message ?? e.toString());
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        // Log the unexpected error for debugging and show a helpful message.
        debugPrint('Unexpected login error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('An unexpected error occurred: ${e.toString()}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FATCS Login'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              // Wrapper to allow 'Enter' key press to trigger the login function
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (ActivateIntent intent) => _login(),
                  ),
                },
                child: FocusTraversalGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Email Text Field
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next, // Moves focus to the next field
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16.0),

                      // Password Text Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                        textInputAction: TextInputAction.done, // Signals this is the last input field
                        onFieldSubmitted: (value) => _login(), // Submits on 'Done'/'Go' on mobile keyboard
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters long';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24.0),

                      // Login Button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text('Login'),
                      ),

                      const SizedBox(height: 8.0),
                      // Debug button: shows last fetched uid and role (useful during testing)
                      TextButton(
                        onPressed: (_lastFetchedUid == null && _lastFetchedRole == null)
                            ? null
                            : () {
                                showDialog<void>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Debug Info'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('UID: ${_lastFetchedUid ?? 'n/a'}'),
                                        const SizedBox(height: 8),
                                        Text('userType: ${_lastFetchedRole ?? 'n/a'}'),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
                                    ],
                                  ),
                                );
                              },
                        child: const Text('Show debug info'),
                      ),

                      const SizedBox(height: 16.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account?"),
                          TextButton(
                            onPressed: () {
                              // Navigate to the User Type Selector page
                              Navigator.pushNamed(context, AppRoutes.userTypeSelector);
                            },
                            child: const Text('Sign Up'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Admin user document creation function (for testing purposes)
Future<void> createAdminUserDoc() async {
  try {
    // Get the current user
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      print('No user is currently logged in.');
      return;
    }

    // Reference to the Firestore document
    DocumentReference userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

    // Check if the document already exists
    DocumentSnapshot docSnapshot = await userDoc.get();
    if (docSnapshot.exists) {
      print('User document already exists.');
      return;
    }

    // Create the document with required fields
    await userDoc.set({
      'userType': 'admin',
      'name': user.displayName ?? 'Admin Name',
      'email': user.email ?? 'admin@example.com',
    });

    print('Admin user document created successfully.');
  } catch (e) {
    print('Error creating admin user document: $e');
  }
}