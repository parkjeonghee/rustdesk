import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/device_auth_service.dart';

import 'page_shape.dart';

class DeviceProvisionPage extends StatefulWidget implements PageShape {
  const DeviceProvisionPage({super.key});

  @override
  final title = 'Device Provisioning';

  @override
  final icon = const Icon(Icons.key_outlined);

  @override
  final appBarActions = const <Widget>[];

  @override
  State<DeviceProvisionPage> createState() => _DeviceProvisionPageState();
}

class _DeviceProvisionPageState extends State<DeviceProvisionPage> {
  final TextEditingController _serialNumberController = TextEditingController();
  final RegExp _serialPattern = RegExp(r'^\d{6,8}$');

  DeviceProvisioningCredentials? _credentials;
  DevicePeerIdentity? _peerIdentity;
  DeviceAccessTokenInfo? _tokenInfo;
  String _appVersion = '';
  bool _isSubmitting = false;
  bool _isIssuingToken = false;
  final List<String> _logs = <String>[];
  String? _lastErrorMessage;

  @override
  void initState() {
    super.initState();
    _credentials = DeviceProvisioningService.getStoredCredentials();
    _tokenInfo = DeviceProvisioningService.getStoredAccessTokenInfo();
    if (_credentials != null) {
      _serialNumberController.text = _credentials!.serialNumber;
    }
    _loadAppVersion();
    _loadPeerIdentity();
  }

  @override
  void dispose() {
    _serialNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    final currentVersion = version.isNotEmpty ? version : await bind.mainGetVersion();
    if (!mounted) return;
    setState(() {
      _appVersion = currentVersion;
    });
  }

  Future<void> _loadPeerIdentity() async {
    try {
      final peerIdentity = await DeviceProvisioningService.getCurrentPeerIdentity(
        onLog: _appendLog,
      );
      if (!mounted) return;
      setState(() {
        _peerIdentity = peerIdentity;
      });
    } catch (error) {
      _appendLog('peer 정보 초기 조회 실패: $error');
      if (!mounted) return;
      setState(() {
        _peerIdentity = null;
      });
    }
  }

  bool get _isSerialNumberValid {
    return _serialPattern.hasMatch(_serialNumberController.text.trim());
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    _startOperationLog('프로비저닝 요청');

    final serialNumber = _serialNumberController.text.trim();
    if (!_serialPattern.hasMatch(serialNumber)) {
      _setError('등록 코드는 6~8자리 숫자여야 합니다');
      showToast('등록 코드는 6~8자리 숫자여야 합니다');
      return;
    }

    if (_appVersion.trim().isEmpty) {
      _setError('앱 버전을 확인할 수 없습니다');
      showToast('앱 버전을 확인할 수 없습니다');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final credentials = await DeviceProvisioningService.provision(
        serialNumber: serialNumber,
        appVersion: _appVersion,
        onLog: _appendLog,
      );
      if (!mounted) return;
      setState(() {
        _credentials = credentials;
        _lastErrorMessage = null;
      });
      _appendLog('프로비저닝 완료');
      showToast('디바이스 프로비저닝이 완료되었습니다');
    } on RequestException catch (error) {
      _setError(_formatError(error));
      _appendLog('프로비저닝 예외: ${_formatError(error)}');
      showToast(error.cause);
    } catch (error) {
      _setError('프로비저닝에 실패했습니다: $error');
      _appendLog('프로비저닝 알 수 없는 예외: $error');
      showToast('프로비저닝에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _clearCredentials() async {
    await DeviceProvisioningService.clearStoredCredentials();
    if (!mounted) return;
    setState(() {
      _credentials = null;
      _tokenInfo = null;
    });
    showToast('저장된 프로비저닝 정보를 삭제했습니다');
  }

  Future<void> _clearTokenInfo() async {
    await DeviceProvisioningService.clearStoredAccessTokenInfo();
    if (!mounted) return;
    setState(() {
      _tokenInfo = null;
    });
    showToast('저장된 디바이스 토큰 정보를 삭제했습니다');
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    showToast('Copied');
  }

  Future<void> _issueToken() async {
    if (_isIssuingToken) return;
    _startOperationLog('토큰 발급 및 디바이스 등록');
    setState(() {
      _isIssuingToken = true;
    });

    try {
      final tokenInfo = await DeviceProvisioningService.issueAccessToken(
        onLog: _appendLog,
      );
      if (!mounted) return;
      setState(() {
        _tokenInfo = tokenInfo;
        _lastErrorMessage = null;
      });
      _appendLog('토큰 발급 및 디바이스 등록 완료');
      showToast('디바이스 액세스 토큰이 발급되었습니다');
    } on RequestException catch (error) {
      _setError(_formatError(error));
      _appendLog('토큰 발급 예외: ${_formatError(error)}');
      showToast(error.cause);
    } catch (error) {
      _setError('디바이스 액세스 토큰 발급에 실패했습니다: $error');
      _appendLog('토큰 발급 알 수 없는 예외: $error');
      showToast('디바이스 액세스 토큰 발급에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() {
          _isIssuingToken = false;
        });
      }
    }
  }

  void _startOperationLog(String title) {
    final separator = '===== $title ${DateTime.now().toIso8601String()} =====';
    setState(() {
      _logs.insert(0, separator);
      _lastErrorMessage = null;
    });
  }

