import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/constants/auth_config.dart';
import 'package:omr_app/constants/coc_school.dart';
import 'package:omr_app/pages/dashboard_page.dart';
import 'package:omr_app/pages/welcome_onboarding_page.dart';
import 'package:omr_app/services/cloud_auth_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/onboarding_preferences_service.dart';
import 'package:omr_app/services/register_form_draft_service.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/cloud_sync_service.dart';
import 'package:omr_app/services/teacher_pin_sync_service.dart';
import 'package:omr_app/services/scanner_engine.dart';
import 'package:omr_app/services/security_config_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/widgets/app_pin_input.dart';
import 'package:omr_app/widgets/app_primary_button.dart';
import 'package:omr_app/utils/password_rules.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/widgets/auth_shell.dart';
import 'package:omr_app/widgets/password_requirements_checklist.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:omr_app/widgets/turnstile_captcha_field.dart';

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

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  final CloudAuthService _auth = CloudAuthService.instance;
  final LocalAuthService _localAuth = LocalAuthService.instance;
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _suffixController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _unlockPinController = TextEditingController();
  final TextEditingController _mfaCodeController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  _LoginStage _stage = _LoginStage.onlineAuth;
  Timer? _registerDraftSaveTimer;
  String? _mfaTicket;
  String? _mfaSetupSecret;
  String? _mfaOtpAuthUrl;
  bool _mfaSetupManualKey = false;
  bool _mfaViaEmail = false;
  String? _mfaEmailHint;
  DateTime? _mfaEmailResendAt;
  bool _mfaEmailSending = false;
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
  SecurityConfig _securityConfig = SecurityConfig.disabled;
  String? _captchaToken;
  String? _captchaSiteKeyOverride;
  /// Remount Turnstile after failures so Success UI cannot outlive a cleared token.
  int _captchaRemountNonce = 0;
  bool _loginCaptchaRequired = false;
  bool _registerCaptchaRequired = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<Uri>? _authLinkSub;
  Timer? _emailVerifyPoll;
  bool _emailVerifyPollInFlight = false;
  bool _adminApprovalDialogOpen = false;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastNameController.addListener(_scheduleRegisterDraftSave);
    _firstNameController.addListener(_scheduleRegisterDraftSave);
    _suffixController.addListener(_scheduleRegisterDraftSave);
    _emailController.addListener(_scheduleRegisterDraftSave);
    unawaited(_bootstrapAuth());
    unawaited(_initConnectivity());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_saveRegisterDraft());
    }
  }

  Future<void> _bootstrapAuth() async {
    await _restoreRegisterDraft();
    await _restoreSession();
    await _loadSecurityConfig();
    await _initAuthDeepLinks();
  }

  Future<void> _restoreRegisterDraft() async {
    final draft = await RegisterFormDraftService.load();
    if (!mounted || !draft.hasAnyField) {
      if (draft.preferRegisterTab && mounted && _stage == _LoginStage.onlineAuth) {
        setState(() => _mode = _AuthMode.register);
      }
      return;
    }
    if (_lastNameController.text.isEmpty && draft.lastName.isNotEmpty) {
      _lastNameController.text = draft.lastName;
    }
    if (_firstNameController.text.isEmpty && draft.firstName.isNotEmpty) {
      _firstNameController.text = draft.firstName;
    }
    if (_suffixController.text.isEmpty && draft.suffix.isNotEmpty) {
      _suffixController.text = draft.suffix;
    }
    if (_emailController.text.isEmpty && draft.email.isNotEmpty) {
      _emailController.text = draft.email;
    }
    if (mounted) {
      setState(() {
        if (draft.department != null &&
            CocSchool.isValidDepartment(draft.department!)) {
          _selectedDepartment = draft.department;
        }
        if (draft.preferRegisterTab || draft.hasAnyField) {
          _mode = _AuthMode.register;
        }
      });
    }
  }

  void _scheduleRegisterDraftSave() {
    _registerDraftSaveTimer?.cancel();
    _registerDraftSaveTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_saveRegisterDraft()),
    );
  }

  Future<void> _saveRegisterDraft() async {
    await RegisterFormDraftService.save(
      RegisterFormDraft(
        lastName: _lastNameController.text,
        firstName: _firstNameController.text,
        suffix: _suffixController.text,
        email: _emailController.text,
        department: _selectedDepartment,
        preferRegisterTab: _mode == _AuthMode.register,
      ),
    );
  }

  Future<void> _clearRegisterDraft() async {
    _registerDraftSaveTimer?.cancel();
    await RegisterFormDraftService.clear();
  }

  Future<void> _loadSecurityConfig() async {
    if (!ApiService.isConfigured) {
      return;
    }
    final config = await SecurityConfigService.instance.fetch();
    if (mounted) {
      setState(() => _securityConfig = config);
    }
  }

  String? get _activeCaptchaSiteKey =>
      _captchaSiteKeyOverride ?? _securityConfig.captchaSiteKey;

  bool get _needsCaptchaOnForm {
    final siteKey = _activeCaptchaSiteKey;
    if (siteKey == null || siteKey.isEmpty) {
      return false;
    }
    if (_mode == _AuthMode.register) {
      return _securityConfig.captchaEnabled || _registerCaptchaRequired;
    }
    return _loginCaptchaRequired;
  }

  void _resetCaptchaChallenge() {
    _captchaToken = null;
    _loginCaptchaRequired = false;
    _registerCaptchaRequired = false;
    _captchaSiteKeyOverride = null;
    _captchaRemountNonce += 1;
  }

  void _invalidateCaptchaAfterFailedAttempt() {
    _captchaToken = null;
    _captchaRemountNonce += 1;
  }

  Widget? _buildCaptchaField() {
    final siteKey = _activeCaptchaSiteKey;
    if (!_needsCaptchaOnForm || siteKey == null || siteKey.isEmpty) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TurnstileCaptchaField(
        // Site key + nonce: password typing does not remount; failures do.
        key: ValueKey<String>('turnstile-$siteKey-$_captchaRemountNonce'),
        siteKey: siteKey,
        onToken: (token) {
          if (!mounted) {
            return;
          }
          setState(() => _captchaToken = token);
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _registerDraftSaveTimer?.cancel();
    unawaited(_saveRegisterDraft());
    _stopEmailVerificationPoll();
    _connectivitySub?.cancel();
    _authLinkSub?.cancel();
    _lastNameController.removeListener(_scheduleRegisterDraftSave);
    _firstNameController.removeListener(_scheduleRegisterDraftSave);
    _suffixController.removeListener(_scheduleRegisterDraftSave);
    _emailController.removeListener(_scheduleRegisterDraftSave);
    _lastNameController.dispose();
    _firstNameController.dispose();
    _suffixController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _unlockPinController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  void _stopEmailVerificationPoll() {
    _emailVerifyPoll?.cancel();
    _emailVerifyPoll = null;
    _emailVerifyPollInFlight = false;
  }

  void _startEmailVerificationPoll() {
    _stopEmailVerificationPoll();
    if (!ApiService.isReady) {
      return;
    }
    // Immediate check, then keep polling until the mail link is confirmed.
    unawaited(_pollEmailVerificationOnce());
    _emailVerifyPoll = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollEmailVerificationOnce()),
    );
  }

  Future<void> _pollEmailVerificationOnce() async {
    if (!mounted ||
        _stage != _LoginStage.awaitingEmailConfirmation ||
        _emailVerifyPollInFlight ||
        _adminApprovalDialogOpen) {
      return;
    }
    final email = (_pendingConfirmationEmail ?? _emailController.text.trim())
        .trim()
        .toLowerCase();
    if (!_isValidEmail(email)) {
      return;
    }

    _emailVerifyPollInFlight = true;
    try {
      final status = await _auth.checkEmailVerificationStatus(email: email);
      if (!mounted || _stage != _LoginStage.awaitingEmailConfirmation) {
        return;
      }
      if (!status.verified) {
        return;
      }
      _stopEmailVerificationPoll();
      await _onEmailConfirmedWhileWaiting(
        accessPending: status.accessPending,
      );
    } catch (error) {
      debugPrint('Email verification poll failed: $error');
    } finally {
      _emailVerifyPollInFlight = false;
    }
  }

  /// After the teacher confirms email (deep link or poll), return to Login and
  /// require them to acknowledge the admin-approval wait.
  Future<void> _onEmailConfirmedWhileWaiting({
    required bool accessPending,
  }) async {
    if (!mounted) {
      return;
    }
    final email = (_pendingConfirmationEmail ?? _emailController.text.trim())
        .trim()
        .toLowerCase();

    // Drop any half-open session from registration — they sign in after approval.
    if (ApiService.hasActiveSession) {
      try {
        await ApiService.clearSession();
      } catch (_) {}
    }

    setState(() {
      _confirmedEmailThisSession = true;
      _pendingConfirmationEmail = email.isEmpty ? _pendingConfirmationEmail : email;
      _stage = _LoginStage.onlineAuth;
      _mode = _AuthMode.login;
      _isLoading = false;
      _isSubmitting = false;
    });

    if (accessPending) {
      await _showAdminApprovalAcknowledgmentDialog(email: email);
    } else {
      _showMessage(
        'Email confirmed. Sign in with your email and password.',
        isError: false,
      );
    }
  }

  Future<void> _showAdminApprovalAcknowledgmentDialog({
    required String email,
  }) async {
    if (!mounted || _adminApprovalDialogOpen) {
      return;
    }
    _adminApprovalDialogOpen = true;
    var understood = false;
    var canContinue = false;
    var waitScheduled = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!waitScheduled) {
              waitScheduled = true;
              Future<void>.delayed(const Duration(seconds: 3), () {
                if (dialogContext.mounted) {
                  setDialogState(() => canContinue = true);
                }
              });
            }
            return PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('Email confirmed'),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Your email is confirmed. You still cannot use COC OMR '
                        'until a school admin approves your account.',
                        style: TextStyle(height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        email.isEmpty
                            ? 'Ask your COC admin to open the web portal → Admin → Access control and approve you.'
                            : 'Ask your COC admin to approve:\n$email\n\n'
                                'They open the web portal → Admin → Access control.',
                        style: const TextStyle(height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'You will get an email when they approve. Then come back '
                        'here and sign in with the same email and password.',
                        style: TextStyle(height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: understood,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'I understand I must wait for admin approval before signing in.',
                          style: TextStyle(fontSize: 14, height: 1.3),
                        ),
                        onChanged: (value) {
                          setDialogState(() => understood = value ?? false);
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: (understood && canContinue)
                        ? () => Navigator.of(dialogContext).pop()
                        : null,
                    child: Text(
                      canContinue
                          ? 'I understand — go to sign in'
                          : 'Read above (wait…)',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    _adminApprovalDialogOpen = false;
    if (!mounted) {
      return;
    }
    _showMessage(
      'Waiting for school admin approval. Sign in again after they approve you.',
      isError: false,
    );
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
    final expected = Uri.parse(kAuthRedirectUrl);
    return uri.scheme == expected.scheme && uri.host == expected.host;
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
      _stopEmailVerificationPoll();
      await _onEmailConfirmedWhileWaiting(accessPending: true);
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
      _stopEmailVerificationPoll();
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
        await _onEmailConfirmedWhileWaiting(accessPending: true);
        return;
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
        _pendingConfirmationEmail = account.email;
        await _onEmailConfirmedWhileWaiting(accessPending: true);
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

    final lastName = _lastNameController.text.trim();
    final firstName = _firstNameController.text.trim();
    final suffix = _suffixController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final isRegister = _mode == _AuthMode.register;

    if (isRegister && (lastName.isEmpty || firstName.isEmpty)) {
      _showMessage('Enter your last name and first name.', isError: true);
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

    if (_needsCaptchaOnForm &&
        (_captchaToken == null || _captchaToken!.trim().isEmpty)) {
      _showMessage(
        'Security check did not sync to the app yet. Wait for '
        '“Security check ready”, or tap Retry security check, then Create Account.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (isRegister) {
        final registration = await _auth.registerTeacher(
          lastName: lastName,
          firstName: firstName,
          suffix: suffix.isEmpty ? null : suffix,
          email: email,
          password: password,
          school: CocSchool.name,
          department: _selectedDepartment!,
          captchaToken: _captchaToken,
        );

        if (!mounted) {
          return;
        }

        if (registration.needsEmailConfirmation) {
          await _clearRegisterDraft();
          setState(() {
            _isSubmitting = false;
            _isNewRegistration = true;
            _pendingConfirmationEmail =
                registration.pendingEmail ?? email.trim().toLowerCase();
            _stage = _LoginStage.awaitingEmailConfirmation;
          });
          _startEmailVerificationPoll();
          return;
        }

        if (registration.needsAdminApproval) {
          await _clearRegisterDraft();
          setState(() {
            _isSubmitting = false;
            _isNewRegistration = true;
            _pendingConfirmationEmail =
                registration.pendingEmail ?? email.trim().toLowerCase();
            _stage = _LoginStage.onlineAuth;
            _mode = _AuthMode.login;
          });
          await _showAdminApprovalAcknowledgmentDialog(
            email: registration.pendingEmail ?? email.trim().toLowerCase(),
          );
          return;
        }

        if (registration.needsMfaEnrollment) {
          final ticket = registration.mfaTicket;
          if (ticket == null || ticket.isEmpty) {
            throw const CloudAuthException(
              'Registration could not continue. Try signing in.',
            );
          }
          final setup =
              await _auth.beginMfaEnrollmentDuringLogin(mfaTicket: ticket);
          if (!mounted) {
            return;
          }
          await _clearRegisterDraft();
          setState(() {
            _isSubmitting = false;
            _isNewRegistration = true;
            _mfaTicket = ticket;
            _mfaSetupSecret = setup['secret'];
            _mfaOtpAuthUrl = setup['otpauth_url'];
            _mfaSetupManualKey = false;
            _stage = _LoginStage.mfaEnrollment;
          });
          _showMessage(
            registration.message ??
                'Scan the QR code with Google Authenticator, then enter the 6-digit code.',
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

        await _clearRegisterDraft();
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
        captchaToken: _captchaToken,
      );

      if (!mounted) {
        return;
      }

      if (signIn.captchaRequired) {
        setState(() {
          _isSubmitting = false;
          _loginCaptchaRequired = true;
          _captchaSiteKeyOverride =
              signIn.captchaSiteKey ?? _securityConfig.captchaSiteKey;
          _invalidateCaptchaAfterFailedAttempt();
        });
        _showMessage(
          signIn.message ??
              'Complete the security check below, then try signing in again.',
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
          _mfaOtpAuthUrl = setup['otpauth_url'];
          _mfaSetupManualKey = false;
          _stage = _LoginStage.mfaEnrollment;
        });
        _showMessage(
          'Scan the QR code with Google Authenticator, then enter the 6-digit code.',
          isError: false,
        );
        return;
      }

      if (signIn.needsMfa) {
        setState(() {
          _isSubmitting = false;
          _mfaTicket = signIn.mfaTicket;
          _mfaViaEmail = false;
          _mfaEmailHint = null;
          _mfaEmailResendAt = null;
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
        // Turnstile tokens are single-use — remount so UI cannot show Success
        // while the app token is already cleared.
        setState(_invalidateCaptchaAfterFailedAttempt);
        if (lower.contains('security check') || lower.contains('captcha')) {
          final refreshed =
              await SecurityConfigService.instance.fetch(forceRefresh: true);
          if (mounted) {
            setState(() {
              _securityConfig = refreshed;
              if (_mode == _AuthMode.register) {
                _registerCaptchaRequired = true;
              } else {
                _loginCaptchaRequired = true;
              }
            });
          }
          _showMessage(message, isError: true);
        } else if (lower.contains('not been confirmed') ||
            lower.contains('confirmation email') ||
            lower.contains('confirm your email')) {
          setState(() {
            _stage = _LoginStage.awaitingEmailConfirmation;
            _pendingConfirmationEmail = email.trim().toLowerCase();
          });
          _startEmailVerificationPoll();
          _showMessage(message, isError: true);
        } else if (lower.contains('admin approval') ||
            lower.contains('waiting for school admin')) {
          _pendingConfirmationEmail = email.trim().toLowerCase();
          await _showAdminApprovalAcknowledgmentDialog(
            email: email.trim().toLowerCase(),
          );
        } else {
          _showMessage(message, isError: true);
        }
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
        showWelcome: _isNewRegistration,
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
    bool requirePinUnlock = false,
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
      if (requirePinUnlock) {
        await _goToOfflineUnlock(restoredFromCloud: false);
        return;
      }
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

    final profile = await _localAuth.loadProfile();
    final teacherId = profile?.cloudUserId ??
        _pendingTrustedAccount?.id ??
        _offlineProfile?.cloudUserId;
    final teacherName = profile?.name ??
        _pendingTrustedAccount?.name ??
        _offlineProfile?.name;

    final completed = await OnboardingPreferencesService.hasCompletedOnboarding(
      teacherId: teacherId,
    );
    // New registrations always see the tutorial. Other accounts see it once
    // per teacher on this phone.
    if (!showWelcome && completed) {
      _openDashboard();
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (context) => WelcomeOnboardingPage(
          teacherName: teacherName,
          onFinished: () async {
            await OnboardingPreferencesService.setOnboardingCompleted(
              teacherId: teacherId,
            );
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
    if (Platform.isAndroid || Platform.isIOS) {
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
        _mfaOtpAuthUrl = null;
      });
      await _routeAfterOnlineAuth(
        account,
        isNewRegistration: _isNewRegistration,
        requirePinUnlock: true,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showMessage(UserErrorMessages.friendlyError(error), isError: true);
      }
    }
  }

  Future<void> _requestMfaEmailCode() async {
    final ticket = _mfaTicket;
    if (ticket == null || ticket.isEmpty) {
      _showMessage('Sign-in expired. Enter your password again.', isError: true);
      setState(() => _stage = _LoginStage.onlineAuth);
      return;
    }
    final resendAt = _mfaEmailResendAt;
    if (resendAt != null && DateTime.now().isBefore(resendAt)) {
      final wait = resendAt.difference(DateTime.now()).inSeconds;
      _showMessage(
        'Wait ${wait.clamp(1, 120)} seconds before requesting another email code.',
        isError: true,
      );
      return;
    }

    setState(() => _mfaEmailSending = true);
    try {
      final response = await _auth.sendMfaEmailCode(mfaTicket: ticket);
      if (!mounted) {
        return;
      }
      final cooldown = (response['resend_after_seconds'] as num?)?.toInt() ?? 60;
      setState(() {
        _mfaEmailSending = false;
        _mfaViaEmail = true;
        _mfaEmailHint = response['email_hint']?.toString();
        _mfaEmailResendAt = DateTime.now().add(Duration(seconds: cooldown));
        _mfaCodeController.clear();
      });
      _showMessage(
        response['message']?.toString() ??
            'We emailed a 6-digit code. Enter it below.',
        isError: false,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _mfaEmailSending = false);
        _showMessage(UserErrorMessages.friendlyError(error), isError: true);
      }
    }
  }

  Widget _buildMfaChallengePanel() {
    return AuthShell(
      title: 'Two-factor code',
      subtitle: _mfaViaEmail
          ? 'Enter the 6-digit code we emailed'
              '${_mfaEmailHint != null ? ' to $_mfaEmailHint' : ''}. '
              'You can still use your authenticator app.'
          : 'Enter the 6-digit code from your authenticator app. '
              'Wait for a fresh code if the server was slow.',
      badge: AuthBadgeType.online,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _mfaCodeController,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: InputDecoration(
              labelText: _mfaViaEmail ? 'Email sign-in code' : 'Authenticator code',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: (_isSubmitting || _mfaEmailSending)
                ? null
                : () => unawaited(_requestMfaEmailCode()),
            child: Text(
              _mfaEmailSending
                  ? 'Sending email code…'
                  : _mfaViaEmail
                      ? 'Resend email code'
                      : 'Can’t use authenticator? Email me a code',
            ),
          ),
          if (_mfaViaEmail)
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        _mfaViaEmail = false;
                        _mfaCodeController.clear();
                      });
                      _showMessage(
                        'Enter the code from your authenticator app.',
                        isError: false,
                      );
                    },
              child: const Text('Use authenticator instead'),
            ),
          const SizedBox(height: AppSpacing.sm),
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
                      _mfaViaEmail = false;
                      _mfaEmailHint = null;
                      _mfaEmailResendAt = null;
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
    final otpAuthUrl = _mfaOtpAuthUrl ?? '';
    final ready = secret.isNotEmpty && otpAuthUrl.isNotEmpty;
    return AuthShell(
      title: 'Set up two-factor',
      subtitle: _mfaSetupManualKey
          ? 'Copy the setup key into Google Authenticator, then enter the code.'
          : 'Scan the QR code with Google Authenticator, then enter the code.',
      badge: AuthBadgeType.online,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ready) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Scan QR code'),
                  icon: Icon(Icons.qr_code_2_outlined, size: 18),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Setup key'),
                  icon: Icon(Icons.vpn_key_outlined, size: 18),
                ),
              ],
              selected: {_mfaSetupManualKey},
              onSelectionChanged: (value) {
                setState(() => _mfaSetupManualKey = value.first);
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (!ready && secret.isNotEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!_mfaSetupManualKey && otpAuthUrl.isNotEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.brandBorder),
                ),
                child: QrImageView(
                  data: otpAuthUrl,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            )
          else if (_mfaSetupManualKey && secret.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brandBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Setup key',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(
                    secret,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: secret));
                        _showMessage(
                          'Setup key copied. Paste it in Google Authenticator → Enter a setup key.',
                          isError: false,
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy setup key'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Codes change every 30 seconds. If the server was slow, wait for a '
            'fresh code before tapping Finish setup.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.brandMuted,
              height: 1.35,
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
                'Ask your COC admin to open the web portal → Admin → Access control '
                'and approve you.\n\n'
                'You will get an email when they approve. Then sign in with the '
                'same email and password — do not keep waiting on this screen.',
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
          'Open the email on this phone and tap “Verify in COC OMR app”. '
          'We will detect confirmation and bring you back to sign in.',
      badge: AuthBadgeType.online,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusNote(
            icon: Icons.mark_email_read_outlined,
            text:
                'Keep this screen open.\n\n'
                '1. Open the email on this phone\n'
                '2. Tap “Verify in COC OMR app”\n'
                '3. We send you back to sign in and explain the admin-approval wait\n\n'
                'Check spam/junk if you do not see the message.',
          ),
          const SizedBox(height: AppSpacing.md),
          _statusNote(
            icon: Icons.hourglass_top_rounded,
            text: 'Waiting for email confirmation…',
          ),
          const SizedBox(height: AppSpacing.md),
          _statusNote(
            icon: Icons.alternate_email_rounded,
            text: email.isEmpty ? 'Your school email' : email,
          ),
          const SizedBox(height: AppSpacing.xl),
          TextButton(
            onPressed: _isSubmitting ? null : _resendConfirmationEmail,
            child: const Text('Resend confirmation email'),
          ),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    _stopEmailVerificationPoll();
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
              controller: _lastNameController,
              label: 'Last name',
              hint: 'e.g. Santos',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.md),
            _textField(
              controller: _firstNameController,
              label: 'First name',
              hint: 'e.g. Maria',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.md),
            _textField(
              controller: _suffixController,
              label: 'Suffix (optional)',
              hint: 'Jr., Sr., III — leave blank if none',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
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
          if (_buildCaptchaField() case final captcha?) captcha,
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
    String? sheetCaptchaToken;
    final captchaSiteKey = _securityConfig.captchaSiteKey;
    final needsCaptcha =
        _securityConfig.captchaEnabled &&
        captchaSiteKey != null &&
        captchaSiteKey.isNotEmpty;

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
              if (needsCaptcha &&
                  (sheetCaptchaToken == null ||
                      sheetCaptchaToken!.trim().isEmpty)) {
                _showMessage(
                  'Complete the security check, then try again.',
                  isError: true,
                );
                return;
              }
              final navigator = Navigator.of(sheetContext);
              setSheetState(() => isSending = true);
              try {
                await _auth.requestPasswordReset(
                  email: email,
                  captchaToken: sheetCaptchaToken,
                );
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
                  if (needsCaptcha) ...[
                    const SizedBox(height: AppSpacing.md),
                    TurnstileCaptchaField(
                      siteKey: captchaSiteKey,
                      onToken: (token) {
                        sheetCaptchaToken = token;
                      },
                    ),
                  ],
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
            onTap: () {
              setState(() {
                _mode = _AuthMode.login;
                _resetCaptchaChallenge();
              });
              _scheduleRegisterDraftSave();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _modeButton(
            label: 'Register',
            icon: Icons.person_add_alt_1_rounded,
            selected: _mode == _AuthMode.register,
            onTap: () {
              setState(() {
                _mode = _AuthMode.register;
                _resetCaptchaChallenge();
              });
              _scheduleRegisterDraftSave();
            },
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
              : (value) {
                  setState(() => _selectedDepartment = value);
                  _scheduleRegisterDraftSave();
                },
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
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
    final isRegister = _mode == _AuthMode.register;
    final password = _passwordController.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(isRegister ? 'Enter New Password' : 'Password'),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _isSubmitting ? null : _submit(),
          autofillHints: isRegister
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
          decoration: _inputDecoration(
            hint: isRegister ? 'Create a strong password' : 'Your account password',
            icon: Icons.password_rounded,
          ).copyWith(
            suffixIconConstraints: const BoxConstraints(
              minHeight: 48,
              minWidth: 48,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (password.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _passwordController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.cancel_rounded),
                    color: AppColors.neutralMuted,
                  ),
                IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isRegister) ...[
          const SizedBox(height: AppSpacing.sm),
          PasswordRequirementsChecklist(password: password),
        ],
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
