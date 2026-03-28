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
  String _appVersion = '';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _credentials = DeviceProvisioningService.getStoredCredentials();
    if (_credentials != null) {
      _serialNumberController.text = _credentials!.serialNumber;
    }
    _loadAppVersion();
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

  bool get _isSerialNumberValid {
    return _serialPattern.hasMatch(_serialNumberController.text.trim());
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();

    final serialNumber = _serialNumberController.text.trim();
    if (!_serialPattern.hasMatch(serialNumber)) {
      showToast('등록 코드는 6~8자리 숫자여야 합니다');
      return;
    }

    if (_appVersion.trim().isEmpty) {
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
      );
      if (!mounted) return;
      setState(() {
        _credentials = credentials;
      });
      showToast('디바이스 프로비저닝이 완료되었습니다');
    } on RequestException catch (error) {
      showToast(error.cause);
    } catch (_) {
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
    });
    showToast('저장된 프로비저닝 정보를 삭제했습니다');
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    showToast('Copied');
  }

  @override
  Widget build(BuildContext context) {
    final tokenRequestBody = DeviceProvisioningService.getStoredTokenRequestBody();

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