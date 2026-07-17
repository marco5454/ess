import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/legal/legal_text.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/chapel_icon.dart';
import '../../../../core/theme/chapel_theme.dart';
import '../../../audit/presentation/providers/audit_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../providers/auth_repository_provider.dart';

/// Login screen for the bishopric tracker.
///
/// Two modes on the same screen, selected by a `SegmentedButton`:
///   - Sign in — email + password.
///   - Create account — email + password + invite code. Invite codes are
///     issued from the admin invite-codes screen; there is no open sign-up.
///
/// Router redirect handles the transition on success.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _AuthMode { signIn, signUp }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    if (_isSubmitting || mode == _mode) return;
    setState(() => _mode = mode);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_mode == _AuthMode.signIn) {
      await _signIn();
    } else {
      await _signUp();
    }
  }

  Future<void> _signIn() async {
    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final audit = ref.read(auditRepositoryProvider);
    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Best-effort audit; swallowed inside the repo on failure.
      await audit.logAuthEvent('user.signin');
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final code = _inviteCodeController.text.trim().toUpperCase();

    // Client-side sanity checks so we don't burn a round-trip on obvious
    // input errors.
    if (email.isEmpty || password.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email, password, and invite code.'),
        ),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.signUpWithInvite(
        email: email,
        password: password,
        inviteCode: code,
      );
      // Success — the auth state stream will flip the router to authed.
    } on SignUpFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_messageFor(e))));
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-up failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _messageFor(SignUpFailure e) {
    switch (e.kind) {
      case SignUpFailureKind.inviteInvalid:
        return 'That invite code is not valid. Ask an admin for a new one.';
      case SignUpFailureKind.emailInUse:
        return 'That email is already registered. Try signing in.';
      case SignUpFailureKind.weakPassword:
        return 'That password is too weak. Try a longer one.';
      case SignUpFailureKind.inviteConsumeRaced:
        // The account was created but the code wasn't consumed. The user
        // is signed in; router will move them on. Show a warning so an
        // admin can clean up if needed.
        return 'Account created, but the invite code could not be marked '
            'used. Contact an admin.';
      case SignUpFailureKind.other:
        return 'Sign-up failed: ${e.cause ?? 'unknown error'}';
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
                  _AuthCard(
                    mode: _mode,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    inviteCodeController: _inviteCodeController,
                    isSubmitting: _isSubmitting,
                    onModeChanged: _setMode,
                    onSubmit: _submit,
                  ),
                  const SizedBox(height: 24),
                  const _DisclaimerFooter(),
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

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.mode,
    required this.emailController,
    required this.passwordController,
    required this.inviteCodeController,
    required this.isSubmitting,
    required this.onModeChanged,
    required this.onSubmit,
  });

  final _AuthMode mode;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController inviteCodeController;
  final bool isSubmitting;
  final ValueChanged<_AuthMode> onModeChanged;
  final VoidCallback onSubmit;

  bool get _isSignUp => mode == _AuthMode.signUp;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<_AuthMode>(
              segments: const [
                ButtonSegment(
                  value: _AuthMode.signIn,
                  label: Text('Sign in'),
                  icon: Icon(Icons.login),
                ),
                ButtonSegment(
                  value: _AuthMode.signUp,
                  label: Text('Create account'),
                  icon: Icon(Icons.person_add_alt),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onModeChanged(s.first),
            ),
            const SizedBox(height: 18),
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
              autofillHints: _isSignUp
                  ? const [AutofillHints.newPassword]
                  : const [AutofillHints.password],
              onSubmitted: _isSignUp ? null : (_) => onSubmit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: _isSignUp ? 'At least 6 characters.' : null,
              ),
            ),
            if (_isSignUp) ...[
              const SizedBox(height: 14),
              TextField(
                controller: inviteCodeController,
                enabled: !isSubmitting,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  labelText: 'Invite code',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                  helperText: 'Ask an admin for a code.',
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: isSubmitting ? null : onSubmit,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isSignUp ? 'Create account' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fine-print footer shown below the sign-in card. Communicates the
/// unaffiliation notice at a glance and links to the full About / legal
/// screen for the complete disclaimer, privacy note, and no-warranty
/// clause.
class _DisclaimerFooter extends StatelessWidget {
  const _DisclaimerFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: ChapelPalette.inkSoft,
      height: 1.4,
    );
    return Column(
      children: [
        Text(
          LegalText.shortUnaffiliation,
          textAlign: TextAlign.center,
          style: baseStyle,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.push(AppRoutes.about),
          style: TextButton.styleFrom(
            foregroundColor: ChapelPalette.navy,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('About & disclaimer'),
        ),
      ],
    );
  }
}
