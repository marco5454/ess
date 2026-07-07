import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/theme/chapel_icon.dart';
import '../../../../core/theme/chapel_theme.dart';

/// Login screen for the bishopric tracker.
///
/// Presents the branding on a cream background with a chapel-book icon
/// hero, then a compact card containing the email/password form. Router
/// redirect handles the transition on success.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BrandingHero(),
                  const SizedBox(height: 28),
                  _SignInCard(
                    emailController: _emailController,
                    passwordController: _passwordController,
                    isSubmitting: _isSubmitting,
                    onSignIn: _signIn,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandingHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: ChapelPalette.navy,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Center(child: ChapelIcon(size: 56)),
        ),
        const SizedBox(height: 20),
        Text(
          'Bishopric Tracker',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: ChapelPalette.navyDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Members and callings, kept together',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ChapelPalette.inkSoft,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({
    required this.emailController,
    required this.passwordController,
    required this.isSubmitting,
    required this.onSignIn,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isSubmitting;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              enabled: !isSubmitting,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passwordController,
              enabled: !isSubmitting,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => onSignIn(),
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: isSubmitting ? null : onSignIn,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
