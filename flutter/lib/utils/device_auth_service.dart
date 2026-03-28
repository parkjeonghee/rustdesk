import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:uuid/uuid.dart';

typedef DeviceAuthLogCallback = void Function(String message);

class DeviceProvisioningCredentials {
  const DeviceProvisioningCredentials({
    required this.serialNumber,
    required this.clientId,
    required this.clientSecret,
    required this.provisionedAt,
  });

  final String serialNumber;
  final String clientId;
  final String clientSecret;
  final String provisionedAt;

  bool get isComplete => clientId.isNotEmpty && clientSecret.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'serialNumber': serialNumber,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'provisionedAt': provisionedAt,
    };
  }
}

class DevicePeerIdentity {
  const DevicePeerIdentity({
    required this.id,
    required this.uuid,
    required this.pk,
  });

  final String id;
  final String uuid;
  final String pk;

  bool get isComplete => id.isNotEmpty && uuid.isNotEmpty && pk.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'pk': pk,
    };
  }
}

class DeviceAccessRustDeskConfig {
  const DeviceAccessRustDeskConfig({
    required this.id,
    required this.idServer,
    required this.relayServer,
    required this.key,
  });

  final String id;
  final String idServer;
  final String relayServer;
  final String key;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'idServer': idServer,
      'relayServer': relayServer,
      'key': key,
    };
  }

  factory DeviceAccessRustDeskConfig.fromJson(Map<String, dynamic> json) {
    return DeviceAccessRustDeskConfig(
      id: (json['id'] ?? '').toString(),
      idServer: (json['idServer'] ?? '').toString(),
      relayServer: (json['relayServer'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
    );
  }
}

class DeviceAccessTokenInfo {
  const DeviceAccessTokenInfo({
    required this.accessToken,
    required this.tokenType,
    required this.roles,
    required this.expiresInSeconds,
    required this.expiresAt,
    required this.deviceId,
    required this.storeId,
    required this.storeName,
    required this.rustdesk,
    required this.timestamp,
  });

  final String accessToken;
  final String tokenType;
  final List<String> roles;
  final int expiresInSeconds;
  final String? expiresAt;
  final String deviceId;
  final String storeId;
  final String storeName;
  final DeviceAccessRustDeskConfig rustdesk;
  final String timestamp;

  bool get isComplete => accessToken.isNotEmpty && tokenType.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'tokenType': tokenType,
      'roles': roles,
      'expiresInSeconds': expiresInSeconds,
      'expiresAt': expiresAt,
      'deviceId': deviceId,
      'storeId': storeId,
      'storeName': storeName,
      'rustdesk': rustdesk.toJson(),
      'timestamp': timestamp,
    };
  }

  factory DeviceAccessTokenInfo.fromJson(Map<String, dynamic> json) {
    return DeviceAccessTokenInfo(
      accessToken: (json['accessToken'] ?? '').toString(),
      tokenType: (json['tokenType'] ?? '').toString(),
      roles: ((json['roles'] as List<dynamic>? ?? const <dynamic>[]))
          .map((role) => role.toString())
          .toList(),
      expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 0,
      expiresAt: json['expiresAt']?.toString(),
      deviceId: (json['deviceId'] ?? '').toString(),
      storeId: (json['storeId'] ?? '').toString(),
      storeName: (json['storeName'] ?? '').toString(),
      rustdesk: DeviceAccessRustDeskConfig.fromJson(
          json['rustdesk'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      timestamp: (json['timestamp'] ?? '').toString(),
    );
  }
}

class DeviceProvisioningService {
  static const String _baseUrl = 'https://operon-api.sundaybonbon.com';
  static const String _provisionPath = '/api/v1/device-auth/provision';
  static const String _tokenPath = '/api/v1/device-auth/token';
  static final RegExp _serialNumberPattern = RegExp(r'^\d{6,8}$');
  static final RegExp _uuidHexPattern = RegExp(r'^[0-9a-f]{32}$');
  static final Uuid _uuidGenerator = const Uuid();

  static Future<DeviceProvisioningCredentials> provision({
    required String serialNumber,
    required String appVersion,
    DeviceAuthLogCallback? onLog,
  }) async {
    final normalizedSerialNumber = serialNumber.trim();
    _log(onLog, '프로비저닝 시작');
    _log(onLog, '입력 serialNumber=$normalizedSerialNumber, appVersion=$appVersion');
    if (!_serialNumberPattern.hasMatch(normalizedSerialNumber)) {
      _log(onLog, '입력 검증 실패: serialNumber 형식이 올바르지 않음');
      throw RequestException(
        400,
        'serialNumber(등록 코드)는 6~8자리 숫자여야 합니다',
      );
    }

    _log(onLog, 'POST $_baseUrl$_provisionPath 요청 준비');

    final response = await http.post(
      Uri.parse('$_baseUrl$_provisionPath'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'serialNumber': normalizedSerialNumber,
        'appVersion': appVersion,
      }),
    );
    final responseBody = decode_http_response(response);
    _log(onLog, '프로비저닝 응답 수신: HTTP ${response.statusCode}');
    _log(onLog, '프로비저닝 응답 본문: $responseBody');

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      _log(onLog, '응답 JSON 파싱 실패');
      throw RequestException(
        response.statusCode,
        '프로비저닝 응답을 해석할 수 없습니다',
      );
    }

    if (response.statusCode != 200 || body['success'] != true) {
      final message = (body['message'] ?? body['error'] ?? '프로비저닝에 실패했습니다')
          .toString();
      _log(onLog, '프로비저닝 실패: $message');
      throw RequestException(response.statusCode, message);
    }

    final data = (body['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final credentials = DeviceProvisioningCredentials(
      serialNumber: normalizedSerialNumber,
      clientId: (data['clientId'] ?? '').toString(),
      clientSecret: (data['clientSecret'] ?? '').toString(),
      provisionedAt: (data['provisionedAt'] ?? '').toString(),
    );

    if (!credentials.isComplete) {
      _log(onLog, '프로비저닝 실패: 응답 필수값 누락');
      throw RequestException(500, '프로비저닝 응답에 필요한 값이 없습니다');
    }

    await saveCredentials(credentials);
    _log(onLog, '프로비저닝 성공: clientId=${credentials.clientId} 저장 완료');
    return credentials;
  }

  static DeviceProvisioningCredentials? getStoredCredentials() {
    final clientId = bind.mainGetLocalOption(key: kOptionDeviceProvisionClientId);
    final clientSecret =
        bind.mainGetLocalOption(key: kOptionDeviceProvisionClientSecret);
    if (clientId.isEmpty || clientSecret.isEmpty) {
      return null;
    }

    return DeviceProvisioningCredentials(
      serialNumber:
          bind.mainGetLocalOption(key: kOptionDeviceProvisionSerialNumber),
      clientId: clientId,
      clientSecret: clientSecret,
      provisionedAt: bind.mainGetLocalOption(key: kOptionDeviceProvisionedAt),
    );
  }

  static Future<void> saveCredentials(
    DeviceProvisioningCredentials credentials,
  ) async {
    await Future.wait([
      bind.mainSetLocalOption(
        key: kOptionDeviceProvisionSerialNumber,
        value: credentials.serialNumber,
      ),
      bind.mainSetLocalOption(
        key: kOptionDeviceProvisionClientId,
        value: credentials.clientId,
      ),
      bind.mainSetLocalOption(
        key: kOptionDeviceProvisionClientSecret,
        value: credentials.clientSecret,
      ),
      bind.mainSetLocalOption(
        key: kOptionDeviceProvisionedAt,
        value: credentials.provisionedAt,
      ),
    ]);
  }

  static Future<void> clearStoredCredentials() async {
    await Future.wait([
      bind.mainSetLocalOption(key: kOptionDeviceProvisionSerialNumber, value: ''),
      bind.mainSetLocalOption(key: kOptionDeviceProvisionClientId, value: ''),
      bind.mainSetLocalOption(
          key: kOptionDeviceProvisionClientSecret, value: ''),
      bind.mainSetLocalOption(key: kOptionDeviceProvisionedAt, value: ''),
    ]);
    await clearStoredAccessTokenInfo();
  }

  static Map<String, String>? getStoredTokenRequestBody() {
    final credentials = getStoredCredentials();
    if (credentials == null) {
      return null;
    }
    return {
      'clientId': credentials.clientId,
      'clientSecret': credentials.clientSecret,
    };
  }

  static Future<DevicePeerIdentity> getCurrentPeerIdentity({
    DeviceAuthLogCallback? onLog,
    bool requireComplete = true,
  }) async {
    _log(onLog, '현재 RustDesk peer 정보 조회 시작');
    final id = await _readPeerId(onLog: onLog);
    final pk = await _readPeerPublicKey(onLog: onLog);
    final uuid = await _readPeerUuid(pk: pk, onLog: onLog);
    final identity = DevicePeerIdentity(id: id, uuid: uuid, pk: pk);
    _log(onLog, 'peer id=$id');
    _log(onLog, 'peer uuid=$uuid');
    _log(onLog, 'peer uuid length=${uuid.length}');
    _log(onLog, 'peer uuid is valid 32-hex? ${_isValidClientUuid(uuid)}');
    _log(onLog, 'peer pk=$pk');
    _log(onLog, 'peer pk length=${pk.length}');
    _log(onLog, 'peer pk is hex? ${_isValidPublicKeyHex(pk)}');
    _log(onLog, 'peer uuid == pk ? ${uuid == pk}');
    if (requireComplete && !identity.isComplete) {
      _log(onLog, 'peer 정보 조회 실패: id/uuid/pk 중 일부가 비어 있음');
      throw RequestException(400, '현재 디바이스의 RustDesk peer 정보를 읽을 수 없습니다');
    }
    if (requireComplete && !_isValidClientUuid(identity.uuid)) {
      _log(onLog, 'peer 정보 조회 실패: uuid가 32자리 hex 규칙을 만족하지 않음');
      throw RequestException(400, 'uuid는 32자리 hex 문자열이어야 합니다');
    }
    if (requireComplete && !_isValidPublicKeyHex(identity.pk)) {
      _log(onLog, 'peer 정보 조회 실패: pk가 hex 문자열 규칙을 만족하지 않음');
      throw RequestException(400, 'pk는 hex 문자열이어야 합니다');
    }
    if (identity.isComplete) {
      _log(onLog, '현재 RustDesk peer 정보 조회 성공');
    }
    return identity;
  }

  static Future<String> _readPeerId({
    DeviceAuthLogCallback? onLog,
  }) async {
    try {
      return (await bind.mainGetMyId()).trim();
    } catch (error) {
      _log(onLog, 'peer id 조회 실패: $error');
      return '';
    }
  }

  static Future<String> _readPeerUuid({
    required String pk,
    DeviceAuthLogCallback? onLog,
  }) async {
    try {
      final storedUuid =
          bind.mainGetLocalOption(key: kOptionDeviceClientUuid).trim();
      if (_isUsableClientUuid(storedUuid, pk)) {
        _log(onLog, '저장된 client uuid 사용');
        return storedUuid.toLowerCase();
      }

      final nativeUuid = _decodeUuidToHex((await bind.mainGetUuid()).trim());
      if (_isUsableClientUuid(nativeUuid, pk)) {
        await bind.mainSetLocalOption(
          key: kOptionDeviceClientUuid,
          value: nativeUuid.toLowerCase(),
        );
        _log(onLog, 'RustDesk uuid를 client uuid로 저장');
        return nativeUuid.toLowerCase();
      }

      final generatedUuid = _uuidGenerator.v4().replaceAll('-', '').toLowerCase();
      await bind.mainSetLocalOption(
        key: kOptionDeviceClientUuid,
        value: generatedUuid,
      );
      _log(onLog, '별도 client uuid 생성 및 저장');
      return generatedUuid;
    } catch (error) {
      _log(onLog, 'peer uuid 조회 실패: $error');
      return '';
    }
  }

  static Future<String> _readPeerPublicKey({
    DeviceAuthLogCallback? onLog,
  }) async {
    try {
      return _normalizeToHex((await bind.mainGetPublicKey()).trim());
    } catch (error) {
      _log(onLog, 'peer pk 조회 실패: $error');
      return '';
    }
  }

  static Future<DeviceAccessTokenInfo> issueAccessToken({
    DeviceAuthLogCallback? onLog,
  }) async {
    _log(onLog, '디바이스 액세스 토큰 발급 시작');
    final credentials = getStoredCredentials();
    if (credentials == null) {
      _log(onLog, '토큰 발급 중단: 저장된 clientId/clientSecret 없음');
      throw RequestException(400, '먼저 디바이스 프로비저닝을 완료해야 합니다');
    }

    _log(onLog, '저장된 clientId=${credentials.clientId} 확인');
    final identity = await getCurrentPeerIdentity(
      onLog: onLog,
      requireComplete: false,
    );
    _log(onLog, 'POST $_baseUrl$_tokenPath 요청 준비');
    final requestHeaders = const {'Content-Type': 'application/json'};
    final requestBody = {
      'clientId': credentials.clientId,
      'clientSecret': credentials.clientSecret,
      'id': identity.id,
      'uuid': identity.uuid,
      'pk': identity.pk,
    };
    _log(onLog, '토큰 요청 헤더: ${jsonEncode(requestHeaders)}');
    _log(onLog, '토큰 요청 바디: ${jsonEncode(requestBody)}');
    if (!identity.isComplete) {
      _log(onLog, '토큰 요청 중단: peer 정보(id/uuid/pk) 불완전');
      throw RequestException(400, '현재 디바이스의 RustDesk peer 정보를 읽을 수 없습니다');
    }
    final response = await http.post(
      Uri.parse('$_baseUrl$_tokenPath'),
      headers: requestHeaders,
      body: jsonEncode(requestBody),
    );
    final responseBody = decode_http_response(response);
    _log(onLog, '토큰 응답 수신: HTTP ${response.statusCode}');
    _log(onLog, '토큰 응답 본문: $responseBody');

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      _log(onLog, '토큰 응답 JSON 파싱 실패');
      throw RequestException(
        response.statusCode,
        '토큰 응답을 해석할 수 없습니다',
      );
    }

    if (response.statusCode != 200 || body['success'] != true) {
      final message =
          (body['message'] ?? body['error'] ?? '디바이스 액세스 토큰 발급에 실패했습니다')
              .toString();
      _log(onLog, '토큰 발급 실패: $message');
      throw RequestException(response.statusCode, message);
    }

    final data = (body['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final tokenInfo = DeviceAccessTokenInfo(
      accessToken: (data['accessToken'] ?? '').toString(),
      tokenType: (data['tokenType'] ?? '').toString(),
      roles: ((data['roles'] as List<dynamic>? ?? const <dynamic>[]))
          .map((role) => role.toString())
          .toList(),
      expiresInSeconds: (data['expiresInSeconds'] as num?)?.toInt() ?? 0,
      expiresAt: data['expiresAt']?.toString(),
      deviceId: (data['deviceId'] ?? '').toString(),
      storeId: (data['storeId'] ?? '').toString(),
      storeName: (data['storeName'] ?? '').toString(),
      rustdesk: DeviceAccessRustDeskConfig.fromJson(
          data['rustdesk'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      timestamp: (body['timestamp'] ?? '').toString(),
    );

    if (!tokenInfo.isComplete) {
      _log(onLog, '토큰 발급 실패: 응답 필수값 누락');
      throw RequestException(500, '토큰 응답에 필요한 값이 없습니다');
    }

    await saveAccessTokenInfo(tokenInfo);
    _log(onLog, '액세스 토큰 저장 완료');
    final shouldAutoRestartService = await _applyRustDeskConfig(
      tokenInfo.rustdesk,
      onLog: onLog,
    );
    await _tryAutoStartService(onLog: onLog);
    if (shouldAutoRestartService) {
      _log(onLog, '변경된 ID로 서비스 재시작 완료');
    }
    _log(onLog, '토큰 발급 및 디바이스 등록 성공');
    return tokenInfo;
  }

  static Future<bool> _applyRustDeskConfig(
    DeviceAccessRustDeskConfig config, {
    DeviceAuthLogCallback? onLog,
  }) async {
    _log(onLog, 'RustDesk 설정 자동 반영 시작');
    await setServerConfig(
      null,
      null,
      ServerConfig(
        idServer: config.idServer,
        relayServer: config.relayServer,
        apiServer: _baseUrl,
        key: config.key,
      ),
    );
    _log(
      onLog,
      'RustDesk 서버 설정 반영 완료: idServer=${config.idServer}, relayServer=${config.relayServer}',
    );

    final targetId = config.id.trim();
    if (targetId.isEmpty) {
      _log(onLog, 'RustDesk ID 자동 설정 생략: 응답에 id 값이 없음');
      return false;
    }

    final currentId = await _readPeerId(onLog: onLog);
    if (currentId == targetId) {
      _log(onLog, 'RustDesk ID 자동 설정 생략: 이미 동일한 ID 사용 중');
      return false;
    }

    final wasServiceRunning = isAndroid && gFFI.serverModel.isStart;
    if (wasServiceRunning) {
      _log(onLog, 'ID 변경 적용을 위해 실행 중인 서비스를 중지');
      await gFFI.serverModel.stopService();
      _log(onLog, '서비스 중지 완료');
    }

    _log(onLog, 'RustDesk ID 변경 요청: $currentId -> $targetId');
    await bind.mainChangeId(newId: targetId);
    final updatedId = await _waitForPeerId(targetId, onLog: onLog);
    if (updatedId != targetId) {
      _log(onLog, 'RustDesk ID 변경 확인 실패: 현재 id=$updatedId');
      throw RequestException(500, '변경된 RustDesk ID가 아직 반영되지 않았습니다');
    }
    _log(onLog, 'RustDesk ID 자동 설정 요청 완료');
    return wasServiceRunning;
  }

  static Future<void> _tryAutoStartService({
    DeviceAuthLogCallback? onLog,
  }) async {
    if (!isAndroid) {
      _log(onLog, '서비스 자동 시작 생략: Android 환경이 아님');
      return;
    }

    if (gFFI.serverModel.isStart) {
      _log(onLog, '서비스 자동 시작 생략: 이미 서비스가 실행 중');
      return;
    }

    _log(onLog, '서비스 자동 시작 준비');

    try {
      await gFFI.serverModel.checkRequestNotificationPermission();
      if (bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) != 'Y') {
        await gFFI.serverModel.checkFloatingWindowPermission();
      }
      if (!await AndroidPermissionManager.check(kManageExternalStorage)) {
        await AndroidPermissionManager.request(kManageExternalStorage);
      }

      await gFFI.serverModel.startService();
      _log(onLog, '서비스 자동 시작 요청 완료');
    } catch (error) {
      _log(onLog, '서비스 자동 시작 실패: $error');
    }
  }

  static Future<String> _waitForPeerId(
    String targetId, {
    DeviceAuthLogCallback? onLog,
  }) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final currentId = await _readPeerId(onLog: onLog);
      if (currentId == targetId) {
        _log(onLog, '변경된 RustDesk ID 반영 확인 완료');
        return currentId;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return await _readPeerId(onLog: onLog);
  }

  static DeviceAccessTokenInfo? getStoredAccessTokenInfo() {
    final rawPayload =
        bind.mainGetLocalOption(key: kOptionDeviceAccessTokenPayload).trim();
    if (rawPayload.isEmpty) {
      return null;
    }
    try {
      return DeviceAccessTokenInfo.fromJson(
          jsonDecode(rawPayload) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAccessTokenInfo(DeviceAccessTokenInfo tokenInfo) async {
    await Future.wait([
      bind.mainSetLocalOption(
        key: kOptionDeviceAccessToken,
        value: tokenInfo.accessToken,
      ),
      bind.mainSetLocalOption(
        key: kOptionDeviceAccessTokenPayload,
        value: jsonEncode(tokenInfo.toJson()),
      ),
    ]);
  }

  static Future<void> clearStoredAccessTokenInfo() async {
    await Future.wait([
      bind.mainSetLocalOption(key: kOptionDeviceAccessToken, value: ''),
      bind.mainSetLocalOption(key: kOptionDeviceAccessTokenPayload, value: ''),
    ]);
  }

  static Map<String, String>? getStoredDeviceAuthorizationHeaders() {
    final token = bind.mainGetLocalOption(key: kOptionDeviceAccessToken).trim();
    if (token.isEmpty) {
      return null;
    }
    return {
      'Authorization': 'Bearer $token',
    };
  }

  static String _decodeUuidToHex(String value) {
    if (value.isEmpty) {
      return '';
    }
    final normalized = value.trim();
    final isHex = RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(normalized);
    if (isHex) {
      return normalized.toLowerCase();
    }
    try {
      final bytes = base64Decode(base64.normalize(normalized));
      return _bytesToHex(bytes);
    } catch (_) {
      return normalized;
    }
  }

  static String _normalizeToHex(String value) {
    if (value.isEmpty) {
      return '';
    }
    final normalized = value.trim();
    if (_isHex(normalized)) {
      return normalized.toLowerCase();
    }
    try {
      final bytes = base64Decode(base64.normalize(normalized));
      return _bytesToHex(bytes);
    } catch (_) {
      return normalized;
    }
  }

  static bool _isHex(String value) {
    return value.isNotEmpty && RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  static bool _isValidClientUuid(String value) {
    return _uuidHexPattern.hasMatch(value);
  }

  static bool _isValidPublicKeyHex(String value) {
    return value.isNotEmpty && value.length.isEven && _isHex(value);
  }

  static bool _isUsableClientUuid(String value, String pk) {
    final normalizedValue = value.trim().toLowerCase();
    final normalizedPk = pk.trim().toLowerCase();
    return _isValidClientUuid(normalizedValue) && normalizedValue != normalizedPk;
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static void _log(DeviceAuthLogCallback? onLog, String message) {
    onLog?.call(message);
  }
}