  void _appendLog(String message) {
    if (!mounted) return;
    final line = '[${DateTime.now().toIso8601String()}] $message';
    setState(() {
      _logs.insert(0, line);
    });
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _lastErrorMessage = message;
    });
  }

  String _formatError(RequestException error) {
    if (error.statusCode > 0) {
      return 'HTTP ${error.statusCode}: ${error.cause}';
    }
    return error.cause;
  }

  @override
  Widget build(BuildContext context) {
    final tokenRequestBody = DeviceProvisioningService.getStoredTokenRequestBody();
    final authorizationHeaders =
        DeviceProvisioningService.getStoredDeviceAuthorizationHeaders();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '등록 코드로 clientId / clientSecret 발급',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'serialNumber에는 현재 구현 기준 등록 코드를 입력합니다. appVersion은 현재 앱 버전($_appVersion)으로 자동 전송됩니다.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _serialNumberController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: InputDecoration(
                    labelText: 'serialNumber',
                    hintText: '6~8자리 등록 코드',
                    helperText: '예: 123456',
                    errorText: _serialNumberController.text.isEmpty ||
                            _isSerialNumberValid
                        ? null
                        : '6~8자리 숫자만 입력할 수 있습니다',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('프로비저닝 요청'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_lastErrorMessage != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '마지막 실패 원인',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_lastErrorMessage!),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '디바이스 액세스 토큰 발급 및 등록',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '프로비저닝된 clientId / clientSecret 과 현재 RustDesk 디바이스 정보(id / uuid / pk)로 토큰을 발급하고 디바이스를 등록합니다.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (_peerIdentity == null)
                  const Text('현재 RustDesk peer 정보를 불러오는 중이거나 읽을 수 없습니다.')
                else ...[
                  _SecretFieldRow(
                    label: 'id',
                    value: _peerIdentity!.id,
                    onCopy: () => _copy(_peerIdentity!.id),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'uuid',
                    value: _peerIdentity!.uuid,
                    onCopy: () => _copy(_peerIdentity!.uuid),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'pk',
                    value: _peerIdentity!.pk,
                    onCopy: () => _copy(_peerIdentity!.pk),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: tokenRequestBody == null || _peerIdentity == null || _isIssuingToken
                        ? null
                        : _issueToken,
                    child: _isIssuingToken
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('토큰 발급 및 디바이스 등록'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_credentials != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '저장된 프로비저닝 정보',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      TextButton(
                        onPressed: _clearCredentials,
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SecretFieldRow(
                    label: 'serialNumber',
                    value: _credentials!.serialNumber,
                    onCopy: () => _copy(_credentials!.serialNumber),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'clientId',
                    value: _credentials!.clientId,
                    onCopy: () => _copy(_credentials!.clientId),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'clientSecret',
                    value: _credentials!.clientSecret,
                    onCopy: () => _copy(_credentials!.clientSecret),
                  ),
                  if (_credentials!.provisionedAt.isNotEmpty) ...[
                    const Divider(height: 24),
                    _SecretFieldRow(
                      label: 'provisionedAt',
                      value: _credentials!.provisionedAt,
                      onCopy: () => _copy(_credentials!.provisionedAt),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_tokenInfo != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '저장된 디바이스 토큰 정보',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      TextButton(
                        onPressed: _clearTokenInfo,
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SecretFieldRow(
                    label: 'accessToken',
                    value: _tokenInfo!.accessToken,
                    onCopy: () => _copy(_tokenInfo!.accessToken),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'tokenType',
                    value: _tokenInfo!.tokenType,
                    onCopy: () => _copy(_tokenInfo!.tokenType),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'roles',
                    value: _tokenInfo!.roles.join(', '),
                    onCopy: () => _copy(_tokenInfo!.roles.join(', ')),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'deviceId',
                    value: _tokenInfo!.deviceId,
                    onCopy: () => _copy(_tokenInfo!.deviceId),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'storeId',
                    value: _tokenInfo!.storeId,
                    onCopy: () => _copy(_tokenInfo!.storeId),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'storeName',
                    value: _tokenInfo!.storeName,
                    onCopy: () => _copy(_tokenInfo!.storeName),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'rustdesk.idServer',
                    value: _tokenInfo!.rustdesk.idServer,
                    onCopy: () => _copy(_tokenInfo!.rustdesk.idServer),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'rustdesk.relayServer',
                    value: _tokenInfo!.rustdesk.relayServer,
                    onCopy: () => _copy(_tokenInfo!.rustdesk.relayServer),
                  ),
                  const Divider(height: 24),
                  _SecretFieldRow(
                    label: 'rustdesk.key',
                    value: _tokenInfo!.rustdesk.key,
                    onCopy: () => _copy(_tokenInfo!.rustdesk.key),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '다음 API 호출 준비 상태',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  tokenRequestBody == null
                      ? '아직 저장된 clientId / clientSecret 이 없습니다.'
                      : 'clientId / clientSecret 이 저장되어 다음 device-auth/token 호출에 사용할 준비가 되었습니다.',
                ),
                if (tokenRequestBody != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      '{\n  "clientId": "${tokenRequestBody['clientId']}",\n  "clientSecret": "${tokenRequestBody['clientSecret']}"\n}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '디바이스 인증 헤더 준비 상태',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  authorizationHeaders == null
                      ? '아직 저장된 디바이스 액세스 토큰이 없습니다.'
                      : '저장된 액세스 토큰으로 Authorization 헤더를 구성할 수 있습니다.',
                ),
                if (authorizationHeaders != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ')
                          .convert(authorizationHeaders),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '실행 로그',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _logs.clear();
                        });
                      },
                      child: const Text('지우기'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_logs.isEmpty)
                  const Text('아직 기록된 로그가 없습니다.')
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      _logs.join('\n'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SecretFieldRow extends StatelessWidget {
  const _SecretFieldRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(value),
            ),
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy',
            ),
          ],
        ),
      ],
    );
  }
}