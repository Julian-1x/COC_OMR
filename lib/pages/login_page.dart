import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omr_app/pages/dashboard_page.dart';
import 'package:omr_app/services/cloud_auth_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:omr_app/services/supabase_sync_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/widgets/app_pin_input.dart';
import 'package:omr_app/widgets/app_primary_button.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/widgets/auth_shell.dart';

enum _AuthMode { login, register }

enum _LoginStage {
  onlineAuth,
  offlinePinSetup,
  offlineUnlock,
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final CloudAuthService _auth = CloudAuthService.instance;
  final LocalAuthService _localAuth = LocalAuthService.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _schoolController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final TextEditingController _unlockPinController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  _LoginStage _stage = _LoginStage.onlineAuth;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  CloudTeacherAccount? _pendingTrustedAccount;
  LocalTeacherProfile? _offlineProfile;
  _PinSetupStep _pinSetupStep = _PinSetupStep.enter;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _schoolController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _unlockPinController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    await _localAuth.lock();

    final offlineProfile = await _localAuth.loadProfile();
    final hasOfflinePin = await _localAuth.hasProfile();
    if (hasOfflinePin && offlineProfile != null) {
      if (mounted) {
        setState(() {
          _offlineProfile = offlineProfile;
          _stage = _LoginStage.offlineUnlock;
          _isLoading = false;
        });
      }
      return;
    }

