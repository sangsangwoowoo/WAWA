// lib/api_service.dart

import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // TimeoutException 사용을 위해 import
import 'package:hive_flutter/hive_flutter.dart';
import 'package:learning_app/models/user_profile.dart';
import 'package:learning_app/models/statistics_model.dart';
import 'package:learning_app/models/study_group_model.dart';
import 'package:learning_app/models/pronunciation_history_model.dart';
import 'package:image_picker/image_picker.dart';
import 'package:learning_app/main.dart';
import 'package:uuid/uuid.dart' show Uuid;
import 'package:url_launcher/url_launcher.dart';
import 'package:learning_app/models/grammar_history_model.dart';
import 'package:learning_app/models/learning_progress_model.dart';
import 'package:learning_app/models/user_word_model.dart';
import 'package:learning_app/models/challenge_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'models/point_history_model.dart';

final String BACKEND_URL = dotenv.env['BACKEND_URL'] ?? 'http://fallback-url.com';
final String AI_BACKEND_URL = dotenv.env['AI_BACKEND_URL'] ?? 'http://fallback-ai-url.com';


// API 통신 중 발생하는 예외를 처리하기 위한 클래스
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  // --- Singleton 설정 ---
  ApiService._privateConstructor();

  static final ApiService _instance = ApiService._privateConstructor();

  factory ApiService() {
    return _instance;
  }

  final Box _userSettingsBox = Hive.box('userSettings');

  // ▼▼▼ [수정] isAdmin 상태를 저장할 변수 추가 ▼▼▼
  bool _isAdmin = false;
  String? _codeVerifier;
  bool get isAdmin => _isAdmin;

  // --- 기본 설정 ---
  static const String _authPlanStatsBaseUrl = String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://15.165.136.44:8001'
  );

  static const String _aiBaseUrl = String.fromEnvironment(
      'AI_BACKEND_URL',
      defaultValue: 'http://15.165.136.44:8000'
  );


  static const Duration _timeoutDuration = Duration(seconds: 30);

  // --- 토큰 및 헤더 관리 ---
  Future<String?> getToken() async {
    return _userSettingsBox.get('auth_token');
  }

  Future<void> saveToken(String token) async {
    await _userSettingsBox.put('auth_token', token);
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> saveAutoLoginPreference(bool autoLogin) async {
    await _userSettingsBox.put('auto_login', autoLogin);
  }

  Future<bool> getAutoLoginPreference() async {
    return _userSettingsBox.get('auto_login', defaultValue: false);
  }

  // 👇 [수정] 로그아웃 시 토큰뿐만 아니라 자동 로그인 설정도 함께 삭제합니다.
  Future<void> logout() async {
    await _userSettingsBox.delete('auth_token');
    await _userSettingsBox.delete('auto_login');
    _isAdmin = false; // ▼▼▼ 로그아웃 시 isAdmin 상태 초기화 ▼▼▼
  }

  Future<Map<String, dynamic>> analyzeAndSavePronunciation({
    required String audioPath,
    required String targetText,
  }) async {
    final userId = AppState.userId;
    if (userId == null) throw ApiException('사용자 ID가 없습니다. 다시 로그인해주세요.');

    // main.py에 정의된 엔드포인트 주소
    final url = Uri.parse('$_aiBaseUrl/api/pronunciation/analyze');
    final headers = await _getAuthHeaders();

    final file = File(audioPath);
    final audioBytes = await file.readAsBytes();
    final base64Audio = base64Encode(audioBytes);

    final body = jsonEncode({
      'audio_base64': base64Audio,
      'target_text': targetText,
      'user_level': AppState.userLevel ?? 'B1',
      'language': 'en',
      // 👇 DB에 저장하기 위한 필수 정보들을 함께 보냅니다.
      'save_to_database': true,
      'user_id': userId,
      'session_id': const Uuid().v4(), // 고유한 세션 ID 생성
    });

    final response = await http.post(url, headers: headers, body: body).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  Future<StatisticsResponse> getStatistics() async {
    final userId = AppState.userId;
    if (userId == null) {
      throw ApiException('사용자 ID를 찾을 수 없습니다. 다시 로그인해주세요.');
    }

    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/api/statistics/statistics/$userId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(
        _timeoutDuration);
    final responseBody = _processResponse(response);

    // JSON 응답을 StatisticsResponse 객체로 변환하여 반환
    return StatisticsResponse.fromJson(responseBody);
  }

  // --- 응답 처리 ---
  dynamic _processResponse(http.Response response) {
    final rawBody = utf8.decode(response.bodyBytes);
    if (rawBody.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {};
      } else {
        throw ApiException('서버로부터 응답이 없습니다.', statusCode: response.statusCode);
      }
    }

    final body = jsonDecode(rawBody);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      // [중요] FastAPI 오류는 'detail', 직접 정의한 오류는 'error' 키로 올 수 있습니다.
      // 이 두 키를 모두 확인하여 백엔드가 보낸 메시지를 ApiException에 담아 throw합니다.
      final errorMessage = body['detail'] ?? body['error'] ?? '알 수 없는 오류가 발생했습니다.';
      throw ApiException(errorMessage, statusCode: response.statusCode);
    }
  }

  // --- API 함수들 ---

  // 회원가입
  Future<Map<String, dynamic>> register(
      {required String email, required String password, required String name}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/register');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'name': name,
        'is_admin': false
      }),
    ).timeout(_timeoutDuration);

    final responseBody = _processResponse(response);
    if (responseBody['access_token'] != null) {
      await saveToken(responseBody['access_token']);
    }
    // 👇 [수정] responseBody를 그대로 반환합니다.
    return responseBody;
  }

  Future<void> createProfile() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/create-profile');
    final headers = await _getAuthHeaders(); // 토큰이 포함된 헤더 가져오기
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    final response = await http.post(url, headers: headers).timeout(
        _timeoutDuration);
    _processResponse(response); // 성공 여부만 확인
  }

  Map<String, dynamic>? _decodeJWT(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // JWT의 payload 부분 디코딩
      final payload = parts[1];
      // Base64 패딩 추가
      var normalizedPayload = payload;
      while (normalizedPayload.length % 4 != 0) {
        normalizedPayload += '=';
      }

      final decoded = utf8.decode(base64.decode(normalizedPayload));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e) {
      print('JWT 디코딩 오류: $e');
      return null;
    }
  }

  // 로그인
  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/login');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': email, 'password': password},
      ).timeout(_timeoutDuration);

      // _processResponse가 모든 응답(성공/실패)을 처리합니다.
      // 실패 시(예: 401 오류) 여기서 ApiException이 throw되어 catch 블록으로 넘어갑니다.
      final responseBody = _processResponse(response);

      // --- 성공 시 로직 ---
      if (responseBody['access_token'] != null) {
        await saveToken(responseBody['access_token']);
        final accountInfo = await getUserProfile();
        _isAdmin = accountInfo['is_admin'] ?? false;
      }
      return responseBody;

    } on TimeoutException {
      throw ApiException('서버 응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.');
    } catch (e) {
      // _processResponse에서 throw된 ApiException 또는 기타 네트워크 예외를 그대로 다시 throw합니다.
      // 이렇게 해야 UI단(_LoginScreenState)에서 구체적인 오류 메시지를 받을 수 있습니다.
      rethrow;
    }
  }

  Future<Map<String, dynamic>> attemptAutoLogin() async {
    final token = await getToken();
    if (token == null) {
      return {'status': 'error', 'message': 'No token found'};
    }

    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/login/auto');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'token': token}),
    ).timeout(_timeoutDuration);

    try {
      final responseBody = _processResponse(response);

      // 현재 저장된 토큰에서 JWT 정보 추출
      final jwtPayload = _decodeJWT(token);
      if (jwtPayload != null) {
        print('=== 자동 로그인 JWT 분석 ===');

        final userMetadata = jwtPayload['user_metadata'] as Map<String,
            dynamic>?;
        final appMetadata = jwtPayload['app_metadata'] as Map<String, dynamic>?;

        bool adminStatus = false;

        if (userMetadata?['is_admin'] is bool) {
          adminStatus = userMetadata!['is_admin'] as bool;
        } else if (appMetadata?['is_admin'] is bool) {
          adminStatus = appMetadata!['is_admin'] as bool;
        } else if (appMetadata?['role'] == 'admin') {
          adminStatus = true;
        }

        _isAdmin = adminStatus;
        print('Auto Login - JWT에서 is_admin: $_isAdmin');
      }

      return responseBody;
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // 사용자 프로필 조회
  Future<Map<String, dynamic>> getUserProfile() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/profile');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(
        _timeoutDuration);
    final responseBody = _processResponse(response);

    print('=== 사용자 프로필 API 응답 ===');
    print('Profile Response: $responseBody');

    // 백엔드에서 user_account 테이블 조인해서 is_admin 포함시켜야 함
    if (responseBody['is_admin'] is bool) {
      _isAdmin = responseBody['is_admin'] as bool;
      print('Profile API에서 is_admin 업데이트: $_isAdmin');
    }

    return responseBody;
  }

  // (참고) /auth/me 엔드포인트용 함수 (현재는 /profile로 통일하여 사용 중)
  Future<UserProfile> getCurrentUser() async {
    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/auth/me'); // 이 엔드포인트는 현재 사용하지 않을 수 있습니다.
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(
        _timeoutDuration);
    final responseBody = _processResponse(response);
    return UserProfile.fromJson(responseBody);
  }

  // 레벨 테스트 결과 업데이트
  Future<void> updateUserLevel(
      {required String userId, required String assessedLevel}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/update-level');
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    final body = jsonEncode({'email': userId, 'assessed_level': assessedLevel});

    final response = await http.post(url, headers: headers, body: body).timeout(
        _timeoutDuration);
    _processResponse(response);
  }

  // 최신 학습 계획 조회
  Future<Map<String, dynamic>?> getLatestLearningPlan() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/plans/latest');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    try {
      final response = await http.get(url, headers: headers).timeout(
          _timeoutDuration);
      // 404 (계획 없음) 오류는 정상적인 상황이므로 null을 반환하여 처리
      if (response.statusCode == 404) {
        return null;
      }
      return _processResponse(response);
    } catch (e) {
      if (e is ApiException && e.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  // 학습 목표(계획) 생성
  Future<Map<String, dynamic>> createLearningPlan({
    required int conversationDuration,
    required int grammarCount,
    required int pronunciationCount,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/plans/create');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    // 백엔드가 요구하는 새로운 요청 본문
    final body = jsonEncode({
      'conversation_duration': conversationDuration,
      'grammar_count': grammarCount,
      'pronunciation_count': pronunciationCount,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 사전 정의된 학습 계획 템플릿 목록을 가져오는 함수
  Future<List<dynamic>> getPlanTemplates() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/plans/templates');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 사용자가 선택한 템플릿으로 학습 계획을 생성하는 함수
  Future<Map<String, dynamic>> selectPlanTemplate({
    required String templateId,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/plans/select-template');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final userId = AppState.userId;
    if (userId == null) throw ApiException('사용자 ID를 찾을 수 없습니다.');

    final body = jsonEncode({
      'user_id': userId,
      'template_id': templateId,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<List<dynamic>> getNotices({int skip = 0, int limit = 20}) async {
    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/api/notices/?skip=$skip&limit=$limit');
    final response = await http.get(url).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> createNotice(
      {required String title, required String content}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/notices/');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        'Admin privileges required.');
    final body = jsonEncode({'title': title, 'content': content});
    final response = await http.post(url, headers: headers, body: body).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> updateNotice(
      {required int noticeId, required String title, required String content}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/notices/$noticeId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        'Admin privileges required.');
    final body = jsonEncode({'title': title, 'content': content});
    final response = await http.put(url, headers: headers, body: body).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  Future<UserProfile> fetchUserProfile() async {
    final json = await getUserProfile(); // 기존 함수 활용
    return UserProfile.fromJson(json);
  }

  Future<void> deleteNotice(int noticeId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/notices/$noticeId');
    final headers = await _getAuthHeaders();

    if (!headers.containsKey('Authorization')) {
      throw ApiException('Admin privileges required.');
    }

    try {
      final response = await http.delete(url, headers: headers).timeout(
          _timeoutDuration);

      // ▼▼▼ 핵심 수정 ▼▼▼
      // 204 No Content 상태 코드는 응답 본문이 없음을 의미합니다.
      // 이 경우 _processResponse를 호출하지 않고 함수를 바로 종료합니다.
      if (response.statusCode == 204) {
        return;
      }

      // 그 외의 모든 응답은 _processResponse 함수에 맡깁니다.
      _processResponse(response);
    } on TimeoutException {
      throw ApiException('요청 시간이 초과되었습니다.');
    } catch (e) {
      // _getAuthHeaders()나 http.delete()에서 발생할 수 있는 다른 예외 처리
      throw ApiException('삭제 실패: $e');
    }
  }

  Future<List<dynamic>> getFAQs({int skip = 0, int limit = 100}) async {
    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/api/faqs/?skip=$skip&limit=$limit');
    final response = await http.get(url).timeout(_timeoutDuration);
    return _processResponse(response);
  }

// FAQ 생성 (관리자용)
  Future<Map<String, dynamic>> createFAQ({
    required String question,
    required String answer,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/faqs/');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('관리자 권한이 필요합니다.');
    }

    final body = jsonEncode({
      'question': question,
      'answer': answer,
    });

    final response = await http.post(url, headers: headers, body: body)
        .timeout(_timeoutDuration);
    return _processResponse(response);
  }

// FAQ 수정 (관리자용)
  Future<Map<String, dynamic>> updateFAQ({
    required int faqId,
    required String question,
    required String answer,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/faqs/$faqId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('관리자 권한이 필요합니다.');
    }

    final body = jsonEncode({
      'question': question,
      'answer': answer,
    });

    final response = await http.put(url, headers: headers, body: body)
        .timeout(_timeoutDuration);
    return _processResponse(response);
  }

// FAQ 삭제 (관리자용)
  Future<void> deleteFAQ(int faqId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/faqs/$faqId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('관리자 권한이 필요합니다.');
    }

    final response = await http.delete(url, headers: headers)
        .timeout(_timeoutDuration);

    if (response.statusCode == 204) {
      return;
    }
    _processResponse(response);
  }

  // --- 출석 체크 API 호출 ---
  Future<Map<String, dynamic>> checkIn() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/attendance/check-in');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final response = await http.post(url, headers: headers).timeout(_timeoutDuration);
    final attendanceResponse = _processResponse(response); // 출석 체크 결과 먼저 처리

    try {
      // executePointTransaction 함수를 호출하여 포인트를 지급합니다.
      final pointResponse = await executePointTransaction(
        amount: 100,
        reason: "출석 체크 보상",
      );
      print("✅ [출석 체크 응답] 백엔드가 보내준 전체 응답: $pointResponse");
      // 반환된 응답에서 final_points 값을 추출
      final newPoints = pointResponse['final_points'];
      if (newPoints != null && newPoints is int) {
        // AppState의 points 값을 새로운 값으로 갱신
        AppState.points.value = newPoints;
        print("✅ 출석 포인트 지급 완료! AppState 업데이트: ${AppState.points}");
      }
    } catch (e) {
      print("⚠️ 출석은 성공했으나 포인트 지급에 실패했습니다: $e");
    }

    return attendanceResponse; // 기존 출석 응답을 그대로 반환
  }

  // --- 출석 기록 조회 API 호출 ---
  Future<List<dynamic>> getAttendanceHistory() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/attendance/history');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  // --- 출석 통계 조회 API 호출 ---
  Future<Map<String, dynamic>> getAttendanceStats() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/attendance/stats');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  // --- 내 알림 목록 조회 API 호출 ---
  Future<List<dynamic>> getMyNotifications(
      {int skip = 0, int limit = 30}) async {
    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/api/notifications/?skip=$skip&limit=$limit');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  // --- 알림 읽음 처리 API 호출 ---
  Future<Map<String, dynamic>> markNotificationAsRead(
      int notificationId) async {
    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/api/notifications/$notificationId/read');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '로그인이 필요합니다.');

    // PATCH 메소드 사용
    final response = await http.patch(url, headers: headers).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  // --- 알림 설정 조회 API 호출 ---
  Future<Map<String, dynamic>> getNotificationSettings() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/notifications/settings');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // --- 알림 설정 업데이트 API 호출 ---
  Future<Map<String, dynamic>> updateNotificationSettings(Map<String, bool> newSettings) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/notifications/settings');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final body = jsonEncode(newSettings);

    final response = await http.patch(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 게시글 목록 조회
  Future<List<dynamic>> getPosts(String category, {String? searchQuery}) async {
    var urlString = '$_authPlanStatsBaseUrl/api/community/posts?category=${Uri.encodeComponent(category)}';
    if (searchQuery != null && searchQuery.isNotEmpty) {
      urlString += '&search=${Uri.encodeComponent(searchQuery)}';
    }
    final url = Uri.parse(urlString);
    final response = await http.get(url).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 게시글 상세 조회
  Future<Map<String, dynamic>> getPostDetail(int postId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/community/posts/$postId');
    final response = await http.get(url).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 게시글 생성
  Future<Map<String, dynamic>> createPost({
    required String title,
    required String content,
    required String category,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/community/posts');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '글을 작성하려면 로그인이 필요합니다.');

    final body = jsonEncode(
        {'title': title, 'content': content, 'category': category});
    final response = await http.post(url, headers: headers, body: body).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  Future<List<dynamic>> getComments(int postId) async {
    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/api/community/posts/$postId/comments');
    final response = await http.get(url).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> createComment({
    required int postId,
    required String content,
  }) async {
    final url = Uri.parse(
        '$_authPlanStatsBaseUrl/api/community/posts/$postId/comments');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException(
        '댓글을 작성하려면 로그인이 필요합니다.');

    final body = jsonEncode({'content': content});
    final response = await http.post(url, headers: headers, body: body).timeout(
        _timeoutDuration);
    return _processResponse(response);
  }

  // 댓글 수정
  Future<Map<String, dynamic>> updateComment({
    required int commentId,
    required String content,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/community/comments/$commentId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('댓글을 수정하려면 로그인이 필요합니다.');

    final body = jsonEncode({'content': content});

    final response = await http.put(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 댓글 삭제
  Future<void> deleteComment({required int commentId}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/community/comments/$commentId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('댓글을 삭제하려면 로그인이 필요합니다.');

    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode == 204) {
      return; // 성공적으로 삭제됨 (No Content)
    }
    _processResponse(response);
  }

  Future<void> addLearningLog({
    required String logType,
    int? duration, // 회화 학습용 (분 단위)
    int? count, // 발음/문법 학습용 (횟수)
  }) async {
    // API 주소는 백엔드의 statistics_api.py에 정의된 경로를 따릅니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/statistics/log/add');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('학습 기록을 저장하려면 로그인이 필요합니다.');
    }

    final body = jsonEncode({
      'log_type': logType,
      'duration': duration,
      'count': count,
    });

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(_timeoutDuration);
      _processResponse(response); // 성공 여부만 확인하고 오류가 있으면 throw
    } catch (e) {
      // API 호출 중 발생한 예외를 다시 던져서 UI에서 처리할 수 있도록 함
      rethrow;
    }
  }

  // ▼▼▼ [추가] 소셜 로그인 URL을 받아오는 함수 ▼▼▼
  Future<Map<String, dynamic>> getSocialLoginUrl(String provider) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/login/$provider');
    final response = await http.get(url).timeout(_timeoutDuration);
    // _processResponse는 {"url": "...", "code_verifier": "..."} 형태의 Map을 반환합니다.
    return _processResponse(response);
  }

  // ▼▼▼ [추가] 받아온 URL을 실행하는 헬퍼 함수 ▼▼▼
  Future<void> launchSocialLogin(String provider) async {
    try {
      // 1. 백엔드로부터 url과 code_verifier를 모두 받습니다.
      final socialLoginData = await getSocialLoginUrl(provider);

      // 2. code_verifier는 변수에 저장합니다.
      _codeVerifier = socialLoginData['code_verifier'] as String?;
      final urlString = socialLoginData['url'] as String?;

      print('✅ 백엔드로부터 받은 소셜 로그인 URL: $urlString');
      print('🤫 임시 저장된 code_verifier: $_codeVerifier');

      if (urlString == null || _codeVerifier == null) {
        throw ApiException('소셜 로그인 정보를 받아오지 못했습니다.');
      }

      // 3. url을 실행합니다.
      final url = Uri.parse(urlString);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw ApiException('$provider 로그인 페이지를 열 수 없습니다.');
      }
    } catch (e) {
      rethrow;
    }
  }

  // ▼▼▼ [추가] 소셜 로그인 후 추가 정보(이메일, 이름)를 업데이트하는 함수 ▼▼▼
  Future<void> updateAdditionalInfo(
      {required String email, required String name}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/update-details');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('추가 정보를 업데이트하려면 로그인이 필요합니다.');
    }

    final body = jsonEncode({
      'email': email,
      'name': name,
    });

    final response = await http
        .patch(url, headers: headers, body: body)
        .timeout(_timeoutDuration);
    _processResponse(response); // 성공 여부만 확인
  }

  Future<void> updateUserLanguages({
    required String nativeLanguage,
    required String targetLanguage,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/update-languages');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('로그인이 필요합니다.');
    }

    final body = jsonEncode({
      'native_language': nativeLanguage,
      'target_language': targetLanguage,
    });

    final response = await http.patch(url, headers: headers, body: body)
        .timeout(_timeoutDuration);
    _processResponse(response);
  }

  Future<Map<String, dynamic>> updateUserCharacter({
    required String characterName,
    required String characterImage,
  }) async {
    // [수정] 사용자 설정을 통합적으로 관리하는 /api/user/settings 엔드포인트를 호출합니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/user/settings');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('캐릭터를 변경하려면 로그인이 필요합니다.');
    }

    final body = jsonEncode({
      'selected_character_name': characterName,
      'selected_character_image': characterImage,
    });

    // PATCH 메소드를 사용하여 요청합니다.
    final response = await http.patch(url, headers: headers, body: body).timeout(_timeoutDuration);

    // 성공 시, 서버는 업데이트된 전체 프로필 정보를 반환합니다.
    return _processResponse(response);
  }

  Future<Map<String, int>> getTodayProgress() async {
    // ✅ /api 추가
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/statistics/today-progress');

    print('=== 요청 URL: $url ===');

    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('로그인이 필요합니다.');
    }

    final response = await http.get(url, headers: headers)
        .timeout(const Duration(seconds: 10));

    print('=== 응답 코드: ${response.statusCode} ===');
    print('=== 응답 본문: ${response.body} ===');

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return {
        'conversation': data['conversation'] ?? 0,
        'grammar': data['grammar'] ?? 0,
        'pronunciation': data['pronunciation'] ?? 0,
      };
    } else {
      throw ApiException('오늘의 진행률 조회 실패: ${response.body}');
    }
  }

  Future<List<StudyGroup>> getStudyGroups() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/list');
    final headers = await _getAuthHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => StudyGroup.fromJson(item)).toList();
    } else {
      throw ApiException('그룹 목록 조회 실패: ${response.body}');
    }
  }

  Future<StudyGroup> createStudyGroup({
    required String name,
    String? description,
    required int maxMembers, // << [수정] required로 변경
    required bool requiresApproval, // << [추가]
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/create');
    final headers = await _getAuthHeaders();

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        'name': name,
        'description': description,
        'max_members': maxMembers,
        'requires_approval': requiresApproval, // << [추가]
      }),
    ).timeout(_timeoutDuration);

    if (response.statusCode == 200) { // 생성은 200 OK로 가정
      return StudyGroup.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw ApiException(error['detail'] ?? '그룹 생성 실패');
    }
  }

  Future<String> joinStudyGroup(int groupId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/join');
    final headers = await _getAuthHeaders();

    final response = await http.post(url, headers: headers).timeout(_timeoutDuration);
    final responseBody = _processResponse(response);

    // 성공 시 백엔드가 보낸 메시지를 그대로 반환
    return responseBody['message'];
  }

  Future<void> leaveStudyGroup(int groupId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/leave');
    final headers = await _getAuthHeaders();

    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw ApiException(error['detail'] ?? '그룹 탈퇴 실패');
    }
  }

  Future<List<GroupMember>> getGroupMembers(int groupId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/members');
    final headers = await _getAuthHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => GroupMember.fromJson(item)).toList();
    } else {
      throw ApiException('멤버 목록 조회 실패');
    }
  }

  Future<void> deleteStudyGroup(int groupId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId');
    final headers = await _getAuthHeaders();

    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode != 200) {
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw ApiException(error['detail'] ?? '그룹 삭제 실패');
    }
  }

  // 발음 이력 조회
  Future<List<PronunciationHistory>> getPronunciationHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/pronunciation/history?limit=$limit&offset=$offset');
    final headers = await _getAuthHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => PronunciationHistory.fromJson(item)).toList();
    } else {
      throw ApiException('발음 이력 조회 실패: ${response.body}');
    }
  }

