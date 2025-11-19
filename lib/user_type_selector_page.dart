// user_type_selector_page.dart - FIXED

import 'package:flutter/material.dart';
import 'app_routes.dart';

class UserTypeSelectorPage extends StatelessWidget {
  const UserTypeSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Account Type'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Are you a Student or an Instructor?',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Instructor Button
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.instructorRegister);
                  },
                  icon: const Icon(Icons.work_outline, size: 28),
                  label: const Text('I am an Instructor',
                      style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 24),

                // Student Button - FIX APPLIED HERE
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.studentRegister);
                  },
                  icon: const Icon(Icons.school_outlined, size: 28),
                  label:
                      const Text('I am a Student', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 48),

                // Back to Login Button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel and Return to Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}