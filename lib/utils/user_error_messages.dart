import 'package:omr_app/services/cloud_auth_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps technical failures to short, teacher-friendly English.
abstract final class UserErrorMessages {
  static String friendlyError(Object error) {
    if (error is CloudAuthException) {
      return error.message;
    }
    if (error is AuthException) {
      return _friendlyAuthMessage(error.message);
    }
    if (error is PostgrestException) {
      return _friendlyDatabaseMessage(error.message);
    }
    if (error is DatabaseException) {
      return _friendlySqliteMessage(error.toString());
    }

    final text = error.toString();
    if (_looksLikeSqlite(text)) {
      return _friendlySqliteMessage(text);
    }
    if (_looksLikePolicy(text)) {
      return 'Account setup incomplete. Contact your administrator.';
    }
    final network = _friendlyNetworkMessage(text);
    if (network != text) {
      return network;
    }

    return 'Something went wrong. Try again.';
  }

  static String friendlySyncError(Object error) {
    return 'Sync failed. ${friendlyError(error)}';
  }

  static String friendlySaveError(Object error) {
    if (error is DatabaseException || _looksLikeSqlite(error.toString())) {
      return 'Could not save on this phone. Close other apps and try again.';
    }
    return friendlyError(error);
  }

  static String friendlyImportError(String? detail) {
    if (detail == null || detail.trim().isEmpty) {
      return 'Import failed. Check the file format and try again.';
    }
    if (_looksLikeSqlite(detail) || _looksLikePolicy(detail)) {
      return friendlyError(detail);
    }
    return detail.length > 120
        ? 'Import failed. Check the file format and try again.'
        : detail;
  }

  static bool _looksLikeSqlite(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('databaseexception') ||
        normalized.contains('sqlite') ||
        normalized.contains('pragma') ||
        normalized.contains('no such table');
  }

  static bool _looksLikePolicy(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('row-level security') ||
        normalized.contains('violates row-level security') ||
        normalized.contains('permission denied') ||
        normalized.contains('policy');
  }

  static String _friendlySqliteMessage(String text) {
    return 'Could not save on this phone. Close other apps and try again.';
  }

  static String _friendlyAuthMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login credentials')) {
      return 'The email or password is incorrect. Check the account details or reset the password in Supabase.';
    }
    if (normalized.contains('email not confirmed')) {
      return 'This email has not been confirmed yet. Open the confirmation email, then sign in again.';
    }
    if (normalized.contains('user already registered') ||
        normalized.contains('already been registered')) {
      return 'An account with this email already exists. Use Login instead.';
    }
    if (normalized.contains('password')) {
      return 'The password does not meet requirements. Use at least 6 characters.';
    }
    if (normalized.contains('rate limit') || normalized.contains('too many')) {
      return 'Too many attempts. Wait a minute, then try again.';
    }
    return message;
  }

  static String _friendlyDatabaseMessage(String message) {
    if (_looksLikePolicy(message)) {
      return 'Account setup incomplete. Contact your administrator.';
    }
    return message;
  }

  static String _friendlyNetworkMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('failed to fetch') ||
        normalized.contains('xmlhttprequest') ||
        normalized.contains('clientexception') ||
        normalized.contains('socketexception') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('network')) {
      return 'Could not reach the server. Check your internet connection and try again.';
    }
    return message;
  }
}
