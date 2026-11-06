import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart' as app_config;

/// services/auth_service.dart — OPTIONAL Google sign-in, synced with the
/// মুক্তিবেগ game server (same architecture as SSC Quest / SSC Bookshelf):
///
///   GoogleSignIn (mobile) → OpenID id_token
///        → POST /api/freescanner/auth/google/token  {idToken}
///        → server verifies + returns an app-scoped JWT + profile
///        → GET  /api/freescanner/user (Bearer JWT)
///        → POST /api/freescanner/account/delete (Play-compliance shape;
///          the backend stores no FreeScanner data, so deletion is instant)
///
/// FreeScanner is local-first: nothing about scans, OCR or exports ever
/// leaves the device. Signing in only syncs the account identity, and every
/// feature works without it.
class AuthService {
  AuthService({required this.prefs, http.Client? client})
      : _client = client ?? http.Client();

  static const _tokenKey = 'freescanner.auth.jwt';
  static const _userKey = 'freescanner.auth.user';

  final SharedPreferences prefs;
  final http.Client _client;

  bool _googleInitialized = false;

  /// True when the app was built with a Google server client id.
  bool get isConfigured => app_config.AppConfig.googleServerClientId.isNotEmpty;

  Future<String?> _storedToken() async => prefs.getString(_tokenKey);

  Future<void> _persist(String? token, AuthUser? user) async {
    if (token == null) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } else {
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, jsonEncode(user!.toJson()));
    }
  }

  AuthUser? _storedUser() {
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Signs in with Google and exchanges the id_token with the backend.
  /// Returns the profile, or throws [AuthException] with a user-facing
  /// message.
  Future<AuthUser> signIn() async {
    if (!isConfigured) {
      throw const AuthException(
        'Sign-in is not configured in this build '
        '(GOOGLE_SERVER_CLIENT_ID missing).',
      );
    }
    try {
      final googleSignIn = GoogleSignIn.instance;
      if (!_googleInitialized) {
        await googleSignIn.initialize(
          serverClientId: app_config.AppConfig.googleServerClientId,
        );
        _googleInitialized = true;
      }
      final account = await googleSignIn.authenticate();
      final authentication = account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null) {
        throw const AuthException(
          'Google did not return an identity token. Check that the server '
          'client id matches the backend GOOGLE_CLIENT_ID.',
        );
      }
      final user = await _exchangeToken(idToken);
      return user;
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw AuthException(_googleMessage(e));
    } on http.ClientException {
      throw const AuthException('Could not reach the server. Try again later.');
    } on TimeoutException {
      throw const AuthException('Sign-in timed out. Try again.');
    } catch (e) {
      debugPrint('signIn failed: $e');
      throw const AuthException('Sign-in failed. Please try again.');
    }
  }

  String _googleMessage(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Sign-in was cancelled.';
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'The sign-in window could not open. Try again.';
      default:
        return 'Sign-in failed (${e.code.name.replaceAll('_', ' ')}).';
    }
  }

  Future<AuthUser> _exchangeToken(String idToken) async {
    final uri = Uri.parse(
      '${app_config.AppConfig.backendBaseUrl}/api/freescanner/auth/google/token',
    );
    final response = await _client
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'idToken': idToken}),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 503) {
      throw const AuthException(
        'Sign-in is not enabled on the server yet (GOOGLE_CLIENT_ID missing).',
      );
    }
    if (response.statusCode != 200) {
      throw const AuthException('The server rejected the sign-in.');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final token = body['token'] as String?;
    final userJson = body['user'];
    if (token == null || userJson is! Map<String, dynamic>) {
      throw const AuthException('Unexpected server response.');
    }
    final user = AuthUser.fromJson(userJson);
    await _persist(token, user);
    return user;
  }

  /// Restores the session from the stored JWT (validates against /user).
  Future<AuthUser?> restoreSession() async {
    final token = await _storedToken();
    if (token == null) return null;
    try {
      final uri = Uri.parse(
        '${app_config.AppConfig.backendBaseUrl}/api/freescanner/user',
      );
      final response = await _client
          .get(uri, headers: {'authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        final userJson = body['user'];
        if (userJson is Map<String, dynamic>) {
          final user = AuthUser.fromJson(userJson);
          await _persist(token, user);
          return user;
        }
      }
      // 401/403 or shape mismatch → stale session.
      await _persist(null, null);
      return null;
    } catch (_) {
      // Offline: fall back to the cached profile, keep the token.
      return _storedUser();
    }
  }

  /// Signs out of Google (when possible) and clears the local session.
  Future<void> signOut() async {
    try {
      if (_googleInitialized || isConfigured) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {
      // Signing out of Google is best-effort; the local session still clears.
    }
    await _persist(null, null);
  }

  /// Play-compliance account deletion. The backend keeps no FreeScanner
  /// user data, so this simply revokes the session server-side and locally.
  Future<void> deleteAccount() async {
    final token = await _storedToken();
    if (token != null) {
      try {
        final uri = Uri.parse(
          '${app_config.AppConfig.backendBaseUrl}/api/freescanner/account/delete',
        );
        await _client
            .post(
              uri,
              headers: {
                'authorization': 'Bearer $token',
                'content-type': 'application/json',
              },
              body: jsonEncode({'confirm': true}),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Even if the call fails we clear the local session below.
      }
    }
    await signOut();
  }
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'email': email,
        'name': displayName,
        'picture': photoUrl,
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        displayName: json['name']?.toString(),
        photoUrl: json['picture']?.toString(),
      );
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
