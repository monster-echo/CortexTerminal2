import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// 一条邀请收益记录（对齐 Gateway GET /api/referral/me rewards[]）。
class ReferralReward {
  ReferralReward({
    required this.invitedUsername,
    required this.rewardDays,
    required this.createdAtUtc,
  });

  final String invitedUsername;
  final int rewardDays;
  final String createdAtUtc;
}

/// 邀请总览（对齐 Gateway GET /api/referral/me）。
class ReferralSummary {
  ReferralSummary({
    required this.code,
    required this.rewardDaysPerInvite,
    required this.invitedCount,
    required this.totalRewardDays,
    required this.rewards,
  });

  final String code;
  final int rewardDaysPerInvite;
  final int invitedCount;
  final int totalRewardDays;
  final List<ReferralReward> rewards;
}

/// 会员 / 兑换码 / 邀请（对齐 Gateway billing + referral 端点）。
class MembershipRepository {
  MembershipRepository(this._client);

  final ApiClient _client;

  /// 兑换会员码（POST /api/billing/redeem）。失败抛 [ApiException]。
  Future<void> redeemCode(String code) async {
    try {
      await _client.postMap('/api/billing/redeem', {'code': code.trim().toUpperCase()});
    } on DioException catch (e) {
      throw ApiClient.throwFor(e);
    }
  }

  Future<ReferralSummary> referral() async {
    try {
      final json = await _client.getMap('/api/referral/me');
      final rawRewards = json['rewards'] as List<dynamic>? ?? const [];
      return ReferralSummary(
        code: json['code'] as String? ?? '',
        rewardDaysPerInvite: json['rewardDaysPerInvite'] as int? ?? 0,
        invitedCount: json['invitedCount'] as int? ?? 0,
        totalRewardDays: json['totalRewardDays'] as int? ?? 0,
        rewards: rawRewards.map((raw) {
          final map = raw as Map<String, dynamic>;
          return ReferralReward(
            invitedUsername: map['invitedUsername'] as String? ?? '',
            rewardDays: map['rewardDays'] as int? ?? 0,
            createdAtUtc: map['createdAtUtc'] as String? ?? '',
          );
        }).toList(),
      );
    } on DioException catch (e) {
      throw ApiClient.throwFor(e);
    }
  }

  /// 绑定好友邀请码（POST /api/referral/apply）。一次性，服务端强校验。
  Future<void> applyReferralCode(String code) async {
    try {
      await _client.postMap('/api/referral/apply', {'code': code.trim().toUpperCase()});
    } on DioException catch (e) {
      throw ApiClient.throwFor(e);
    }
  }
}

final membershipRepositoryProvider =
    Provider<MembershipRepository>((ref) => MembershipRepository(ref.watch(apiClientProvider)));

final referralSummaryProvider = FutureProvider<ReferralSummary>((ref) {
  return ref.watch(membershipRepositoryProvider).referral();
});