    if (SupabaseService.client?.auth.currentSession != null) {
      final currentUser = SupabaseService.client?.auth.currentUser;
      final profile = await _localAuth.loadProfile();
      if (profile == null && currentUser != null) {
        final account = await _auth.accountFromCurrentSession();
        if (mounted) {
          setState(() {
            _pendingTrustedAccount = account ??
                CloudTeacherAccount(
                  id: currentUser.id,
                  email: currentUser.email ?? '',
                  name: currentUser.email ?? 'Teacher',
                  isActive: true,
                );
            _stage = _LoginStage.offlinePinSetup;
            _isLoading = false;
          });
        }
        return;
      }
      await LocalDataStore.instance.claimUnownedDataForCurrentTeacher();
      await _pullCloudData(showErrors: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_enterDashboard());
        }
      });
      return;
    }

    if (mounted) {
      setState(() {
        _offlineProfile = offlineProfile;
        _stage = _LoginStage.onlineAuth;
        _isLoading = false;
      });
    }
  }

  Future<void> _pullCloudData({required bool showErrors}) async {
    if (!SupabaseService.isReady) {
      return;
    }

    try {
      await SupabaseSyncService.instance.syncAll();
    } catch (error) {
      if (showErrors && mounted) {
        _showMessage(
          '${UserErrorMessages.friendlySyncError(error)} You can sync later from Settings.',
          isError: true,
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!SupabaseService.isReady) {
      _showMessage(
        'Supabase is not connected. Start the app with your project URL and publishable key.',
        isError: true,
      );
      return;
    }

    final name = _nameController.text.trim();
    final school = _schoolController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final isRegister = _mode == _AuthMode.register;

    if (isRegister && name.isEmpty) {
      _showMessage('Enter the teacher name.', isError: true);
      return;
    }
    if (isRegister && school.isEmpty) {
      _showMessage('Enter the school or department.', isError: true);
      return;
    }
    if (!_isValidEmail(email)) {
      _showMessage('Enter a valid email address.', isError: true);
      return;
    }
    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final account = isRegister
          ? await _auth.registerTeacher(
              name: name,
              email: email,
              password: password,
              school: school,
            )
          : await _auth.signInTeacher(email: email, password: password);

      if (!mounted) {
        return;
      }

      await _pullCloudData(showErrors: true);
      if (!mounted) {
        return;
      }

      final existingProfile = await _localAuth.loadProfile();
      if (existingProfile?.cloudUserId == account.id) {
        setState(() => _isSubmitting = false);
        await _enterDashboard();
        return;
      }

      setState(() {
        _pendingTrustedAccount = account;
        _stage = _LoginStage.offlinePinSetup;
        _pinSetupStep = _PinSetupStep.enter;
        _pinController.clear();
        _confirmPinController.clear();
        _isSubmitting = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showMessage(UserErrorMessages.friendlyError(error), isError: true);
      }
    }
  }

  Future<void> _createOfflinePin() async {
    final account = _pendingTrustedAccount;
    if (account == null) {
      _showMessage(
        'Sign in online before creating offline unlock.',
        isError: true,
      );
      return;
    }

    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      _showMessage('PIN must be 4 to 6 digits.', isError: true);
      return;
    }
    if (pin != confirmPin) {
      _showMessage('PIN confirmation does not match.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _localAuth.trustCloudAccount(
        name: account.name,
        school: _schoolController.text.trim(),
        email: account.email,
        cloudUserId: account.id,
        pin: pin,
      );
      await LocalDataStore.instance.claimUnownedDataForCurrentTeacher();
      await _pullCloudData(showErrors: true);
      if (!mounted) {
        return;
      }
      await _enterDashboard();
    } catch (error) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showMessage(UserErrorMessages.friendlyError(error), isError: true);
      }
    }
  }

  Future<void> _unlockOffline() async {
    if (_isSubmitting) {
      return;
    }

    final pin = _unlockPinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      _showMessage('Enter your full 4-6 digit PIN.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await _localAuth.verifyPin(pin);
    if (!mounted) {
      return;
    }

    if (!result.success) {
      final cooldown = result.cooldownRemaining;
      setState(() => _isSubmitting = false);
      _unlockPinController.clear();
      _showMessage(
        cooldown == null
            ? result.message ?? 'Offline unlock failed.'
            : '${result.message} ${cooldown.inSeconds}s remaining.',
        isError: true,
      );
      return;
    }

    await LocalDataStore.instance.reloadForCurrentTeacher();
    if (!mounted) {
      return;
    }
    await _enterDashboard();
  }

  Future<void> _enterDashboard() async {
    await LocalDataStore.instance.reloadForCurrentTeacher();
    if (!mounted) {
      return;
    }
    _openDashboard();
  }

  void _advancePinSetup() {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      _showMessage('PIN must be 4 to 6 digits.', isError: true);
      return;
    }
    setState(() {
      _pinSetupStep = _PinSetupStep.confirm;
      _confirmPinController.clear();
    });
  }

  void _showOnlineLogin() {
    setState(() {
      _stage = _LoginStage.onlineAuth;
      _isSubmitting = false;
      _unlockPinController.clear();
    });
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  void _openDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (context) => const DashboardPage()),
    );
  }

  void _showMessage(String message, {required bool isError}) {
    final cleanMessage = message.replaceFirst(
      RegExp(r'^(exception|cloudauthexception):\s*', caseSensitive: false),
      '',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cleanMessage),
        backgroundColor: isError ? AppColors.error : AppColors.brandGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool get _isPinStage =>
      _stage == _LoginStage.offlinePinSetup ||
      _stage == _LoginStage.offlineUnlock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.appCanvas,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: const AuthLoadingShell(),
                ),
              )
            : _isPinStage
                ? _buildPinStageLayout()
                : _buildScrollableAuthLayout(),
      ),
    );
  }

  Widget _buildScrollableAuthLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: _buildAuthPanel(),
        ),
      ),
    );
  }

  Widget _buildPinStageLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            children: [
              const CocSealLogo(size: 80),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: SingleChildScrollView(
                  child: _stage == _LoginStage.offlinePinSetup
                      ? _buildPinSetupContent()
                      : _buildOfflineUnlockContent(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _stage == _LoginStage.offlinePinSetup
                  ? _buildPinSetupActions()
                  : _buildOfflineUnlockActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthPanel() {
    switch (_stage) {
      case _LoginStage.offlinePinSetup:
        return _buildPinSetupPanel();
      case _LoginStage.offlineUnlock:
        return _buildOfflineUnlockPanel();
      case _LoginStage.onlineAuth:
        return _buildOnlineAuthPanel();
    }
  }

  Widget _buildOnlineAuthPanel() {
    final isRegister = _mode == _AuthMode.register;

    return AuthShell(
      title: isRegister ? 'Create Teacher Account' : 'Welcome Back',
      subtitle: isRegister
          ? 'Register to sync your classes and scan results to the cloud.'
          : 'Sign in to continue to OMR Hub.',
      badge: SupabaseService.isReady
          ? AuthBadgeType.online
          : AuthBadgeType.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modeSelector(),
          const SizedBox(height: AppSpacing.lg),
          if (!SupabaseService.isReady) ...[
            _statusNote(
              icon: Icons.cloud_off_rounded,
              text:
                  'Cloud sign-in is not configured in this APK. Ask your administrator for a build that includes the school Supabase keys, or reinstall using the official release package.',
              isWarning: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (isRegister) ...[
            _textField(
              controller: _nameController,
              label: 'Teacher Name',
              hint: 'e.g. Maria Santos',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.md),
            _textField(
              controller: _schoolController,
              label: 'School / Department',
              hint: 'e.g. COC - SHS',
              icon: Icons.apartment_rounded,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _emailField(),
          const SizedBox(height: AppSpacing.md),
          _passwordField(),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: isRegister ? 'Create Account' : 'Sign In',
            icon: isRegister
                ? Icons.person_add_alt_1_rounded
                : Icons.login_rounded,
            isLoading: _isSubmitting,
            onPressed: SupabaseService.isReady && !_isSubmitting ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPinSetupPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPinSetupContent(),
        const SizedBox(height: AppSpacing.md),
        _buildPinSetupActions(),
      ],
    );
  }

  Widget _buildPinSetupContent() {
    final account = _pendingTrustedAccount;
    final isConfirm = _pinSetupStep == _PinSetupStep.confirm;

    return AuthShell(
      title: 'Create Offline PIN',
      subtitle: 'Use this PIN on exam days when there is no internet.',
      badge: AuthBadgeType.online,
      showLogo: false,
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account != null)
            _statusNote(
              icon: Icons.verified_user_rounded,
              text: account.email.isEmpty
                  ? 'Your online account is verified.'
                  : 'Trusted account: ${account.email}',
            ),
          if (account != null) const SizedBox(height: AppSpacing.md),
          if (isConfirm)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Re-enter the same PIN to confirm.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.brandMuted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          AppPinInput(
            key: ValueKey(isConfirm ? 'pin-confirm' : 'pin-enter'),
            controller: isConfirm ? _confirmPinController : _pinController,
            label: isConfirm ? 'Confirm PIN' : 'Choose a PIN',
            enabled: !_isSubmitting,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPinSetupActions() {
    final isConfirm = _pinSetupStep == _PinSetupStep.confirm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isConfirm)
          AppPrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: _advancePinSetup,
          )
        else ...[
          AppPrimaryButton(
            label: 'Trust This Device',
            icon: Icons.verified_rounded,
            isLoading: _isSubmitting,
            onPressed: _createOfflinePin,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => setState(() {
                      _pinSetupStep = _PinSetupStep.enter;
                      _confirmPinController.clear();
                    }),
            child: const Text('Change PIN'),
          ),
        ],
      ],
    );
  }

  Widget _buildOfflineUnlockPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildOfflineUnlockContent(),
        const SizedBox(height: AppSpacing.md),
        _buildOfflineUnlockActions(),
      ],
    );
  }

  Widget _buildOfflineUnlockContent() {
    final profile = _offlineProfile;

    return AuthShell(
      title: 'Enter your PIN',
      subtitle: 'Unlock this trusted device without Wi‑Fi.',
      teacherName: profile?.name,
      schoolName: profile?.school,
      badge: AuthBadgeType.offline,
      showLogo: false,
      compact: true,
      child: AppPinInput(
        key: const ValueKey('pin-unlock'),
        controller: _unlockPinController,
        label: 'Offline PIN',
        enabled: !_isSubmitting,
        compact: true,
      ),
    );
  }

  Widget _buildOfflineUnlockActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPrimaryButton(
          label: 'Unlock',
          icon: Icons.lock_open_rounded,
          isLoading: _isSubmitting,
          onPressed: _unlockOffline,
        ),
        if (SupabaseService.isReady) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _showOnlineLogin,
              child: const Text('Use online login'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _modeSelector() {
    return Row(
      children: [
        Expanded(
          child: _modeButton(
            label: 'Login',
            icon: Icons.login_rounded,
            selected: _mode == _AuthMode.login,
            onTap: () => setState(() => _mode = _AuthMode.login),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _modeButton(
            label: 'Register',
            icon: Icons.person_add_alt_1_rounded,
            selected: _mode == _AuthMode.register,
            onTap: () => setState(() => _mode = _AuthMode.register),
          ),
        ),
      ],
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? AppColors.brandGreen.withValues(alpha: 0.12)
          : Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: _isSubmitting ? null : onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          height: AppSpacing.touchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected ? AppColors.brandGreen : AppColors.borderSubtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.brandGreen : AppColors.brandMuted,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.brandGreen : AppColors.brandMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          decoration: _inputDecoration(hint: hint, icon: icon),
        ),
      ],
    );
  }

  Widget _emailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Email'),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: _inputDecoration(
            hint: 'teacher@example.com',
            icon: Icons.email_outlined,
          ),
        ),
      ],
    );
  }

  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Password'),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          onSubmitted: (_) => _isSubmitting ? null : _submit(),
          autofillHints: const [AutofillHints.password],
          decoration: _inputDecoration(
            hint: 'At least 6 characters',
            icon: Icons.password_rounded,
          ).copyWith(
            suffixIcon: IconButton(
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.brandText,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.brandMuted),
      filled: true,
      fillColor: AppColors.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: const BorderSide(color: AppColors.brandGreen, width: 2),
      ),
    );
  }

  Widget _statusNote({
    required IconData icon,
    required String text,
    bool isWarning = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.warningBg : AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isWarning ? AppColors.warningBorder : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: isWarning ? AppColors.warningAccent : AppColors.brandMuted,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isWarning ? AppColors.warningText : AppColors.brandMuted,
                height: 1.4,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PinSetupStep { enter, confirm }
