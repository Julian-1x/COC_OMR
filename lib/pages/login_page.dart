import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/constants/coc_school.dart';
import 'package:omr_app/pages/dashboard_page.dart';
import 'package:omr_app/pages/welcome_onboarding_page.dart';
import 'package:omr_app/services/cloud_auth_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/onboarding_preferences_service.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/cloud_sync_service.dart';
import 'package:omr_app/services/teacher_pin_sync_service.dart';
import 'package:omr_app/services/scanner_engine.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/widgets/app_pin_input.dart';
import 'package:omr_app/widgets/app_primary_button.dart';
import 'package:omr_app/utils/password_rules.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/widgets/auth_shell.dart';

enum _AuthMode { login, register }

enum _LoginStage {
  onlineAuth,
  mfaChallenge,
  mfaEnrollment,
  awaitingEmailConfirmation,
  awaitingAdminApproval,
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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _unlockPinController = TextEditingController();
  final TextEditingController _mfaCodeController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  _LoginStage _stage = _LoginStage.onlineAuth;
  String? _mfaTicket;
  String? _mfaSetupSecret;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _selectedDepartment;
  CloudTeacherAccount? _pendingTrustedAccount;
  LocalTeacherProfile? _offlineProfile;
  bool _isNewRegistration = false;
  bool _restoredPinFromCloud = false;
  bool _confirmedEmailThisSession = false;
  /// Teacher forgot offline PIN — after online login they must set a new one.
  bool _resettingForgottenPin = false;
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
    _emailController.dispose();
    _passwordController.dispose();
    _unlockPinController.dispose();
    _mfaCodeController.dispose();
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
    if (!ApiService.isReady) {
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
    if (!mounted || !ApiService.isReady || !_isAuthCallbackUri(uri)) {
      return;
    }

    final accessPending = uri.queryParameters['access_pending'] == '1' ||
        uri.queryParameters['access_status'] == 'pending' ||
        uri.queryParameters['access_status'] == 'revoked';
    final verified = uri.queryParameters['verified'] == '1';
    final token = uri.queryParameters['token']?.trim();

    if (accessPending || (verified && (token == null || token.isEmpty))) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _LoginStage.awaitingAdminApproval;
        _mode = _AuthMode.login;
        _isLoading = false;
        _isSubmitting = false;
        _pendingConfirmationEmail =
            _pendingConfirmationEmail ?? _emailController.text.trim().toLowerCase();
      });
      _showMessage(
        'Email confirmed. Ask your COC admin to approve your account, then sign in.',
        isError: false,
      );
      return;
    }

    if (token == null || token.isEmpty) {
      return;
    }

    try {
      await _auth.applyTokenFromEmailVerification(token);
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
      final message = UserErrorMessages.friendlyError(error);
      if (message.toLowerCase().contains('admin approval') ||
          message.toLowerCase().contains('waiting for school admin')) {
        setState(() {
          _stage = _LoginStage.awaitingAdminApproval;
          _mode = _AuthMode.login;
          _isLoading = false;
          _isSubmitting = false;
        });
      }
      _showMessage(message, isError: true);
    }
  }

  Future<void> _continueWithActiveSession({
    bool fromEmailConfirmation = false,
    bool isNewRegistration = false,
  }) async {
    if (!ApiService.hasActiveSession) {
      return;
    }

    final check = await _auth.checkCurrentSession();
    final account =
        check.isUnreachable ? _auth.cachedSessionAccount() : check.account;
    if (account == null) {
      if (check.isUnreachable) {
        await _fallBackToOfflineUnlock();
        return;
      }
      if (ApiService.hasActiveSession) {
        await _auth.signOut();
      }
      if (mounted) {
        setState(() {
          _offlineProfile = null;
          _stage = _LoginStage.onlineAuth;
          _isLoading = false;
          _isSubmitting = false;
        });
        _showMessage(
          'Your account was removed or access was revoked. Sign in again or contact your COC admin.',
          isError: true,
        );
      }
      return;
    }
    if (!account.isApproved) {
      await ApiService.clearSession();
      if (mounted) {
        setState(() {
          _stage = _LoginStage.awaitingAdminApproval;
          _mode = _AuthMode.login;
          _isLoading = false;
          _isSubmitting = false;
          _pendingConfirmationEmail = account.email;
        });
        _showMessage(
          'Your account is waiting for school admin approval. Ask your COC admin to approve you, then sign in.',
          isError: false,
        );
      }
      return;
    }

    final profile = await _localAuth.loadProfile();
    if (profile == null) {
      final resolvedAccount = account;
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
      // Show the PIN screen immediately. A slow /me call on Wi‑Fi must not
      // delay unlock — validate the cloud session in the background.
      if (mounted) {
        setState(() {
          _offlineProfile = offlineProfile;
          _stage = _LoginStage.offlineUnlock;
          _isLoading = false;
        });
      }
      unawaited(_validateSessionInBackground());
      return;
    }

    if (ApiService.hasActiveSession) {
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
    if (!ApiService.isReady) {
      return;
    }

    try {
      await CloudSyncService.instance.syncAll();
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
    if (!ApiService.isReady) {
      _showMessage(
        'School server is not connected. Reinstall the app with API_BASE_URL configured.',
        isError: true,
      );
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final isRegister = _mode == _AuthMode.register;

    if (isRegister && name.isEmpty) {
      _showMessage('Enter your full name (first name, then last name).', isError: true);
      return;
    }
    if (isRegister &&
        (_selectedDepartment == null ||
            !CocSchool.isValidDepartment(_selectedDepartment!))) {
      _showMessage('Select your COC department.', isError: true);
      return;
    }
    if (!_isValidEmail(email)) {
      _showMessage('Enter a valid email address.', isError: true);
      return;
    }
    if (isRegister) {
      final passwordError = PasswordRules.validationError(password);
      if (passwordError != null) {
        _showMessage(passwordError, isError: true);
        return;
      }
    } else if (password.trim().isEmpty) {
      _showMessage('Enter your password.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (isRegister) {
        final registration = await _auth.registerTeacher(
          name: name,
          email: email,
          password: password,
          school: CocSchool.name,
          department: _selectedDepartment!,
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

        if (registration.needsAdminApproval) {
          setState(() {
            _isSubmitting = false;
            _isNewRegistration = true;
            _pendingConfirmationEmail =
                registration.pendingEmail ?? email.trim().toLowerCase();
            _stage = _LoginStage.awaitingAdminApproval;
          });
          _showMessage(
            registration.message ??
                'Ask your COC admin to approve your account, then sign in.',
            isError: false,
          );
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

      final signIn = await _auth.signInTeacher(
        email: email,
        password: password,
      );

      if (!mounted) {
        return;
      }

      if (signIn.captchaRequired) {
        setState(() => _isSubmitting = false);
        _showMessage(
          signIn.message ??
              'Too many sign-in attempts. Use the web portal to complete the security check, then try again.',
          isError: true,
        );
        return;
      }

      if (signIn.needsMfaEnrollment) {
        final ticket = signIn.mfaTicket;
        if (ticket == null || ticket.isEmpty) {
          throw const CloudAuthException('Sign in could not continue. Try again.');
        }
        final setup = await _auth.beginMfaEnrollmentDuringLogin(mfaTicket: ticket);
        setState(() {
          _isSubmitting = false;
          _mfaTicket = ticket;
          _mfaSetupSecret = setup['secret'];
          _stage = _LoginStage.mfaEnrollment;
        });
        _showMessage(
          'Set up two-factor sign-in. Add the secret to Google Authenticator, then enter the 6-digit code.',
          isError: false,
        );
        return;
      }

      if (signIn.needsMfa) {
        setState(() {
          _isSubmitting = false;
          _mfaTicket = signIn.mfaTicket;
          _stage = _LoginStage.mfaChallenge;
        });
        return;
      }

      final account = signIn.account;
      if (account == null) {
        throw const CloudAuthException('Sign in failed. Try again.');
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
        final message = UserErrorMessages.friendlyError(error);
        final lower = message.toLowerCase();
        if (lower.contains('not been confirmed') ||
            lower.contains('confirmation email') ||
            lower.contains('confirm your email')) {
          setState(() {
            _stage = _LoginStage.awaitingEmailConfirmation;
            _pendingConfirmationEmail = email.trim().toLowerCase();
          });
        } else if (lower.contains('admin approval') ||
            lower.contains('waiting for school admin')) {
          setState(() {
            _stage = _LoginStage.awaitingAdminApproval;
            _pendingConfirmationEmail = email.trim().toLowerCase();
          });
        }
        _showMessage(message, isError: true);
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
        school: account.school ?? CocSchool.name,
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
          _resettingForgottenPin
              ? 'New PIN saved. Use it next time you unlock this phone.'
              : 'PIN saved. You can use it on this phone and restore it after reinstall or on a new phone.',
          isError: false,
        );
      }
      _resettingForgottenPin = false;
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
    // Never block exam-day unlock on a cloud PIN backup round-trip.
    unawaited(_syncPinToCloudIfNeeded());
    if (!mounted) {
      return;
    }
    await _enterDashboard();
  }

  Future<void> _validateSessionInBackground() async {
    if (!ApiService.hasActiveSession || !ApiService.isReady) {
      return;
    }

    final check = await _auth.checkCurrentSession();
    if (!mounted || !check.isInvalid) {
      return;
    }

    // Cloud token is dead (expired DB / old session). Keep the offline PIN
    // screen so teachers can still open the app on exam day.
    await ApiService.clearSession();
    final profile = await _localAuth.loadProfile();
    if (!mounted) {
      return;
    }
    if (profile != null) {
      setState(() {
        _offlineProfile = profile;
        _stage = _LoginStage.offlineUnlock;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _offlineProfile = null;
      _stage = _LoginStage.onlineAuth;
      _isLoading = false;
    });
    _showMessage(
      'Cloud sign-in is unavailable right now. Use your offline PIN if this phone was set up before, or try again when the school server is back.',
      isError: true,
    );
  }

  Future<void> _routeAfterOnlineAuth(
    CloudTeacherAccount account, {
    required bool isNewRegistration,
  }) async {
    if (_resettingForgottenPin) {
      final existingProfile = await _localAuth.loadProfile();
      final existingCloudId = existingProfile?.cloudUserId?.trim();
      if (existingCloudId != null &&
          existingCloudId.isNotEmpty &&
          existingCloudId != account.id) {
        if (mounted) {
          _showMessage(
            'Sign in with the same school email used on this phone '
            '(${existingProfile?.email ?? 'your teacher account'}), then set a new PIN.',
            isError: true,
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _pendingTrustedAccount = account;
          _isNewRegistration = false;
          _restoredPinFromCloud = false;
          _stage = _LoginStage.offlinePinSetup;
        });
      }
      return;
    }

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
    if (!ApiService.hasActiveSession) {
      return false;
    }

    final cloudPin = await TeacherPinSyncService.instance.fetchForCurrentUser();
    if (cloudPin == null) {
      return false;
    }

    await _localAuth.installCloudProfile(
      name: cloudPin.name.isNotEmpty ? cloudPin.name : account.name,
      school: cloudPin.school ?? account.school ?? CocSchool.name,
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

  /// Used when the cloud cannot be reached: never accuse the account of being
  /// revoked, just let the teacher unlock with their PIN.
  Future<void> _fallBackToOfflineUnlock() async {
    final profile = await _localAuth.loadProfile();
    if (!mounted) {
      return;
    }
    if (profile != null) {
      await _goToOfflineUnlock(restoredFromCloud: false);
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() {
      _offlineProfile = null;
      _stage = _LoginStage.onlineAuth;
      _isLoading = false;
      _isSubmitting = false;
    });
    _showMessage(
      'No internet right now. Connect to Wi-Fi or data once to finish setting up this phone.',
      isError: true,
    );
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
    if (Platform.isAndroid) {
      unawaited(ScannerEngine.warmUp());
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
      _resettingForgottenPin = false;
      _mode = _AuthMode.login;
      _unlockPinController.clear();
    });
  }

  void _startForgotPinFlow() {
    if (!ApiService.isReady) {
      _showMessage(
        'School server is not connected on this install. Ask IT for the official APK.',
        isError: true,
      );
      return;
    }
    if (!_isDeviceOnline) {
      _showMessage(
        'Connect to Wi‑Fi or mobile data, then tap Forgot PIN again. '
        'You must sign in with your school email to set a new offline PIN.',
        isError: true,
      );
      return;
    }

    final email = _offlineProfile?.email?.trim();
    setState(() {
      _resettingForgottenPin = true;
      _stage = _LoginStage.onlineAuth;
      _mode = _AuthMode.login;
      _isSubmitting = false;
      _restoredPinFromCloud = false;
      _unlockPinController.clear();
      if (email != null && email.isNotEmpty) {
        _emailController.text = email;
      }
    });
    _showMessage(
      'Sign in with your school email and password, then create a new offline PIN.',
      isError: false,
    );
  }

  void _returnToOfflineUnlock() {
    setState(() {
      _stage = _LoginStage.offlineUnlock;
      _resettingForgottenPin = false;
      _isSubmitting = false;
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
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: AuthLoadingShell(),
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
      case _LoginStage.awaitingAdminApproval:
        return _buildAwaitingAdminApprovalPanel();
      case _LoginStage.offlinePinSetup:
        return _buildPinSetupContent();
      case _LoginStage.offlineUnlock:
        return _buildOfflineUnlockPanel();
      case _LoginStage.mfaChallenge:
        return _buildMfaChallengePanel();
      case _LoginStage.mfaEnrollment:
        return _buildMfaEnrollmentPanel();
      case _LoginStage.onlineAuth:
        return _buildOnlineAuthPanel();
    }
  }

  Future<void> _submitMfaCode({required bool enrollment}) async {
    final ticket = _mfaTicket;
    final code = _mfaCodeController.text.trim();
    if (ticket == null || ticket.isEmpty) {
      _showMessage('Sign-in expired. Enter your password again.', isError: true);
      setState(() => _stage = _LoginStage.onlineAuth);
      return;
    }
    if (code.length < 6) {
      _showMessage('Enter the 6-digit code from your authenticator app.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final account = enrollment
          ? await _auth.completeMfaEnrollmentDuringLogin(
              mfaTicket: ticket,
              code: code,
            )
          : await _auth.completeMfaSignIn(mfaTicket: ticket, code: code);

      if (!mounted) {
        return;
      }

      await _pullCloudData(showErrors: true);
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _mfaCodeController.clear();
        _mfaTicket = null;
        _mfaSetupSecret = null;
        _stage = _LoginStage.onlineAuth;
      });
      await _routeAfterOnlineAuth(account, isNewRegistration: false);
    } catch (error) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showMessage(UserErrorMessages.friendlyError(error), isError: true);
      }
    }
  }

  Widget _buildMfaChallengePanel() {
    return AuthShell(
      title: 'Two-factor code',
      subtitle: 'Enter the 6-digit code from your authenticator app.',
      badge: AuthBadgeType.online,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _mfaCodeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'Authenticator code',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Verify and continue',
            icon: Icons.verified_user_outlined,
            isLoading: _isSubmitting,
            onPressed: !_isSubmitting
                ? () => _submitMfaCode(enrollment: false)
                : null,
          ),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    setState(() {
                      _stage = _LoginStage.onlineAuth;
                      _mfaTicket = null;
                      _mfaCodeController.clear();
                    });
                  },
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }

  Widget _buildMfaEnrollmentPanel() {
    final secret = _mfaSetupSecret ?? '';
    return AuthShell(
      title: 'Set up two-factor',
      subtitle:
          'School admins must use an authenticator app. Add this key, then enter the code.',
      badge: AuthBadgeType.online,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (secret.isNotEmpty)
            SelectableText(
              secret,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _mfaCodeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: '6-digit code',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Finish setup',
            icon: Icons.shield_outlined,
            isLoading: _isSubmitting,
            onPressed:
                !_isSubmitting ? () => _submitMfaCode(enrollment: true) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingAdminApprovalPanel() {
    final email = _pendingConfirmationEmail ?? _emailController.text.trim();

    return AuthShell(
      title: 'Waiting for approval',
      subtitle:
          'Your email is confirmed. A COC school admin must approve your account before you can use the app.',
      badge: AuthBadgeType.online,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusNote(
            icon: Icons.admin_panel_settings_outlined,
            text:
                'Your email must already be confirmed. Then a COC admin opens '
                'the web portal → Admin → Access control and approves you.\n\n'
                'After they approve, come back here and sign in with the same email and password.',
          ),
          const SizedBox(height: AppSpacing.md),
          _statusNote(
            icon: Icons.alternate_email_rounded,
            text: email.isEmpty ? 'Your school email' : email,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Back to sign in',
            icon: Icons.login_rounded,
            onPressed: () {
              setState(() {
                _stage = _LoginStage.onlineAuth;
                _mode = _AuthMode.login;
              });
            },
          ),
        ],
      ),
    );
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
                'After your email is confirmed, a school admin still needs to '
                'approve your account before you can use the app.\n\n'
                'Check spam/junk if you do not see the message.',
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
            onPressed: _isSubmitting ? null : _resendConfirmationEmail,
            child: const Text('Resend confirmation email'),
          ),
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

  Future<void> _resendConfirmationEmail() async {
    final email = (_pendingConfirmationEmail ?? _emailController.text.trim())
        .trim()
        .toLowerCase();
    if (!_isValidEmail(email)) {
      _showMessage('Enter a valid email on the sign-in form first.', isError: true);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _auth.resendEmailVerification(email: email);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage(
        'Confirmation email sent again. Check your inbox and spam folder.',
        isError: false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage(UserErrorMessages.friendlyError(error), isError: true);
    }
  }

  Future<void> _retryAfterEmailConfirmation() async {
    if (!ApiService.isReady) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (ApiService.hasActiveSession) {
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
    final canReturnToPin = _offlineProfile != null && !_isSubmitting;

    return AuthShell(
      title: _resettingForgottenPin
          ? 'Sign in to reset PIN'
          : isRegister
              ? 'Create Teacher Account'
              : 'Welcome Back',
      subtitle: _resettingForgottenPin
          ? 'Use your school email and password. After sign-in you will set a new offline PIN.'
          : isRegister
              ? 'Register to sync your classes and scan results to the cloud.'
              : 'Sign in to continue to OMR Hub.',
      badge: ApiService.isReady
          ? AuthBadgeType.online
          : AuthBadgeType.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_resettingForgottenPin) ...[
            _modeSelector(),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (!ApiService.isReady) ...[
            _statusNote(
              icon: Icons.cloud_off_rounded,
              text:
                  'Cloud sign-in is not configured in this APK. Ask your administrator for a build that includes API_BASE_URL, or reinstall using the official release package.',
              isWarning: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (isRegister && !_resettingForgottenPin) ...[
            _textField(
              controller: _nameController,
              label: 'Full name',
              hint: 'First name then last name (e.g. Maria Santos)',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.md),
            _statusNote(
              icon: Icons.apartment_rounded,
              text: CocSchool.name,
            ),
            const SizedBox(height: AppSpacing.md),
            _departmentDropdown(),
            const SizedBox(height: AppSpacing.sm),
            _statusNote(
              icon: Icons.info_outline_rounded,
              text:
                  'After email confirmation, a school admin must approve your account before you can use the app.',
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _emailField(),
          const SizedBox(height: AppSpacing.md),
          _passwordField(),
          if (!isRegister || _resettingForgottenPin) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: ApiService.isReady && !_isSubmitting
                    ? _showForgotPasswordSheet
                    : null,
                child: const Text('Forgot password?'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: _resettingForgottenPin
                ? 'Sign in & set new PIN'
                : isRegister
                    ? 'Create Account'
                    : 'Sign In',
            icon: _resettingForgottenPin
                ? Icons.lock_reset_rounded
                : isRegister
                    ? Icons.person_add_alt_1_rounded
                    : Icons.login_rounded,
            isLoading: _isSubmitting,
            onPressed: ApiService.isReady && !_isSubmitting ? _submit : null,
          ),
          if (canReturnToPin) ...[
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton(
                onPressed: _returnToOfflineUnlock,
                child: const Text('Back to PIN unlock'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Prompts for an email and asks the server to send a password-reset link.
  Future<void> _showForgotPasswordSheet() async {
    final resetEmailController =
        TextEditingController(text: _emailController.text.trim());
    var isSending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> submitReset() async {
              final email = resetEmailController.text.trim();
              if (!_isValidEmail(email)) {
                _showMessage('Enter a valid email address.', isError: true);
                return;
              }
              final navigator = Navigator.of(sheetContext);
              setSheetState(() => isSending = true);
              try {
                await _auth.requestPasswordReset(email: email);
                if (!mounted) return;
                navigator.pop();
                _showMessage(
                  'If that email is registered, a reset link is on its way. '
                  'Open it in your browser to set a new password, then sign in here.',
                  isError: false,
                );
              } catch (error) {
                setSheetState(() => isSending = false);
                _showMessage(
                  UserErrorMessages.friendlyError(error),
                  isError: true,
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                    AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Reset your password',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Enter your account email. We\'ll send a link to set a new '
                    'password. Open it on this phone.',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: AppColors.brandMuted,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    enabled: !isSending,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    onSubmitted: (_) => isSending ? null : submitReset(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppPrimaryButton(
                    label: 'Send reset link',
                    icon: Icons.mail_outline_rounded,
                    isLoading: isSending,
                    onPressed: isSending ? null : submitReset,
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    resetEmailController.dispose();
  }

  Widget _buildPinSetupContent() {
    final account = _pendingTrustedAccount;
    final isReset = _resettingForgottenPin;

    return AuthShell(
      title: isReset ? 'Set a new PIN' : 'Create your PIN',
      subtitle: isReset
          ? 'Your online sign-in is verified. Choose a new 4–6 digit PIN for exam day.'
          : _confirmedEmailThisSession
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
        if (ApiService.isReady) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _isSubmitting ? null : _startForgotPinFlow,
              child: const Text('Forgot PIN?'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _isSubmitting ? null : _showOnlineLogin,
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

  Widget _departmentDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Department'),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(_selectedDepartment ?? 'dept-none'),
          initialValue: _selectedDepartment,
          decoration: _inputDecoration(
            hint: 'Select department',
            icon: Icons.school_outlined,
          ),
          items: CocSchool.departments
              .map(
                (code) => DropdownMenuItem<String>(
                  value: code,
                  child: Text(code),
                ),
              )
              .toList(),
          onChanged: _isSubmitting
              ? null
              : (value) => setState(() => _selectedDepartment = value),
        ),
      ],
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
            hint: _mode == _AuthMode.register
                ? PasswordRules.requirementHint
                : 'Your account password',
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
