import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/auth/safe_logout.dart';
import '../models/admin_models.dart';

class AdminService {
  const AdminService();

  String? get currentEmail =>
      SupabaseService.requiredClient.auth.currentUser?.email;

  /// Emits whenever the auth session changes (sign-in, sign-out, token
  /// refresh, initial session restore). The admin screen listens to this so
  /// its access check re-runs after the session settles instead of only once.
  Stream<AuthState> authStateChanges() =>
      SupabaseService.requiredClient.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await SupabaseService.requiredClient.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await SafeLogout.run();
  }

  Future<AdminOverview> fetchOverview() async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_dashboard_overview',
    );
    final rows = data as List<dynamic>;
    if (rows.isEmpty) {
      throw StateError('not_authorized');
    }
    return AdminOverview.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<List<AdminRechargeRequest>> fetchRechargeRequests({
    String? status,
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_recharge_requests',
      params: {'p_status': status, 'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map(
          (item) => AdminRechargeRequest.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> approveRecharge(String requestId, {String? note}) async {
    await SupabaseService.requiredClient.rpc(
      'approve_recharge_request',
      params: {'p_request_id': requestId, 'p_admin_note': note},
    );
  }

  Future<void> rejectRecharge(String requestId, String reason) async {
    await SupabaseService.requiredClient.rpc(
      'reject_recharge_request',
      params: {'p_request_id': requestId, 'p_reject_reason': reason},
    );
  }

  Future<AdminWalletSummary?> lookupWallet(String publicUserId) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_wallet_lookup_by_public_id',
      params: {'p_public_user_id': publicUserId},
    );
    final rows = data as List<dynamic>;
    if (rows.isEmpty) {
      return null;
    }
    return AdminWalletSummary.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<AdminWalletSummary?> adjustWallet({
    required String userId,
    required int coinsDelta,
    required int diamondsDelta,
    String? note,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_manual_wallet_adjustment',
      params: {
        'p_user_id': userId,
        'p_coins_delta': coinsDelta,
        'p_diamonds_delta': diamondsDelta,
        'p_note': note,
      },
    );
    return null;
  }

  Future<List<AdminWalletTransaction>> fetchWalletTransactions({
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_wallet_transactions',
      params: {'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map(
          (item) =>
              AdminWalletTransaction.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<AdminGiftTransaction>> fetchGiftTransactions({
    int limit = 30,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_gift_transactions',
      params: {'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map(
          (item) => AdminGiftTransaction.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<AdminAgency>> fetchAgencies() async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_recharge_agencies',
    );
    return (data as List<dynamic>)
        .map((item) => AdminAgency.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminAgent>> fetchAgents() async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_recharge_agents',
    );
    return (data as List<dynamic>)
        .map((item) => AdminAgent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminUserSummary>> searchUsers({
    String? query,
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_search_users',
      params: {'p_query': query, 'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map((item) => AdminUserSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Resolve a free-text query (UUID / Golden ID / username / name) to a list
  /// of matching users, for use by VIP grant / revoke / Golden ID actions.
  ///
  /// Uses [admin_find_user_for_grants] which is safe against invalid UUID casts.
  /// Limit is capped at 10 — this is a targeted lookup, not a bulk search.
  Future<List<AdminUserSummary>> findUsersForGrants(String query) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_find_user_for_grants',
      params: {'p_query': query.trim(), 'p_limit': 10},
    );
    return (data as List<dynamic>).map((item) {
      final m = item as Map<String, dynamic>;
      return AdminUserSummary(
        userId:              m['user_id']?.toString()           ?? '',
        publicUserId:        m['golden_id']?.toString(),
        displayName:         m['display_name']?.toString(),
        username:            m['username']?.toString(),
        avatarUrl:           m['avatar_url']?.toString(),
        vipLevel:            (m['vip_level'] as int?)           ?? 0,
        isGoldenId:          m['is_golden_id'] == true,
        goldenIdExpiresAt:   m['golden_id_expires_at'] != null
            ? DateTime.tryParse(m['golden_id_expires_at'].toString())
            : null,
        goldenIdStyle:         m['golden_id_style']?.toString()          ?? 'gold',
        goldenIdFrame:         m['golden_id_frame']?.toString()          ?? 'classic',
        country:               m['country']?.toString(),
        countryCode:           m['country_code']?.toString(),
        countryFlagStyle:      m['country_flag_style']?.toString()       ?? 'normal',
        countryFlagFrame:      m['country_flag_frame']?.toString()       ?? 'classic',
        countryFlagExpiresAt:  m['country_flag_expires_at'] != null
            ? DateTime.tryParse(m['country_flag_expires_at'].toString())
            : null,
        coinsBalance:          0,
        diamondsBalance:     0,
        roles:               const [],
      );
    }).toList();
  }

  Future<Map<String, dynamic>> setUserCountryFlagStyle({
    required String userId,
    String? countryCode,
    String? countryName,
    required String style,
    required String frame,
    int? durationDays,
  }) async {
    final params = <String, dynamic>{
      'p_user_id': userId,
      'p_style':   style,
      'p_frame':   frame,
    };
    if (countryCode != null && countryCode.isNotEmpty) params['p_country_code'] = countryCode;
    if (countryName != null && countryName.isNotEmpty) params['p_country_name'] = countryName;
    if (durationDays != null) params['p_duration_days'] = durationDays;
    final raw = await SupabaseService.requiredClient.rpc(
      'set_user_country_flag_style',
      params: params,
    );
    return Map<String, dynamic>.from(raw as Map);
  }


  Future<void> assignUserRole({
    required String userId,
    required String role,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_assign_user_role',
      params: {'p_user_id': userId, 'p_role': role},
    );
  }

  Future<void> removeUserRole({
    required String userId,
    required String role,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_remove_user_role',
      params: {'p_user_id': userId, 'p_role': role},
    );
  }

  Future<List<AdminWithdrawalRequest>> fetchWithdrawalRequests({
    String status = 'pending',
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient
        .from('withdrawal_requests')
        .select(
          'id, user_id, diamonds, gross_usd, host_share_usd, agency_share_usd, platform_share_usd, method, account_details, notes, status, created_at, profiles(public_user_id, display_name)',
        )
        .eq('status', status)
        .order('created_at')
        .limit(limit);
    return (data as List<dynamic>).map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      final profile = m['profiles'] as Map<String, dynamic>?;
      m['public_user_id'] = profile?['public_user_id'];
      m['display_name'] = profile?['display_name'];
      return AdminWithdrawalRequest.fromJson(m);
    }).toList();
  }

  Future<void> approveWithdrawal(String requestId) async {
    await SupabaseService.requiredClient.rpc(
      'admin_approve_withdrawal',
      params: {'p_request_id': requestId},
    );
  }

  Future<void> rejectWithdrawal(String requestId, String reason) async {
    await SupabaseService.requiredClient.rpc(
      'admin_reject_withdrawal',
      params: {'p_request_id': requestId, 'p_admin_note': reason},
    );
  }

  Future<List<AdminRoomSummary>> fetchRooms({int limit = 50}) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_rooms',
      params: {'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map((item) => AdminRoomSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminGiftSummary>> fetchGifts({int limit = 100}) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_gifts',
      params: {'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map((item) => AdminGiftSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> setGiftActive({
    required String giftId,
    required bool isActive,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_gift_active',
      params: {'p_gift_id': giftId, 'p_is_active': isActive},
    );
  }

  Future<void> setAgencyActive({
    required String agencyId,
    required bool isActive,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_recharge_agency_active',
      params: {'p_agency_id': agencyId, 'p_is_active': isActive},
    );
  }

  Future<void> setAgentActive({
    required String agentId,
    required bool isActive,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_recharge_agent_active',
      params: {'p_agent_id': agentId, 'p_is_active': isActive},
    );
  }

  Future<List<AdminAuditLog>> fetchAuditLogs({int limit = 50}) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_audit_logs',
      params: {'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map((item) => AdminAuditLog.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> createAgency({
    required String name,
    required String code,
    String? country,
    String? whatsapp,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_create_recharge_agency',
      params: {
        'p_name': name,
        'p_code': code,
        'p_country': country,
        'p_whatsapp': whatsapp,
        'p_commission_rate': 0,
      },
    );
  }

  Future<void> createAgent({
    required String agencyCode,
    required String name,
    required String code,
    String? whatsapp,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_create_recharge_agent',
      params: {
        'p_agency_code': agencyCode,
        'p_name': name,
        'p_code': code,
        'p_whatsapp': whatsapp,
        'p_commission_rate': 0,
      },
    );
  }

  Future<String> updateGift({
    String? giftId,
    String? code,
    String? name,
    String? arabicName,
    int? priceCoins,
    String? icon,
    String category = 'hot',
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_update_gift',
      params: {
        'p_gift_id': giftId,
        'p_code': code,
        'p_name': name,
        'p_arabic_name': arabicName,
        'p_price_coins': priceCoins,
        'p_icon': icon,
        'p_category': category,
        'p_is_active': isActive,
        'p_sort_order': sortOrder,
      },
    );
    return data.toString();
  }

  Future<AdminUserDetail?> fetchUserDetail(String userId) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_user_detail',
      params: {'p_user_id': userId},
    );
    final rows = data as List<dynamic>;
    if (rows.isEmpty) return null;
    return AdminUserDetail.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? username,
    String? avatarUrl,
    String? bio,
    int? vipLevel,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_user_profile',
      params: {
        'p_user_id': userId,
        'p_display_name': displayName,
        'p_username': username,
        'p_avatar_url': avatarUrl,
        'p_bio': bio,
        'p_vip_level': vipLevel,
      },
    );
  }

  Future<void> setUserRestriction({
    required String userId,
    required String restrictionType,
    required bool isActive,
    String? reason,
    DateTime? expiresAt,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_user_restriction',
      params: {
        'p_user_id': userId,
        'p_restriction_type': restrictionType,
        'p_is_active': isActive,
        'p_reason': reason,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
      },
    );
  }

  Future<List<AdminUserLedgerRow>> fetchUserWalletTransactions(
    String userId, {
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_user_wallet_transactions',
      params: {'p_user_id': userId, 'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map(
          (item) => AdminUserLedgerRow.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<AdminUserRechargeRow>> fetchUserRechargeRequests(
    String userId, {
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_user_recharge_requests',
      params: {'p_user_id': userId, 'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map(
          (item) => AdminUserRechargeRow.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<AdminUserGiftRow>> fetchUserGiftTransactions(
    String userId, {
    int limit = 50,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_user_gift_transactions',
      params: {'p_user_id': userId, 'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map((item) => AdminUserGiftRow.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> closeRoom({required String roomId, String? reason}) async {
    await SupabaseService.requiredClient.rpc(
      'admin_close_room',
      params: {'p_room_id': roomId, 'p_reason': reason},
    );
  }

  Future<void> reopenRoom({required String roomId}) async {
    await SupabaseService.requiredClient.rpc(
      'admin_reopen_room',
      params: {'p_room_id': roomId},
    );
  }

  Future<void> kickRoomMember({
    required String roomId,
    required String userId,
    String? reason,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_kick_room_member',
      params: {'p_room_id': roomId, 'p_user_id': userId, 'p_reason': reason},
    );
  }

  Future<AdminFinanceReport?> fetchFinanceReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_finance_report',
      params: {
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    final rows = data as List<dynamic>;
    if (rows.isEmpty) return null;
    return AdminFinanceReport.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<List<AdminBdReportRow>> fetchBdReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_bd_report',
      params: {
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    return (data as List<dynamic>)
        .map((item) => AdminBdReportRow.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminAvatarFrameSummary>> fetchAvatarFrames({
    int limit = 200,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_avatar_frames',
      params: {'p_limit': limit},
    );
    return (data as List<dynamic>)
        .map(
          (item) =>
              AdminAvatarFrameSummary.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> updateAvatarFrame({
    required String frameKey,
    required String name,
    required String category,
    int? vipLevel,
    int? requiredVipLevel,
    String? assetUrl,
    bool isActive = true,
    bool isFeatured = false,
    int sortOrder = 0,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_avatar_frame',
      params: {
        'p_frame_key': frameKey,
        'p_name': name,
        'p_category': category,
        'p_vip_level': vipLevel,
        'p_required_vip_level': requiredVipLevel,
        'p_asset_url': assetUrl,
        'p_is_active': isActive,
        'p_is_featured': isFeatured,
        'p_sort_order': sortOrder,
      },
    );
  }

  Future<List<AdminVipPackage>> fetchVipPackages() async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_vip_packages',
    );
    return (data as List<dynamic>)
        .map((item) => AdminVipPackage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateVipPackage({
    required int vipLevel,
    required String code,
    required String name,
    String? arabicName,
    int priceCoins = 0,
    int durationDays = 30,
    String? badgeLabel,
    String? entranceBannerKey,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_vip_package',
      params: {
        'p_vip_level': vipLevel,
        'p_code': code,
        'p_name': name,
        'p_arabic_name': arabicName,
        'p_price_coins': priceCoins,
        'p_duration_days': durationDays,
        'p_badge_label': badgeLabel,
        'p_entrance_banner_key': entranceBannerKey,
        'p_is_active': isActive,
        'p_sort_order': sortOrder,
      },
    );
  }

  Future<List<AdminEntranceBanner>> fetchEntranceBanners() async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_entrance_banners',
    );
    return (data as List<dynamic>)
        .map(
          (item) => AdminEntranceBanner.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> updateEntranceBanner({
    required String bannerKey,
    required String name,
    String? arabicName,
    int? vipLevel,
    String? assetUrl,
    String? gradientStart,
    String? gradientEnd,
    String? messageTemplate,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_entrance_banner',
      params: {
        'p_banner_key': bannerKey,
        'p_name': name,
        'p_arabic_name': arabicName,
        'p_vip_level': vipLevel,
        'p_asset_url': assetUrl,
        'p_gradient_start': gradientStart,
        'p_gradient_end': gradientEnd,
        'p_message_template': messageTemplate,
        'p_is_active': isActive,
        'p_sort_order': sortOrder,
      },
    );
  }

  Future<List<AdminGiftCategory>> fetchGiftCategories() async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_gift_categories',
    );
    return (data as List<dynamic>)
        .map((item) => AdminGiftCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateGiftCategory({
    required String categoryKey,
    required String name,
    String? arabicName,
    String? icon,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_gift_category',
      params: {
        'p_category_key': categoryKey,
        'p_name': name,
        'p_arabic_name': arabicName,
        'p_icon': icon,
        'p_is_active': isActive,
        'p_sort_order': sortOrder,
      },
    );
  }

  Future<void> grantVip({
    required String userId,
    required int vipLevel,
    int days = 30,
    String? title,
  }) async {
    try {
      await SupabaseService.requiredClient.rpc(
        'admin_grant_vip',
        params: {
          'p_user_id': userId,
          'p_vip_level': vipLevel,
          'p_days': days,
          'p_title': title,
        },
      );
    } catch (e) {
      debugPrint('[AdminService] grantVip error: $e');
      rethrow;
    }
  }

  Future<void> setGoldenId({
    required String userId,
    required String publicUserId,
    required bool isGolden,
    DateTime? expiresAt,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_set_user_golden_id',
      params: {
        'p_user_id': userId,
        'p_public_user_id': publicUserId,
        'p_is_golden': isGolden,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
      },
    );
  }

  // ── Promotional Banners ────────────────────────────────────────────────────

  Future<List<AdminPromoBanner>> fetchPromoBanners() async {
    final data = await SupabaseService.requiredClient
        .from('promo_banners')
        .select()
        .order('sort_order', ascending: true);
    return (data as List<dynamic>)
        .map((e) => AdminPromoBanner.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> upsertPromoBanner({
    String? id,
    required String slideKey,
    required int sortOrder,
    required bool isActive,
    required String labelEn,
    required String labelAr,
    required String titleEn,
    required String titleAr,
    required String subtitleEn,
    required String subtitleAr,
    required String ctaEn,
    required String ctaAr,
    required String iconName,
    String? gradientStart,
    String? gradientMid,
    String? gradientEnd,
    String? iconBgColor,
    String? imageUrl,
    String? targetRoute,
  }) async {
    final payload = <String, dynamic>{
      'slide_key': slideKey,
      'sort_order': sortOrder,
      'is_active': isActive,
      'label_en': labelEn,
      'label_ar': labelAr,
      'title_en': titleEn,
      'title_ar': titleAr,
      'subtitle_en': subtitleEn,
      'subtitle_ar': subtitleAr,
      'cta_en': ctaEn,
      'cta_ar': ctaAr,
      'icon_name': iconName,
      'gradient_start': gradientStart,
      'gradient_mid': gradientMid,
      'gradient_end': gradientEnd,
      'icon_bg_color': iconBgColor,
      'image_url': imageUrl,
      'target_route': targetRoute,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (id != null) payload['id'] = id;
    await SupabaseService.requiredClient
        .from('promo_banners')
        .upsert(payload, onConflict: 'slide_key');
  }

  Future<void> deletePromoBanner(String id) async {
    await SupabaseService.requiredClient
        .from('promo_banners')
        .delete()
        .eq('id', id);
  }

  // ── Withdrawal history ─────────────────────────────────────────────────────

  Future<List<AdminWithdrawalRequest>> fetchWithdrawalHistory({
    int limit = 100,
  }) async {
    final data = await SupabaseService.requiredClient
        .from('withdrawal_requests')
        .select(
          'id, user_id, diamonds, gross_usd, host_share_usd, agency_share_usd, platform_share_usd, method, account_details, notes, status, created_at, profiles(public_user_id, display_name)',
        )
        .inFilter('status', ['approved', 'rejected'])
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List<dynamic>).map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      final profile = m['profiles'] as Map<String, dynamic>?;
      m['public_user_id'] = profile?['public_user_id'];
      m['display_name'] = profile?['display_name'];
      return AdminWithdrawalRequest.fromJson(m);
    }).toList();
  }

  // ── Audit log search ───────────────────────────────────────────────────────

  Future<List<AdminAuditLog>> searchAuditLogs({
    String? actorId,
    String? action,
    String? targetType,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_search_audit_logs',
      params: {
        'p_actor_id':    actorId,
        'p_action':      action,
        'p_target_type': targetType,
        'p_from':        from?.toUtc().toIso8601String(),
        'p_to':          to?.toUtc().toIso8601String(),
        'p_limit':       limit,
      },
    );
    return (data as List<dynamic>)
        .map((item) => AdminAuditLog.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // ── Agency update ──────────────────────────────────────────────────────────

  Future<void> updateAgency({
    required String agencyId,
    String? name,
    String? whatsapp,
    String? country,
    double? commissionRate,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_recharge_agency',
      params: {
        'p_agency_id':       agencyId,
        'p_name':            name,
        'p_whatsapp':        whatsapp,
        'p_country':         country,
        'p_commission_rate': commissionRate,
      },
    );
  }

  // ── Reports ────────────────────────────────────────────────────────────────

  Future<List<AdminReport>> fetchReports({
    String? status,
    String? targetType,
    int limit = 100,
  }) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_list_reports',
      params: {
        'p_status':      status,
        'p_target_type': targetType,
        'p_limit':       limit,
      },
    );
    return (data as List<dynamic>)
        .map((item) => AdminReport.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ModerationEvidence>> fetchReportEvidence(String reportId) async {
    final data = await SupabaseService.requiredClient.rpc(
      'admin_get_report_evidence',
      params: {'p_report_id': reportId},
    );
    return (data as List<dynamic>)
        .map((item) => ModerationEvidence.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> adjustWealthXp({
    required String userId,
    required String action, // 'add' | 'remove'
    required int amount,
    required String reason,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'super_admin_adjust_wealth_xp',
      params: {
        'p_target_user_id': userId,
        'p_action':         action,
        'p_amount':         amount,
        'p_reason':         reason,
      },
    );
  }

  Future<void> setWealthXp({
    required String userId,
    required int xp,
    required String reason,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'super_admin_set_wealth_xp',
      params: {
        'p_target_user_id': userId,
        'p_xp':             xp,
        'p_reason':         reason,
      },
    );
  }

  Future<void> updateReportStatus({
    required String reportId,
    required String status,
    String? resolutionNote,
  }) async {
    await SupabaseService.requiredClient.rpc(
      'admin_update_report_status',
      params: {
        'p_report_id':       reportId,
        'p_status':          status,
        'p_resolution_note': resolutionNote,
      },
    );
  }

  // ── Asset upload (Supabase Storage → admin-assets bucket) ─────────────────

  Future<String> uploadAdminAsset({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final client = SupabaseService.requiredClient;
    // Strip directory components and allow only safe characters.
    final baseName = filename.split(RegExp(r'[/\\]')).last;
    final safe = baseName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final safeName = safe.isEmpty ? 'banner.jpg' : safe;
    final path = 'banners/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await client.storage
        .from('admin-assets')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return client.storage.from('admin-assets').getPublicUrl(path);
  }
}