// 발음 통계 조회
  Future<PronunciationStatistics> getPronunciationStatistics() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/pronunciation/statistics');
    final headers = await _getAuthHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return PronunciationStatistics.fromJson(data);
    } else {
      throw ApiException('통계 조회 실패: ${response.body}');
    }
  }

// 발음 이력 삭제
  Future<void> deletePronunciationHistory(String resultId) async {  // ✅ int → String
    final url = Uri.parse('$_aiBaseUrl/pronunciation/history/$resultId');
    final headers = await _getAuthHeaders();

    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode != 200) {
      throw ApiException('삭제 실패: ${response.body}');
    }
  }

  // 중복 닉네임 검사
  Future<Map<String, dynamic>> checkNameAvailability(String name) async {
    // 이름이 비어있으면 API를 호출하지 않고 즉시 클라이언트에서 처리
    if (name.trim().isEmpty) {
      return {'available': false};
    }

    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/check-name');
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    final requestBody = jsonEncode({'name': name});

    try {
      final response = await http.post(
        url,
        headers: headers,
        body: requestBody,
      ).timeout(_timeoutDuration);

      // _processResponse가 성공(2xx) 시 body를 반환하고,
      // 실패(4xx, 5xx) 시 ApiException을 발생시킵니다.
      return _processResponse(response);

    } catch (e) {
      // ApiException이 아닌 네트워크 오류 등 다른 예외를 다시 throw
      // UI단에서 "이름 확인 중 오류가 발생했습니다." 메시지를 보여줄 수 있습니다.
      rethrow;
    }
  }

  /// 사용자 이름만 수정
  Future<Map<String, dynamic>> updateUserName({
    required String name,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/user/update-name');
    final headers = await _getAuthHeaders();

    if (!headers.containsKey('Authorization')) {
      throw ApiException('로그인이 필요합니다.');
    }

    final body = jsonEncode({'name': name});

    final response = await http.patch(
      url,
      headers: headers,
      body: body,
    ).timeout(_timeoutDuration);

    return _processResponse(response);
  }

  Future<Map<String, dynamic>> startGrammarSession({
    required String language,
    required String level,
  }) async {
    // AI 서버에 새로 추가한 문법 학습 세션 시작 엔드포인트
    final url = Uri.parse('$_aiBaseUrl/api/grammar/start-session');
    final userId = AppState.userId;
    if (userId == null) throw ApiException('User not logged in');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'user_id': userId,
        'language': language,
        'level': level,
      }),
    ).timeout(_timeoutDuration);

    return _processResponse(response);
  }

  Future<Map<String, dynamic>> submitGrammarAnswer({
    required String sessionId,
    required String questionId,
    required String answer,
  }) async {
    // AI 서버에 새로 추가한 문법 답변 제출 엔드포인트
    final url = Uri.parse('$_aiBaseUrl/api/grammar/submit-answer');

    /*
    [중요] 이 함수가 호출하는 AI 서버의 응답 값에 아래 항목들이 포함되어야 합니다.
    {
      "success": true,
      "is_correct": boolean,
      "explanation": "해설 텍스트...",
      "correct_answer_key": "C", // (필수 추가) 정답 옵션의 키 (A, B, C, D 등)
      "corrected_text": "The cat sat on the mat.", // (필수 추가) 정답을 포함한 전체 문장
      "next_question": { ... }
    }
    */
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'session_id': sessionId,
        'question_id': questionId,
        'answer': answer,
      }),
    ).timeout(_timeoutDuration);

    return _processResponse(response);
  }

  // 게시글 수정
  Future<Map<String, dynamic>> updatePost({
    required int postId,
    required String title,
    required String content,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/community/posts/$postId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('글을 수정하려면 로그인이 필요합니다.');

    final body = jsonEncode({'title': title, 'content': content});

    // PUT 메소드를 사용하여 요청
    final response = await http.put(url, headers: headers, body: body).timeout(_timeoutDuration);

    return _processResponse(response);
  }

  // 게시글 삭제
  Future<void> deletePost({required int postId}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/community/posts/$postId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('글을 삭제하려면 로그인이 필요합니다.');

    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);

    // 성공적인 삭제 응답(204 No Content)은 본문(body)이 없으므로
    // _processResponse를 호출하기 전에 별도로 처리합니다.
    if (response.statusCode == 204) {
      return; // 성공적으로 삭제되었으므로 함수 종료
    }

    // 204가 아닌 다른 응답 코드는 기존 방식으로 처리
    _processResponse(response);
  }

  // 내 단어장 목록 가져오기
  Future<List<dynamic>> getWordbooks() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/wordbooks');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 새 단어장 만들기
  Future<Map<String, dynamic>> createWordbook(String name) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/wordbooks');
    final headers = await _getAuthHeaders();
    final body = jsonEncode({'name': name});
    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 단어장 삭제하기
  Future<void> deleteWordbook(int wordbookId) async {
    // 참고: 이 API는 백엔드에 아직 구현되지 않았을 수 있습니다. 추가가 필요합니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/wordbooks/$wordbookId');
    final headers = await _getAuthHeaders();
    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);
    if (response.statusCode == 204) return;
    _processResponse(response);
  }

  // 특정 단어장의 상세 정보(단어 목록 포함) 가져오기
  Future<Map<String, dynamic>> getWordbookDetails(int wordbookId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/wordbooks/$wordbookId');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 단어장에 단어 추가하기
  Future<Map<String, dynamic>> addWordToWordbook({
    required int wordbookId,
    required String word,
    required String definition,
    String? pronunciation,
    String? englishExample,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/wordbooks/$wordbookId/words');
    final headers = await _getAuthHeaders();
    final body = jsonEncode({
      'word': word,
      'definition': definition,
      'pronunciation': pronunciation,
      'english_example': englishExample,
    });
    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> updateWordContent({
    required int wordId,
    required String word,
    required String definition,
    String? pronunciation,
    String? englishExample,
  }) async {
    // PUT /api/vocabulary/words/{word_id} 엔드포인트를 호출합니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/words/$wordId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('단어를 수정하려면 로그인이 필요합니다.');

    final body = jsonEncode({
      'word': word,
      'definition': definition,
      'pronunciation': pronunciation,
      'english_example': englishExample,
    });

    final response = await http.put(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  // 단어 암기 상태 변경하기
  Future<void> updateWordMemorizedStatus({required int wordId, required bool isMemorized}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/words/$wordId');
    final headers = await _getAuthHeaders();
    final body = jsonEncode({'is_memorized': isMemorized});
    await http.patch(url, headers: headers, body: body).timeout(_timeoutDuration);
  }

  // 단어장에서 단어 삭제하기
  Future<void> deleteWord(int wordId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/words/$wordId');
    final headers = await _getAuthHeaders();
    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);
    if (response.statusCode == 204) return;
    _processResponse(response);
  }

  Future<void> addWordsToWordbookBatch({
    required int wordbookId,
    required List<Map<String, dynamic>> words,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/wordbooks/$wordbookId/words/batch');
    final headers = await _getAuthHeaders();
    final body = jsonEncode({'words': words});

    final response = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 120)); // 타임아웃을 2분으로 넉넉하게 설정

    _processResponse(response);
  }

  Future<void> updateWordFavoriteStatus({required int wordId, required bool isFavorite}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/words/$wordId/favorite?is_favorite=$isFavorite');
    final headers = await _getAuthHeaders();
    await http.patch(url, headers: headers).timeout(_timeoutDuration);
  }

  Future<List<UserWord>> getFavoriteWords() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/favorites');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    // UserWord 객체 리스트로 변환하여 반환
    return data.map((item) => UserWord.fromJson(item)).toList();
  }

  Future<Map<String, dynamic>> getVocabularyStats() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/stats');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<List<dynamic>> getAllWords({String? status}) async {
    String queryString = status != null ? '?status=$status' : '';
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/words$queryString');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> getVocabularyAnalysis() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/analysis');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<Map<String, dynamic>?> getDailyFeedback() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/statistics/daily-feedback');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('피드백을 받으려면 로그인이 필요합니다.');
    }
    try {
      final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
      if (response.statusCode == 204) {
        return null;
      }
      return _processResponse(response);
    } on TimeoutException {
      throw ApiException('요청 시간이 초과되었습니다. 네트워크 연결을 확인해주세요.');
    } catch (e) {
      rethrow;
    }
  }

  // 문법 연습 이력 목록 조회
  Future<List<GrammarHistory>> getGrammarHistory({int limit = 20, int offset = 0}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/grammar/history?limit=$limit&offset=$offset');
    final headers = await _getAuthHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    return data.map((item) => GrammarHistory.fromJson(item)).toList();
  }

