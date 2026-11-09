import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:trackapp/pages/init_page.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';
import 'package:trackapp/widgets/text_prompt_dialog.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, this.auth});

  final FirebaseAuth? auth;

  @override
  State<AccountPage> createState() => AccountPageState();
}

class AccountPageState extends State<AccountPage> {
  bool _busy = false; //blocks the actions while sign-out/delete is running

  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;

  void showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void navigateToInitPage() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const InitPage()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> disconnectWatches() async {
    final bleService = WatchBleService.instance;
    for (final watch in bleService.watches) {
      if (watch.isConnected) {
        try {
          await bleService.disconnect(watch);
        } catch (_) {
          //sign out even if disconnecting fails
        }
      }
    }
  }

  //session history about students stays on the device, so wipe it
  Future<void> clearLocalData() async {
    AlertManager.instance.reset();
    await LocalStore.instance.clearSessions();
  }

  Future<void> signOut() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await disconnectWatches();
      await clearLocalData();
      await _auth.signOut();
      if (!mounted) return;
      navigateToInitPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar('Sign out failed: $e');
    }
  }

  Future<void> confirmDeleteAccount() async {
    if (_busy) return;

    //confirm first, this can't be undone
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'This permanently deletes your account and all of your data: '
            'your classes, device assignments, and student names.\n\n'
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: appRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    if (proceed != true || !mounted) return;

    //firebase needs a fresh login to delete
    final password = await promptForPassword();
    if (password == null || !mounted) return;

    await deleteAccount(password);
  }

  //null if cancelled
  Future<String?> promptForPassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ConfirmPasswordDialog(),
    );
    if (password == null || password.isEmpty) return null;
    return password;
  }

  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      showSnackBar('No signed-in account.');
      return;
    }

    setState(() => _busy = true);
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      //delete their data first while we can still write it
      await FirebaseDatabase.instance.ref('users/${user.uid}').remove();

      await disconnectWatches();
      await user.delete();
      await clearLocalData();

      if (!mounted) return;
      showSnackBar('Your account has been deleted.');
      navigateToInitPage();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-mismatch') {
        showSnackBar('Incorrect password. Your account was not deleted.');
      } else if (e.code == 'too-many-requests') {
        showSnackBar('Too many attempts. Please try again later.');
      } else {
        showSnackBar('Could not delete account: ${e.code}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar('Could not delete account: $e');
    }
  }

  //saved on the firebase auth profile
  Future<void> editDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final name = await showTextPrompt(
      context,
      title: 'Your name',
      initial: user.displayName,
      hint: 'e.g. Ms. Zhu',
      capitalization: TextCapitalization.words,
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    try {
      await user.updateDisplayName(trimmed);
      await user.reload();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      showSnackBar('Could not save your name: $e');
    }
  }

  //firebase needs a fresh login before changing the password
  Future<void> changePassword() async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      showSnackBar('No signed-in account.');
      return;
    }
    final passwords = await showDialog<({String current, String next})>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (passwords == null || !mounted) return;
    final currentPassword = passwords.current;
    final newPassword = passwords.next;

    setState(() => _busy = true);
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
      if (!mounted) return;
      showSnackBar('Password changed.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      showSnackBar(
        e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'Current password is incorrect. Nothing was changed.'
            : e.code == 'too-many-requests'
                ? 'Too many attempts. Please try again later.'
                : 'Could not change password: ${e.code}',
      );
    } catch (e) {
      if (!mounted) return;
      showSnackBar('Could not change password: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final email = user?.email ?? 'Unknown account';
    final name = user?.displayName?.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: appIndigo.withValues(alpha: 0.12),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: appIndigo,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name == null || name.isEmpty
                                    ? 'Add your name'
                                    : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: name == null || name.isEmpty
                                      ? appMuted
                                      : appInk,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit your name',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: appBlue,
                              onPressed: _busy ? null : editDisplayName,
                            ),
                          ],
                        ),
                        const Text(
                          'Shown to anyone you share a student with',
                          style: TextStyle(
                            color: appMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.mail_outline, color: appMuted),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Signed in with email & password',
                          style: TextStyle(
                            color: appMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: appInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Account actions',
              style: TextStyle(
                color: appBlue,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                children: [
                  _ActionRow(
                    icon: Icons.lock_outline,
                    label: 'Change password',
                    onTap: _busy ? null : changePassword,
                  ),
                  const Divider(height: 1, color: appBorder),
                  _ActionRow(
                    icon: Icons.logout,
                    label: 'Sign out',
                    onTap: _busy ? null : signOut,
                  ),
                  const Divider(height: 1, color: appBorder),
                  _ActionRow(
                    icon: Icons.delete_outline,
                    label: 'Delete account',
                    color: appRed,
                    onTap: _busy ? null : confirmDeleteAccount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Deleting your account permanently removes your classes, '
                'device assignments, and student names.',
                style: TextStyle(color: appMuted, fontSize: 14, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color ?? appBlue),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color ?? appInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: appMuted),
          ],
        ),
      ),
    );
  }
}

class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog();

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For your security, please re-enter your password to delete this account.',
            style: TextStyle(color: appMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _obscure,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock),
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: appRed),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Delete forever'),
        ),
      ],
    );
  }
}

//checks length and match before calling firebase
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = _next.text.length < 6
        ? 'Use at least 6 characters.'
        : _next.text != _again.text
            ? 'The new passwords do not match.'
            : _current.text.isEmpty
                ? 'Enter your current password.'
                : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, (current: _current.text, next: _next.text));
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline),
        );
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: field('Current password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: field('New password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _again,
            obscureText: true,
            decoration: field('New password again'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: appRed)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Change')),
      ],
    );
  }
}
