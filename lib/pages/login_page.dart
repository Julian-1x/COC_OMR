import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/pages/dashboard_page.dart';
import 'package:omr_app/pages/welcome_onboarding_page.dart';
import 'package:omr_app/services/cloud_auth_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/onboarding_preferences_service.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:omr_app/services/supabase_sync_service.dart';
import 'package:omr_app/services/teacher_pin_sync_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/widgets/app_pin_input.dart';
import 'package:omr_app/widgets/app_primary_button.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/widgets/auth_shell.dart';

enum _AuthMode { login, register }

enum _LoginStage {
  onlineAuth,
  awaitingEmailConfirmation,
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
  final TextEditingController _unlockPinController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  _LoginStage _stage = _LoginStage.onlineAuth;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  CloudTeacherAccount? _pendingTrustedAccount;
  LocalTeacherProfile? _offlineProfile;
  bool _isNewRegistration = false;
  bool _restoredPinFromCloud = false;
  bool _confirmedEmailThisSession = false;
  String? _pendingConfirmationEmail;
  bool _isDeviceOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<Uri>? _authLinkSub;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapAuth());
    unawaited(_initConnectivity());
  }

  Future<void> _bootstrapAuth() async {
    await _restoreSession();
    await _initAuthDeepLinks();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _authLinkSub?.cancel();
    _nameController.dispose();
    _schoolController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _unlockPinController.dispose();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    if (mounted) {
      setState(() => _isDeviceOnline = _hasNetworkConnection(initial));
    }

    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      if (!mounted) {
        return;
      }
      final wasOffline = !_isDeviceOnline;
      final isOnline = _hasNetworkConnection(results);
      setState(() => _isDeviceOnline = isOnline);
      if (wasOffline &&
          isOnline &&
          _stage == _LoginStage.offlineUnlock &&
          !_isLoading) {
        _showMessage(
          'You\'re back online. After unlock, open Settings and tap Sync now to upload your work.',
          isError: false,
        );
      }
    });
  }

  bool _hasNetworkConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> _initAuthDeepLinks() async {
    if (!SupabaseService.isReady) {
      return;
    }

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handleAuthDeepLink(initial);
      }
    } catch (error) {
      debugPrint('Auth deep link (initial) failed: $error');
    }

    _authLinkSub = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleAuthDeepLink(uri)),
      onError: (Object error) {
        debugPrint('Auth deep link stream failed: $error');
      },
    );
  }

  bool _isAuthCallbackUri(Uri uri) {
    return uri.scheme == 'edu.coc.omr' && uri.host == 'login-callback';
  }

  Future<void> _handleAuthDeepLink(Uri uri) async {
    if (!mounted || !SupabaseService.isReady || !_isAuthCallbackUri(uri)) {
      return;
    }

    final client = SupabaseService.client;
    if (client == null) {
      return;
    }

    try {
      await client.auth.getSessionFromUrl(uri);
      if (!mounted) {
        return;
      }
      _confirmedEmailThisSession = true;
      await _continueWithActiveSession(
        fromEmailConfirmation: true,
        isNewRegistration: _isNewRegistration,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        UserErrorMessages.friendlyError(error),
        isError: true,
      );
    }
  }

  Future<void> _continueWithActiveSession({
    bool fromEmailConfirmation = false,
    bool isNewRegistration = false,
  }) async {
    if (SupabaseService.client?.auth.currentSession == null) {
      return;
    }

    final currentUser = SupabaseService.client?.auth.currentUser;
    final profile = await _localAuth.loadProfile();
    if (profile == null && currentUser != null) {
      final account = await _auth.accountFromCurrentSession();
      final resolvedAccount = account ??
          CloudTeacherAccount(
            id: currentUser.id,
            email: currentUser.email ?? '',
            name: currentUser.email ?? 'Teacher',
            isActive: true,
          );
      if (await _tryRestoreCloudPinProfile(resolvedAccount)) {
        if (mounted) {
          setState(() => _isLoading = false);
          if (fromEmailConfirmation) {
            _showMessage(
              'Email confirmed! Enter your PIN to open the dashboard.',
              isError: false,
            );
          }
          await _goToOfflineUnlock(restoredFromCloud: true);
        }
        return;
      }
      if (mounted) {
        if (fromEmailConfirmation) {
          _showMessage(
            'Email confirmed! Create your PIN — then you\'re in.',
            isError: false,
          );
        }
        setState(() {
          _pendingTrustedAccount = resolvedAccount;
          _isNewRegistration = isNewRegistration || _isNewRegistration;
          _restoredPinFromCloud = false;
          _stage = _LoginStage.offlinePinSetup;
          _isLoading = false;
          _isSubmitting = false;
        });
      }
      return;
    }

    await LocalDataStore.instance.claimUnownedDataForCurrentTeacher();
    await _pullCloudData(showErrors: fromEmailConfirmation);
    await _syncPinToCloudIfNeeded();
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = false);
    if (fromEmailConfirmation) {
      _showMessage('Email confirmed! Opening your dashboard…', isError: false);
    }
    unawaited(_enterAppAfterAuth(showWelcome: false));
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
      await _continueWithActiveSession();
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
      if (isRegister) {
        final registration = await _auth.registerTeacher(
          name: name,
          email: email,
          password: password,
          school: school,
        );

        if (!mounted) {
          return;
        }

        if (registration.needsEmailConfirmation) {
          setState(() {
            _isSubmitting = false;
            _isNewRegistration = true;
            _pendingConfirmationEmail =
                registration.pendingEmail ?? email.trim().toLowerCase();
            _stage = _LoginStage.awaitingEmailConfirmation;
          });
          return;
        }

        final account = registration.account;
        if (account == null) {
          throw const CloudAuthException(
            'Registration did not finish. Try again.',
          );
        }

        await _pullCloudData(showErrors: true);
        if (!mounted) {
          return;
        }

        setState(() => _isSubmitting = false);
        await _routeAfterOnlineAuth(account, isNewRegistration: true);
        return;
      }

      final account = await _auth.signInTeacher(email: email, password: password);

      if (!mounted) {
        return;
      }

      await _pullCloudData(showErrors: true);
      if (!mounted) {
        return;
      }

      setState(() => _isSubmitting = false);
      await _routeAfterOnlineAuth(account, isNewRegistration: false);
    } catch (error) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showMessage(UserErrorMessages.friendlyError(error), isError: true);
      }
    }
  }

  Future<void> _createOfflinePin(String pin) async {
    final account = _pendingTrustedAccount;
    if (account == null) {
      _showMessage(
        'Sign in with your email first, then create a PIN.',
        isError: true,
      );
      return;
    }

    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      _showMessage('PIN must be 4 to 6 digits.', isError: true);
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
      final credentials = await _localAuth.storedPinCredentials();
      var cloudBackupOk = false;
      if (credentials != null) {
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            await TeacherPinSyncService.instance.uploadPin(
              pinHash: credentials.hash,
              pinSalt: credentials.salt,
            );
            cloudBackupOk = true;
            break;
          } catch (error) {
            if (attempt == 1 && mounted) {
              final message = error is PinSyncException
                  ? error.message
                  : 'PIN saved on this phone, but cloud backup failed. '
                      'Stay on Wi‑Fi — open Settings after login to retry backup.';
              _showMessage(message, isError: true);
            }
            if (attempt == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 800));
            }
          }
        }
      }
      await LocalDataStore.instance.claimUnownedDataForCurrentTeacher();
      await _pullCloudData(showErrors: true);
      if (!mounted) {
        return;
      }
      if (cloudBackupOk && mounted) {
        _showMessage(
          'PIN saved. You can use it on this phone and restore it after reinstall or on a new phone.',
          isError: false,
        );
      }
      await _enterAppAfterAuth(
        showWelcome: _isNewRegistration && !_confirmedEmailThisSession,
      );
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
            ? result.message ?? 'PIN unlock failed.'
            : '${result.message} ${cooldown.inSeconds}s remaining.',
        isError: true,
      );
      return;
    }

    await LocalDataStore.instance.claimUnownedDataForCurrentTeacher();
    await LocalDataStore.instance.reloadForCurrentTeacher();
    await _syncPinToCloudIfNeeded();
    if (!mounted) {
      return;
    }
    await _enterDashboard();
  }

  Future<void> _routeAfterOnlineAuth(
    CloudTeacherAccount account, {
    required bool isNewRegistration,
  }) async {
    final existingProfile = await _localAuth.loadProfile();
    if (existingProfile?.cloudUserId == account.id &&
        await _localAuth.hasProfile()) {
      await _syncPinToCloudIfNeeded();
      await _enterAppAfterAuth(showWelcome: isNewRegistration);
      return;
    }

    if (await _tryRestoreCloudPinProfile(account)) {
      await _goToOfflineUnlock(restoredFromCloud: true);
      return;
    }

    setState(() {
      _pendingTrustedAccount = account;
      _isNewRegistration = isNewRegistration;
      _restoredPinFromCloud = false;
      _stage = _LoginStage.offlinePinSetup;
    });
  }

  Future<bool> _tryRestoreCloudPinProfile(CloudTeacherAccount account) async {
    if (!SupabaseService.hasActiveSession) {
      return false;
    }

    final cloudPin = await TeacherPinSyncService.instance.fetchForCurrentUser();
    if (cloudPin == null) {
      return false;
    }

    await _localAuth.installCloudProfile(
      name: cloudPin.name.isNotEmpty ? cloudPin.name : account.name,
      school: cloudPin.school ?? _schoolController.text.trim(),
      pinHash: cloudPin.pinHash,
      pinSalt: cloudPin.pinSalt,
      email: cloudPin.email ?? account.email,
      cloudUserId: cloudPin.cloudUserId ?? account.id,
    );
    return true;
  }

  Future<void> _goToOfflineUnlock({required bool restoredFromCloud}) async {
    final profile = await _localAuth.loadProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      _offlineProfile = profile;
      _restoredPinFromCloud = restoredFromCloud;
      _stage = _LoginStage.offlineUnlock;
      _unlockPinController.clear();
      _isSubmitting = false;
    });
  }

  Future<void> _syncPinToCloudIfNeeded() async {
    await TeacherPinSyncService.instance.syncLocalPinIfMissing(
      readLocal: _localAuth.storedPinCredentials,
    );
  }

  Future<void> _enterAppAfterAuth({bool showWelcome = false}) async {
    await LocalDataStore.instance.reloadForCurrentTeacher();
    if (!mounted) {
      return;
    }

    final completed = await OnboardingPreferencesService.hasCompletedOnboarding();
    if (!showWelcome && completed) {
      _openDashboard();
      return;
    }

    final profile = await _localAuth.loadProfile();
    final teacherName = profile?.name ??
        _pendingTrustedAccount?.name ??
        _offlineProfile?.name;

    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (context) => WelcomeOnboardingPage(
          teacherName: teacherName,
          onFinished: () async {
            await OnboardingPreferencesService.setOnboardingCompleted();
            if (!context.mounted) {
              return;
            }
            Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const DashboardPage(),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _enterDashboard() async {
    await LocalDataStore.instance.reloadForCurrentTeacher();
    if (!mounted) {
      return;
    }
    _openDashboard();
  }

  void _openDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (context) => const DashboardPage()),
    );
  }

  void _showOnlineLogin() {
    setState(() {
      _stage = _LoginStage.onlineAuth;
      _isSubmitting = false;
      _restoredPinFromCloud = false;
      _unlockPinController.clear();
    });
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
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
    final isSetup = _stage == _LoginStage.offlinePinSetup;

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
              CocSealLogo(size: isSetup ? 64 : 80),
              const SizedBox(height: AppSpacing.md),
              if (isSetup)
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _buildPinSetupContent(),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildOfflineUnlockContent(),
                  ),
                ),
              if (!isSetup) ...[
                const SizedBox(height: AppSpacing.md),
                _buildOfflineUnlockActions(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthPanel() {
    switch (_stage) {
      case _LoginStage.awaitingEmailConfirmation:
        return _buildAwaitingEmailConfirmationPanel();
      case _LoginStage.offlinePinSetup:
        return _buildPinSetupContent();
      case _LoginStage.offlineUnlock:
        return _buildOfflineUnlockPanel();
      case _LoginStage.onlineAuth:
        return _buildOnlineAuthPanel();
    }
  }

  Widget _buildAwaitingEmailConfirmationPanel() {
    final email = _pendingConfirmationEmail ?? _emailController.text.trim();

    return AuthShell(
      title: 'Check your email',
      subtitle:
          'We sent a confirmation link to finish setting up your account.',
      badge: AuthBadgeType.online,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusNote(
            icon: Icons.mark_email_read_outlined,
            text:
                'Open the email on this phone and tap Confirm.\n\n'
                'COC OMR will open automatically. Create your PIN once, then you\'ll land on your dashboard — no need to sign in again.',
          ),
          const SizedBox(height: AppSpacing.md),
          _statusNote(
            icon: Icons.alternate_email_rounded,
            text: email.isEmpty ? 'Your school email' : email,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'I confirmed — continue',
            icon: Icons.arrow_forward_rounded,
            isLoading: _isSubmitting,
            onPressed: !_isSubmitting ? _retryAfterEmailConfirmation : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    setState(() {
                      _stage = _LoginStage.onlineAuth;
                      _mode = _AuthMode.login;
                    });
                  },
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryAfterEmailConfirmation() async {
    if (!SupabaseService.isReady) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await SupabaseService.client?.auth.refreshSession();
      if (!mounted) {
        return;
      }

      if (SupabaseService.client?.auth.currentSession != null) {
        _confirmedEmailThisSession = true;
        await _continueWithActiveSession(
          fromEmailConfirmation: true,
          isNewRegistration: true,
        );
        return;
      }

      setState(() => _isSubmitting = false);
      _showMessage(
        'Not confirmed yet. Tap the link in your email first, then try again.',
        isError: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmitting = false);
      _showMessage(UserErrorMessages.friendlyError(error), isError: true);
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

  Widget _buildPinSetupContent() {
    final account = _pendingTrustedAccount;

    return AuthShell(
      title: 'Create your PIN',
      subtitle: _confirmedEmailThisSession
          ? 'Last step — then your dashboard opens.'
          : 'One PIN for exam day — on this phone, after reinstall, or on a new phone.',
      badge: AuthBadgeType.none,
      showLogo: false,
      compact: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account != null)
            _statusNote(
              icon: Icons.verified_user_rounded,
              text: account.email.isEmpty
                  ? 'Your online account is verified.'
                  : 'Signed in as ${account.email}',
            ),
          if (account != null) const SizedBox(height: AppSpacing.md),
          AppPinSetupFlow(
            isLoading: _isSubmitting,
            onConfirmed: _createOfflinePin,
          ),
        ],
      ),
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
      subtitle: _restoredPinFromCloud
          ? 'Use the same PIN you set before. It works offline on this phone too.'
          : _isDeviceOnline
              ? 'Unlock your trusted device to continue grading.'
              : 'You can keep scanning and grading. Your work saves on this phone.',
      teacherName: profile?.name,
      schoolName: profile?.school,
      badge: _isDeviceOnline ? AuthBadgeType.none : AuthBadgeType.offline,
      showLogo: false,
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isDeviceOnline) ...[
            _statusNote(
              icon: Icons.wifi_off_rounded,
              text:
                  'No Wi‑Fi or mobile data right now.\n\n'
                  '• Scanning and grading still work — scores stay on this phone.\n'
                  '• When internet returns, unlock and go to Settings → Sync now to upload.\n'
                  '• Or tap Use online login below if you prefer email sign-in.',
              isWarning: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppPinInput(
            key: const ValueKey('pin-unlock'),
            controller: _unlockPinController,
            label: 'PIN',
            enabled: !_isSubmitting,
            compact: true,
          ),
        ],
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
