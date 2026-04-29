import 'dart:async';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_update/azhon_app_update.dart';
import 'package:flutter_app_update/update_model.dart';
import 'package:island/shared/widgets/content/markdown.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:process_run/process_run.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:island/shared/widgets/layouts/sheet_scaffold.dart';

/// ==================== 数据模型 ====================
class CustomUpdateInfo {
  final String versionTag;
  final String title;
  final String changelog;
  final String releaseUrl;
  final bool forceUpdate;
  final String minVersionTag;

  final String windowsSetupExe;
  final String windowsPortableZip;
  final String androidArm64;
  final String androidArmeabi;
  final String androidX86_64;
  final String linuxAppImage;
  final String linuxZip;
  final String webPackage;

  final List history;

  CustomUpdateInfo({
    required this.versionTag,
    required this.title,
    required this.changelog,
    required this.releaseUrl,
    required this.forceUpdate,
    required this.minVersionTag,
    required this.windowsSetupExe,
    required this.windowsPortableZip,
    required this.androidArm64,
    required this.androidArmeabi,
    required this.androidX86_64,
    required this.linuxAppImage,
    required this.linuxZip,
    required this.webPackage,
    required this.history,
  });

  factory CustomUpdateInfo.fromJson(Map<String, dynamic> json) {
    return CustomUpdateInfo(
      versionTag: json['version_tag'] ?? '0.0.0+0',
      title: json['update_title'] ?? '版本更新',
      changelog: json['update_log'] ?? '暂无更新日志',
      releaseUrl: json['release_url'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      minVersionTag: json['min_app_version'] ?? '0.0.0+0',
      windowsSetupExe: json['windows_setup_exe'] ?? '',
      windowsPortableZip: json['windows_portable_zip'] ?? '',
      androidArm64: json['android_arm64_v8a'] ?? '',
      androidArmeabi: json['android_armeabi_v7a'] ?? '',
      androidX86_64: json['android_x86_64'] ?? '',
      linuxAppImage: json['linux_appimage'] ?? '',
      linuxZip: json['linux_bundle_zip'] ?? '',
      webPackage: json['web_package'] ?? '',
      history: json['update_history'] as List? ?? [],
    );
  }
}

/// 版本比较
class _ParsedVersion implements Comparable<_ParsedVersion> {
  final int major, minor, patch, build;
  const _ParsedVersion(this.major, this.minor, this.patch, this.build);

  static _ParsedVersion? tryParse(String input) {
    final parts = input.split('+');
    final verParts = parts[0].split('.');
    final buildNum = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (verParts.length != 3) return null;
    return _ParsedVersion(
      int.tryParse(verParts[0]) ?? 0,
      int.tryParse(verParts[1]) ?? 0,
      int.tryParse(verParts[2]) ?? 0,
      buildNum,
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }
}

const bool kEnableBuiltInUpdate = true;

class UpdateService {
  UpdateService({Dio? dio, this.useProxy = false})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));

  final Dio _dio;
  final bool useProxy;

  static const String updateApiUrl = 'https://fs.dy.ci/d/meta/update_meta/index.json';

  CustomUpdateInfo? _latestData;

  Future<CustomUpdateInfo?> fetchUpdateConfig() async {
    try {
      final resp = await _dio.get(updateApiUrl);
      if (resp.statusCode != 200) return null;
      return CustomUpdateInfo.fromJson(resp.data);
    } catch (e) {
      Logger.root.severe('[Update] 获取更新配置失败: $e');
      return null;
    }
  }

  Future<void> checkForUpdates(BuildContext context) async {
    if (!kEnableBuiltInUpdate) return;

    try {
      final data = await fetchUpdateConfig();
      if (data == null) return;
      _latestData = data;

      final pkg = await PackageInfo.fromPlatform();
      final localVer = '\( {pkg.version}+ \){pkg.buildNumber}';

      final local = _ParsedVersion.tryParse(localVer);
      final latest = _ParsedVersion.tryParse(data.versionTag);

      if (local == null || latest == null || latest.compareTo(local) <= 0) {
        Logger.root.info('[更新] 当前已是最新版本');
        return;
      }

      if (context.mounted) {
        await showUpdateSheet(context);
      }
    } catch (e) {
      Logger.root.severe('[更新检测失败] $e');
    }
  }

  // 兼容旧调用方式
  Future<void> showUpdateSheet(BuildContext context, [dynamic release]) async {
    if (_latestData == null) {
      final data = await fetchUpdateConfig();
      if (data != null) _latestData = data;
    }
    if (context.mounted) {
      await _showUpdateBottomSheet(context);
    }
  }

  Future<void> _showUpdateBottomSheet(BuildContext context) async {
    final data = _latestData;
    if (data == null || !context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => _UpdateSheet(updateData: data),
    );
  }

  // Windows 一键更新
  Future<void> downloadAndInstallWindows(BuildContext context, String url) async {
    if (kIsWeb) return;
    if (!Platform.isWindows) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WindowsUpdateDialog(installUrl: url),
    );
  }
}

// ====================== Windows 更新弹窗 ======================
class _WindowsUpdateDialog extends StatefulWidget {
  final String installUrl;
  const _WindowsUpdateDialog({super.key, required this.installUrl});

  @override
  State<_WindowsUpdateDialog> createState() => _WindowsUpdateDialogState();
}

class _WindowsUpdateDialogState extends State<_WindowsUpdateDialog> {
  final progress = ValueNotifier<double>(0.0);
  final status = ValueNotifier<String>('正在下载安装包...');

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isWindows) {
      _startInstallProcess();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _startInstallProcess() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = path.join(tempDir.path, 'SolianSetup.exe');

      await Dio().download(widget.installUrl, savePath,
          onReceiveProgress: (received, total) {
        if (total != 0) progress.value = received / total;
      });

      status.value = '正在启动安装程序...';
      await Process.start(savePath, [], workingDirectory: tempDir.path);
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      status.value = '更新失败：$e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在更新'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) => LinearProgressIndicator(value: value),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, value, __) => Text(value),
          ),
        ],
      ),
    );
  }
}

// ====================== 更新弹窗界面 ======================
class _UpdateSheet extends StatelessWidget {
  final CustomUpdateInfo updateData;

  const _UpdateSheet({super.key, required this.updateData});

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: '发现新版本',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(updateData.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(updateData.versionTag),
            if (updateData.forceUpdate)
              const Text('⚠️ 强制更新，旧版本无法继续使用', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            MarkdownTextContent(content: updateData.changelog),
            const SizedBox(height: 24),

            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!kIsWeb && Platform.isAndroid && updateData.androidArm64.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () {
                      final model = UpdateModel(updateData.androidArm64, "solian.apk", "launcher_icon", "");
                      AzhonAppUpdate.update(model);
                    },
                    icon: const Icon(Symbols.system_update),
                    label: const Text('安卓一键更新'),
                  ),

                const SizedBox(height: 8),

                if (!kIsWeb && Platform.isWindows && updateData.windowsSetupExe.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => UpdateService().downloadAndInstallWindows(context, updateData.windowsSetupExe),
                    icon: const Icon(Symbols.install_desktop),
                    label: const Text('一键安装更新'),
                  ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: updateData.forceUpdate ? null : () => launchUrl(Uri.parse(updateData.releaseUrl)),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('浏览器下载其他版本'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
