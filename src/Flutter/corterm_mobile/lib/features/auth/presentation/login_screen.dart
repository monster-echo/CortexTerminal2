import 'package:flutter/material.dart';

import 'auth_form_screen.dart';

/// Password and third-party login entry page. Its form stays mounted while a
/// phone login route is pushed, preserving the user's credentials on return.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const AuthFormScreen(phoneLogin: false);
}
