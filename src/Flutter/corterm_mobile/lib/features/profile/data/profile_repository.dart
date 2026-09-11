import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/config/app_config.dart';

/// 用户资料（对齐 Gateway GET /api/me/profile）。
class UserProfile {
  UserProfile({
    required this.id,
    required this.username,
    this.email,
    this.displayName,
    required this.hasPassword,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String? email;
  final String? displayName;
  final bool hasPassword;

  /// 相对路径（如 /api/users/{id}/avatar）或外部 URL；null 表示未设置。
  final String? avatarUrl;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String?,
        displayName: json['displayName'] as String?,
        hasPassword: json['hasPassword'] as bool? ?? false,
        avatarUrl: json['avatarUrl'] as String?,
      );
}

/// 资料数据源（对齐 Gateway /api/me/profile、/api/me/avatar）。
class ProfileRepository {
  ProfileRepository(this._client, this._baseUrl);

  final ApiClient _client;
  final String _baseUrl;

  Future<UserProfile> get() async {
    final json = await _client.getMap('/api/me/profile');
    return UserProfile.fromJson(json);
  }

  Future<void> updateDisplayName(String displayName) async {
    try {
      await _client.postMap('/api/me/profile', {'displayName': displayName});
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  /// 上传头像：PNG base64 以 text/plain 直传（MAUI 同款；服务端上限 2MB）。
  Future<String> uploadAvatar(Uint8List bytes) async {
    try {
      final json = await _client.postText('/api/me/avatar', base64Encode(bytes));
      final url = json['avatarUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw ApiException(0, serverMessage: 'avatar upload returned no url');
      }
      return url;
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }

  /// 头像展示地址（相对路径补全 gateway 前缀）。
  String resolveAvatarUrl(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty || avatarUrl.startsWith('http')) {
      return avatarUrl ?? '';
    }
    return '$_baseUrl$avatarUrl';
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider), ref.watch(appConfigProvider));
});
