import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/device_auth_service.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

class DeviceResourceSnapshotResult {
  const DeviceResourceSnapshotResult({
    required this.id,
    required this.message,
    required this.observedAt,
    required this.receivedAt,
  });

  final int id;
  final String message;
  final String observedAt;
  final String receivedAt;
}

class DeviceResourceSnapshotService {
  static const String _baseUrl = 'https://operon-api.sundaybonbon.com';

  static Future<DeviceResourceSnapshotResult> uploadSnapshot() async {
    final tokenInfo = DeviceProvisioningService.getStoredAccessTokenInfo();
    if (tokenInfo == null || tokenInfo.accessToken.trim().isEmpty) {
      throw RequestException(400, '먼저 디바이스 액세스 토큰을 발급해야 합니다');
    }

    final deviceId = tokenInfo.deviceId.trim();
    if (deviceId.isEmpty) {
      throw RequestException(400, '저장된 디바이스 ID가 없습니다');
    }

    final snapshot = await _getNativeSnapshot();
    final appVersion = version.isNotEmpty ? version : await bind.mainGetVersion();
    final requestBody = _buildRequestBody(snapshot, appVersion: appVersion);

    final response = await http.post(
      Uri.parse('$_baseUrl/api/v1/devices/$deviceId/resource-snapshots'),
      headers: {
        'Authorization': 'Bearer ${tokenInfo.accessToken.trim()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    final responseBody = decode_http_response(response);
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      throw RequestException(response.statusCode, '리소스 스냅샷 응답을 해석할 수 없습니다');
    }

    if (response.statusCode != 200 || body['success'] != true) {
      final message =
          (body['message'] ?? body['error'] ?? '리소스 스냅샷 저장에 실패했습니다')
              .toString();
      throw RequestException(response.statusCode, message);
    }

    final data = body['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return DeviceResourceSnapshotResult(
      id: (data['id'] as num?)?.toInt() ?? 0,
      message: (body['message'] ?? '디바이스 리소스 정보가 저장되었습니다').toString(),
      observedAt: (data['observedAt'] ?? '').toString(),
      receivedAt: (data['receivedAt'] ?? '').toString(),
    );
  }

  static Future<Map<String, dynamic>> _getNativeSnapshot() async {
    if (!isAndroid) {
      throw RequestException(400, '안드로이드에서만 디바이스 리소스 스냅샷을 수집할 수 있습니다');
    }

    final rawSnapshot =
        await platformFFI.invokeMethod(AndroidChannel.kGetDeviceResourceSnapshot);
    if (rawSnapshot is! Map) {
      throw RequestException(500, '안드로이드 리소스 스냅샷을 읽을 수 없습니다');
    }
    return Map<String, dynamic>.from(rawSnapshot);
  }

  static Map<String, dynamic> _buildRequestBody(
    Map<String, dynamic> snapshot, {
    required String appVersion,
  }) {
    final extras = (snapshot['extras'] ?? '').toString().trim();
    return {
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'cpuUsagePercent': _asDouble(snapshot['cpuUsagePercent']),
      'memoryTotalMb': _asInt(snapshot['memoryTotalMb']),
      'memoryAvailableMb': _asInt(snapshot['memoryAvailableMb']),
      'storageTotalMb': _asInt(snapshot['storageTotalMb']),
      'storageAvailableMb': _asInt(snapshot['storageAvailableMb']),
      'batteryLevelPercent': _clampInt(_asInt(snapshot['batteryLevelPercent']), 0, 100),
      'batteryCharging': _asBool(snapshot['batteryCharging']),
      'batteryTemperatureCelsius': _asDouble(snapshot['batteryTemperatureCelsius']),
      'networkType': _trimToLength(snapshot['networkType']?.toString(), 20),
      'networkConnected': _asBool(snapshot['networkConnected']),
      'networkSignalLevel': _clampInt(_asInt(snapshot['networkSignalLevel']), 0, 4),
      'appVersion': _trimToLength(appVersion, 50),
      'uptimeSeconds': _asInt(snapshot['uptimeSeconds']),
      'extras': extras.isEmpty ? '{}' : extras,
    };
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value >= 0 ? value : 0;
    }
    if (value is num) {
      final converted = value.toInt();
      return converted >= 0 ? converted : 0;
    }
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    return null;
  }

  static int? _clampInt(int? value, int min, int max) {
    if (value == null) {
      return null;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  static String? _trimToLength(String? value, int maxLength) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.length <= maxLength ? trimmed : trimmed.substring(0, maxLength);
  }
}