import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

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

class DeviceProvisioningService {
  static const String _baseUrl = 'https://operon-api.sundaybonbon.com';
  static const String _provisionPath = '/api/v1/device-auth/provision';
  static final RegExp _serialNumberPattern = RegExp(r'^\d{6,8}$');

  static Future<DeviceProvisioningCredentials> provision({
    required String serialNumber,
    required String appVersion,
  }) async {
    final normalizedSerialNumber = serialNumber.trim();
    if (!_serialNumberPattern.hasMatch(normalizedSerialNumber)) {
      throw RequestException(
        400,
        'serialNumber(등록 코드)는 6~8자리 숫자여야 합니다',
      );
    }

    final response = await http.post(
      Uri.parse('$_baseUrl$_provisionPath'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'serialNumber': normalizedSerialNumber,
        'appVersion': appVersion,
      }),
    );

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(decode_http_response(response)) as Map<String, dynamic>;
    } catch (_) {
      throw RequestException(
        response.statusCode,
        '프로비저닝 응답을 해석할 수 없습니다',
      );
    }

    if (response.statusCode != 200 || body['success'] != true) {
      final message = (body['message'] ?? body['error'] ?? '프로비저닝에 실패했습니다')
          .toString();
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
      throw RequestException(500, '프로비저닝 응답에 필요한 값이 없습니다');
    }

    await saveCredentials(credentials);
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
}