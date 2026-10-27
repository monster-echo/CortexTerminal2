import 'package:flutter/material.dart';

import 'auth_form_screen.dart';

/// Independent SMS login route, with its own fields, request state and timer.
class PhoneLoginScreen extends StatelessWidget {
  const PhoneLoginScreen({super.key, this.initialConsent = false});

  final bool initialConsent;

  @override
  Widget build(BuildContext context) =>
      AuthFormScreen(phoneLogin: true, initialConsent: initialConsent);
}