// 문법 연습 통계 조회
  Future<GrammarStatistics> getGrammarStatistics() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/grammar/statistics');
    final headers = await _getAuthHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final data = _processResponse(response);
    return GrammarStatistics.fromJson(data);
  }

  // 문법 연습 결과(이력) 저장
  Future<Map<String, dynamic>> addGrammarHistory({ // 👈 1. void를 Future<Map<String, dynamic>>으로 변경
    required String transcribedText,
    required String correctedText,
    required List<String> grammarFeedback,
    required List<String> vocabularySuggestions,
    required bool isCorrect,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/grammar/history/add');
    final headers = await _getAuthHeaders();

    final body = jsonEncode({
      'transcribed_text': transcribedText,
      'corrected_text': correctedText,
      'grammar_feedback': grammarFeedback,
      'vocabulary_suggestions': vocabularySuggestions,
      'is_correct': isCorrect,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response); // 👈 2. 이 줄을 추가하여 서버 응답을 반환
  }

  // 문법 즐겨찾기 상태 업데이트
  Future<void> updateGrammarFavoriteStatus({required int historyId, required bool isFavorite}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/grammar/history/$historyId/favorite?is_favorite=$isFavorite');
    final headers = await _getAuthHeaders();
    final response = await http.patch(url, headers: headers).timeout(_timeoutDuration);
    _processResponse(response);
  }

  // 즐겨찾기된 문법 이력 목록 조회
  Future<List<GrammarHistory>> getFavoriteGrammarHistory() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/grammar/favorites');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    return data.map((item) => GrammarHistory.fromJson(item)).toList();
  }

  // 비밀번호 변경
  Future<Map<String, dynamic>> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/user/update-password');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('비밀번호를 변경하려면 로그인이 필요합니다.');
    }

    final body = jsonEncode({
      'current_password': currentPassword,
      'new_password': newPassword,
    });

    final response = await http.patch(
      url,
      headers: headers,
      body: body,
    ).timeout(_timeoutDuration);

    return _processResponse(response); // ✅ Map 반환으로 변경
  }

  // 회원 탈퇴
  Future<void> deleteAccount({required String password}) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/user/delete-account');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('회원 탈퇴를 진행하려면 로그인이 필요합니다.');
    }

    final body = jsonEncode({'password': password});

    final response = await http.post( // DELETE 대신 POST를 사용하여 body 전송
      url,
      headers: headers,
      body: body,
    ).timeout(_timeoutDuration);

    _processResponse(response); // 성공 여부만 확인
  }

  // --- 학습 진척도 조회 API 호출 ---
  Future<LearningProgress> getLearningProgress() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/statistics/progress');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final responseBody = _processResponse(response);

    // JSON 응답을 LearningProgress 객체로 변환하여 반환
    return LearningProgress.fromJson(responseBody);
  }

  // [추가] 학습 목표(계획) 수정
  Future<Map<String, dynamic>> updateLearningPlan({
    required int planId, // 수정할 계획의 ID
    required int conversationDuration,
    required int grammarCount,
    required int pronunciationCount,
  }) async {
    // PUT 요청을 보낼 URL
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/plans/$planId');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    // 요청 본문(body)은 createLearningPlan과 동일한 형식을 사용
    final body = jsonEncode({
      'conversation_duration': conversationDuration,
      'grammar_count': grammarCount,
      'pronunciation_count': pronunciationCount,
    });

    // http.put 메소드를 사용하여 요청
    final response = await http.put(url, headers: headers, body: body).timeout(_timeoutDuration);

    // 응답 처리 후 반환
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> analyzeGrammarFromVoice({
    required String audioPath,
    required String language,
    required String level,
  }) async {
    // AI 서버에 새로 추가할 엔드포인트
    final url = Uri.parse('$_aiBaseUrl/api/grammar/analyze-voice');
    final userId = AppState.userId;
    if (userId == null) throw ApiException('User not logged in');

    // 파일을 읽어 Base64로 인코딩
    final file = File(audioPath);
    final audioBytes = await file.readAsBytes();
    final base64Audio = base64Encode(audioBytes);

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'user_id': userId,
        'audio_base64': base64Audio,
        'language': language, // 예: "en"
        'level': level,       // 예: "B1"
      }),
    ).timeout(const Duration(seconds: 60)); // AI 분석 시간이 길 수 있으므로 타임아웃을 넉넉하게 설정

    return _processResponse(response);
  }

  Future<Map<String, dynamic>> updateBeginnerMode({required bool isEnabled}) async {
    // 위 1-2 단계에서 새로 만든 API 엔드포인트 주소를 사용합니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/user/settings');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      throw ApiException('설정을 변경하려면 로그인이 필요합니다.');
    }

    final body = jsonEncode({'beginner_mode': isEnabled});

    // PATCH 메소드를 사용하여 일부 데이터만 업데이트합니다.
    final response = await http.patch(
      url,
      headers: headers,
      body: body,
    ).timeout(_timeoutDuration);

    return _processResponse(response);
  }

  Future<Map<String, dynamic>> getCorrectedPronunciation({
    required String sessionId,
    required String userId, // <--- user_id 파라미터 추가
  }) async {
    final url = Uri.parse('$_aiBaseUrl/api/pronunciation/personalized-correction');
    // 이제 이 API는 인증이 필요 없으므로 일반 헤더를 사용합니다.
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};

    final response = await http.post(
      url,
      headers: headers,
      // body에 session_id와 함께 user_id를 추가합니다.
      body: jsonEncode({
        'session_id': sessionId,
        'user_id': userId,
      }),
    ).timeout(const Duration(seconds: 45));

    return _processResponse(response);
  }

  Future<List<StudyGroupMessage>> getGroupMessages(int groupId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/messages');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);

    final List<dynamic> data = _processResponse(response);
    return data.map((item) => StudyGroupMessage.fromJson(item)).toList();
  }

  Future<StudyGroupMessage> postGroupMessage(int groupId, String content) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/messages');
    final headers = await _getAuthHeaders();
    final body = jsonEncode({'content': content});

    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    return StudyGroupMessage.fromJson(_processResponse(response));
  }

  Future<List<StudyGroupJoinRequest>> getJoinRequests(int groupId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/requests');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    return data.map((item) => StudyGroupJoinRequest.fromJson(item)).toList();
  }

  // 그룹 가입 요청 승인
  Future<String> approveJoinRequest(int groupId, int requestId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/requests/$requestId/approve');
    final headers = await _getAuthHeaders();
    final response = await http.post(url, headers: headers).timeout(_timeoutDuration);
    final responseBody = _processResponse(response);
    return responseBody['message'];
  }

  // 그룹 가입 요청 거절
  Future<String> rejectJoinRequest(int groupId, int requestId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/requests/$requestId/reject');
    final headers = await _getAuthHeaders();
    final response = await http.post(url, headers: headers).timeout(_timeoutDuration);
    final responseBody = _processResponse(response);
    return responseBody['message'];
  }

  Future<Map<String, dynamic>> exchangeCodeForToken(String authCode) async {
    if (_codeVerifier == null) {
      throw ApiException('Code verifier를 찾을 수 없습니다. 로그인 과정을 다시 시도해주세요.');
    }

    final url = Uri.parse('$_authPlanStatsBaseUrl/auth/exchange-code');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      // body에 저장해뒀던 _codeVerifier를 함께 보냅니다.
      body: jsonEncode({
        'auth_code': authCode,
        'code_verifier': _codeVerifier,
      }),
    ).timeout(_timeoutDuration);

    _codeVerifier = null; // 사용 후에는 비워줍니다.
    return _processResponse(response);
  }

  Future<List<UserWord>> searchAllWords(String query) async {
    // vocabulary_api.py에 정의된 /api/vocabulary/search 엔드포인트를 호출합니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/search?query=${Uri.encodeComponent(query)}');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);

    // API 응답(JSON 리스트)을 UserWord 객체 리스트로 변환하여 반환합니다.
    return data.map((item) => UserWord.fromJson(item)).toList();
  }

  Future<List<GroupChallenge>> getGroupChallenges(int groupId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/challenges');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    return data.map((item) => GroupChallenge.fromJson(item)).toList();
  }

  // 새 챌린지 생성
  Future<GroupChallenge> createGroupChallenge({
    required int groupId,
    required String title,
    required String description,
    required int durationDays,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/$groupId/challenges');
    final headers = await _getAuthHeaders();

    // ▼▼▼ 2. JSON body에 새 필드 추가 ▼▼▼
    final body = jsonEncode({
      'title': title,
      'description': description,
      'duration_days': durationDays,
    });
    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    // 반환 모델도 새로운 GroupChallenge.fromJson으로 변경 (이 부분은 이전 답변에서 누락되었을 수 있습니다)
    return GroupChallenge.fromJson(_processResponse(response));
  }

  // 챌린지 진행률 자동 기록
  Future<void> logChallengeProgress({
    required String logType, // 'pronunciation', 'grammar', 'conversation'
    required int value,      // 횟수(1) 또는 시간(분)
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/challenges/log-progress');
    final headers = await _getAuthHeaders();
    final body = jsonEncode({
      'log_type': logType,
      'value': value,
    });
    // 이 API는 성공 여부만 확인하므로, 실패 시에만 예외가 발생합니다.
    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    _processResponse(response);
  }

  Future<void> completeChallenge(int challengeId) async {
    // 백엔드에 새로 만든 POST /api/challenges/{challenge_id}/complete 엔드포인트를 호출합니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/challenges/$challengeId/complete');
    final headers = await _getAuthHeaders();
    final response = await http.post(url, headers: headers).timeout(_timeoutDuration);
    _processResponse(response); // 성공 여부만 확인
  }

  Future<GroupChallenge> updateGroupChallenge({
    required int challengeId,
    required String title,
    required String description,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/challenges/$challengeId');
    final headers = await _getAuthHeaders();
    final body = jsonEncode({
      'title': title,
      'description': description,
    });
    final response = await http.put(url, headers: headers, body: body).timeout(_timeoutDuration);
    return GroupChallenge.fromJson(_processResponse(response));
  }

  // 챌린지 삭제
  Future<void> deleteGroupChallenge(int challengeId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/challenges/$challengeId');
    final headers = await _getAuthHeaders();
    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);
    if (response.statusCode == 204) return;
    _processResponse(response);
  }

  // 포인트 교환소
  Future<Map<String, dynamic>> executePointTransaction({
    required int amount, // 적립은 양수, 사용은 음수
    required String reason,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/points/transaction');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    // AppState에서 현재 사용자 ID 가져오기
    final userId = AppState.userId;
    if (userId == null) throw ApiException('사용자 정보를 찾을 수 없습니다.');

    final body = jsonEncode({
      'user_id': userId,
      'amount': amount,
      'reason': reason,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> searchWordOnline(String query) async {
    // 새로 만든 백엔드 엔드포인트를 호출합니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/vocabulary/word-search-online?query=${Uri.encodeComponent(query)}');
    final headers = await _getAuthHeaders();

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    // _processResponse가 성공/실패를 모두 처리합니다.
    return _processResponse(response);
  }

  Future<List<PointTransaction>> getPointHistory() async {
    // 백엔드에 새로 만들 API 엔드포인트 주소입니다.
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/points/history');
    final token = await getToken();
    if (token == null) {
      throw ApiException('로그인이 필요합니다.');
    }

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        // UTF-8로 디코딩하여 한글 깨짐 방지
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        // 받아온 JSON 리스트를 PointTransaction 객체 리스트로 변환하여 반환
        return data.map((item) => PointTransaction.fromJson(item)).toList();
      } else {
        // 서버에서 에러 메시지를 보냈을 경우
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        throw ApiException(errorData['detail'] ?? '포인트 내역을 불러오는데 실패했습니다.');
      }
    } catch (e) {
      // 네트워크 오류 등
      throw ApiException('포인트 내역을 불러오는 중 오류가 발생했습니다.');
    }
  }

  Future<void> toggleGrammarQuestionFavorite({
    required String questionId,
    required bool isFavorite,
    String? question, // [추가]
    Map<String, String>? options, // [추가]
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/grammar/questions/$questionId/favorite');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final body = json.encode({
      'is_favorite': isFavorite,
      'question': question, // [추가]
      'options': options,   // [추가]
    });

    final response = await http.post(url, headers: headers, body: body).timeout(_timeoutDuration);
    _processResponse(response);
  }

  Future<List<TestQuestion>> getFavoriteGrammarQuestions() async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/grammar/questions/favorites');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    return data.map((item) => TestQuestion.fromJson(item)).toList();
  }

  Future<LearningProgress> getTodayLearningProgress() async {
    // 1단계에서 새로 만든 엔드포인트 주소
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/statistics/today-progress-detailed');
    final headers = await _getAuthHeaders();
    if (!headers.containsKey('Authorization')) throw ApiException('로그인이 필요합니다.');

    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final responseBody = _processResponse(response);

    // 기존 LearningProgress 모델을 그대로 재활용
    return LearningProgress.fromJson(responseBody);
  }

  Future<Map<String, dynamic>> submitChallengeProof({
    required int challengeId,
    String? content,
    XFile? imageFile,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/challenges/$challengeId/submit');
    final headers = await _getAuthHeaders();

    String? imageBase64;
    if (imageFile != null) {
      final imageBytes = await imageFile.readAsBytes();
      imageBase64 = base64Encode(imageBytes);
    }

    final body = jsonEncode({
      'proof_content': content,
      'proof_image_base64': imageBase64,
    });

    final response = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 60)); // 이미지 업로드를 위해 타임아웃 60초
    return _processResponse(response);
  }

  Future<ChallengeSubmission?> getMyChallengeSubmission(int challengeId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/challenges/$challengeId/my-submission');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);

    // 204 No Content는 데이터가 아예 없는 경우이므로 null 반환 (기존 로직 유지)
    if (response.statusCode == 204) {
      return null;
    }

    final data = _processResponse(response);

    // ✨ [핵심 수정]
    // 서버가 200 OK와 함께 null 본문을 보냈을 경우를 확인합니다.
    if (data == null) {
      return null;
    }

    // data가 null이 아닐 때만 fromJson을 실행합니다.
    return ChallengeSubmission.fromJson(data);
  }

  Future<ChallengeSubmission> updateChallengeSubmission({
    required int submissionId,
    String? content,
    XFile? imageFile,
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/submissions/$submissionId');
    final headers = await _getAuthHeaders();

    String? imageBase64;
    if (imageFile != null) {
      imageBase64 = base64Encode(await imageFile.readAsBytes());
    }

    final body = jsonEncode({
      'proof_content': content,
      'proof_image_base64': imageBase64,
    });

    final response = await http.put(url, headers: headers, body: body).timeout(const Duration(seconds: 60));
    final data = _processResponse(response);

    // ✨ [핵심 수정]
    // 서버가 submission 객체를 직접 반환하므로, data['submission'] 대신 data를 바로 사용합니다.
    return ChallengeSubmission.fromJson(data);
  }

  // ▼▼▼ [신규] 챌린지 인증 삭제 함수 ▼▼▼
  Future<void> deleteChallengeSubmission(int submissionId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/submissions/$submissionId');
    final headers = await _getAuthHeaders();
    final response = await http.delete(url, headers: headers).timeout(_timeoutDuration);

    if (response.statusCode == 204) {
      return; // 성공
    }
    _processResponse(response); // 실패 시 예외 발생
  }

  Future<List<ChallengeSubmission>> getChallengeSubmissions(int challengeId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/challenges/$challengeId/submissions');
    final headers = await _getAuthHeaders();
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    return data.map((item) => ChallengeSubmission.fromJson(item)).toList();
  }

  // ▼▼▼ [신규] 챌린지 인증 처리 (승인/거절) ▼▼▼
  Future<Map<String, dynamic>> processChallengeSubmission({
    required int submissionId,
    required String status, // "approved" 또는 "rejected"
  }) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/submissions/$submissionId/process?status=$status');
    final headers = await _getAuthHeaders();
    final response = await http.post(url, headers: headers).timeout(_timeoutDuration);
    return _processResponse(response);
  }

  Future<List<ChallengeParticipant>> getChallengeParticipants(int challengeId) async {
    final url = Uri.parse('$_authPlanStatsBaseUrl/api/study-groups/challenges/$challengeId/participants');
    // 이 API는 인증이 필요 없다고 가정 (필요 시 _getAuthHeaders() 사용)
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    final response = await http.get(url, headers: headers).timeout(_timeoutDuration);
    final List<dynamic> data = _processResponse(response);
    return data.map((item) => ChallengeParticipant.fromJson(item)).toList();
  }
}