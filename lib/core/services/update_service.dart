import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
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

/// 自定义云盘更新配置模型
class CustomUpdateInfo {
  final String versionTag;
  final String title;
  final String changelog;
  final String releaseUrl;
  final bool forceUpdate;
  final String minVersionTag;

  final String windowsSetupUrl;
  final String windowsZipUrl;

  final String androidArm64Url;
  final String androidArmeabiUrl;
  final String androidX86_64Url;

  final String linuxAppImageUrl;
  final String linuxZipUrl;
  final String webPackageUrl;

  final List history;

  CustomUpdateInfo({
    required this.versionTag,
    required this.title,
    required this.changelog,
    required this.releaseUrl,
    required this.forceUpdate,
    required this.minVersionTag,
    required this.windowsSetupUrl,
    required this.windowsZipUrl,
    required this.androidArm64Url,
    required this.androidArmeabiUrl,
    required this.androidX86_64Url,
    required this.linuxAppImageUrl,
    required this.linuxZipUrl,
    required this.webPackageUrl,
    required this.history,
  });

  factory CustomUpdateInfo.fromJson(Map<String, dynamic> json) {
    final historyList = json['update_history'] as List? ?? [];

    return CustomUpdateInfo(
      versionTag: json['version_tag'] ?? '0.0.0',
      title: json['update_title'] ?? '版本更新',
      changelog: json['update_log'] ?? '暂无更新日志',
      releaseUrl: json['release_url'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      minVersionTag: json['min_app_version'] ?? '0.0.0',
      windowsSetupUrl: json['windows_setup'] ?? '',
      windowsZipUrl: json['windows_zip'] ?? '',
      androidArm64Url: json['android_arm64_v8a'] ?? '',
      androidArmeabiUrl: json['android_armeabi_v7a'] ?? '',
      androidX86_64Url: json['android_x86_64'] ?? '',
      linuxAppImageUrl: json['linux_appimage'] ?? '',
      linuxZipUrl: json['linux_zip'] ?? '',
      webPackageUrl: json['web_package'] ?? '',
      history: historyList,
    );
  }
}

/// 历史版本条目
class UpdateHistoryItem {
  final String versionTag;
  final String title;
  final String changelog;
  final String windowsUrl;
  final String androidUrl;
  final String linuxUrl;
  final String webUrl;

  UpdateHistoryItem({
    required this.versionTag,
    required this.title,
    required this.changelog,
    required this.windowsUrl,
    required this.androidUrl,
    required this.linuxUrl,
    required this.webUrl,
  });

  factory UpdateHistoryItem.fromJson(Map<String, dynamic> json) {
    return UpdateHistoryItem(
      versionTag: json['version_tag'] ?? '',
      title: json['update_title'] ?? '',
      changelog: json['update_log'] ?? '',
      windowsUrl: json['windows_url'] ?? '',
      androidUrl: json['android_arm64'] ?? '',
      linuxUrl: json['linux_url'] ?? '',
      webUrl: json['web_url'] ?? '',
    );
  }
}

/// GitHub Release 通用结构
class GithubRelease {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime createdAt;
  final List assets;

  const GithubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.createdAt,
    this.assets = const [],
  });
}

/// 版本号对比解析
class VersionCompare implements Comparable<VersionCompare> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const VersionCompare(this.major, this.minor, this.patch, this.build);

  static VersionCompare? parse(String input) {
    final parts = input.split('+');
    final verParts = parts[0].split('.');
    final buildNum = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    if (verParts.length != 3) return null;
    final a = int.tryParse(verParts[0]);
    final b = int.tryParse(verParts[1]);
    final c = int.tryParse(verParts[2]);
    if (a == null || b == null || c == null) return null;

    return VersionCompare(a, b, c, buildNum);
  }

  @override
  int compareTo(VersionCompare other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }
}

const bool enableUpdateCheck = true;

class UpdateService {
  UpdateService({Dio? dio, this.useProxy = false})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;
  final bool useProxy;
  static const String updateApiUrl = 'https://fs.dy.ci/d/meta/update_meta/index.json';

  CustomUpdateInfo? _latestData;

  /// 兼容旧调试面板方法
  Future<GithubRelease?> fetchLatestRelease() async {
    final data = await fetchUpdateConfig();
    if (data == null) return null;

    return GithubRelease(
      tagName: data.versionTag,
      name: data.title,
      body: data.changelog,
      htmlUrl: data.releaseUrl,
      createdAt: DateTime.now(),
    );
  }

  Future<void> checkForUpdates(BuildContext context) async {
    if (!enableUpdateCheck) return;
    Logger.root.info('[更新] 正在检测新版本');

    try {
      final data = await fetchUpdateConfig();
      if (data == null) return;
      _latestData = data;

      final pkg = await PackageInfo.fromPlatform();
      final localVer = '${pkg.version}+${pkg.buildNumber}';

      final local = VersionCompare.parse(localVer);
      final latest = VersionCompare.parse(data.versionTag);
      final min = VersionCompare.parse(data.minVersionTag);

      if (local == null || latest == null) return;

      final needForce = min != null && local.compareTo(min) < 0;
      final hasNew = local.compareTo(latest) < 0;

      if (!hasNew) {
        Logger.root.info('[更新] 当前已是最新版本');
        return;
      }

      if (context.mounted) {
        showUpdateSheet(context, data: data, force: needForce);
      }
    } catch (e) {
      Logger.root.severe('[更新检测失败] $e');
    }
  }

  Future<void> showUpdateSheet(BuildContext context, {required CustomUpdateInfo data, required bool force}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => UpdateSheet(
        release: GithubRelease(
          tagName: data.versionTag,
          name: data.title,
          body: data.changelog,
          htmlUrl: data.releaseUrl,
          createdAt: DateTime.now(),
        ),
        updateData: data,
        forceUpdate: force,
      ),
    );
  }

  /// 仅Windows执行安装，Linux/Web全部跳过
  Future<void> downloadAndInstallWindows(BuildContext context, String url) async {
    if (kIsWeb || Platform.isLinux) return;
    if (!Platform.isWindows) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WindowsUpdateDialog(installUrl: url),
    );
  }

  Future<CustomUpdateInfo?> fetchUpdateConfig() async {
    final resp = await _dio.get(updateApiUrl);
    if (resp.statusCode != 200) return null;
    return CustomUpdateInfo.fromJson(resp.data);
  }
}

class WindowsUpdateDialog extends StatefulWidget {
  final String installUrl;
  const WindowsUpdateDialog({super.key, required this.installUrl});

  @override
  State<WindowsUpdateDialog> createState() => _WindowsUpdateDialogState();
}

class _WindowsUpdateDialogState extends State<WindowsUpdateDialog> {
  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<String> status = ValueNotifier('正在下载安装包');

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isWindows) {
      _startInstallProcess();
    }
  }

  Future<void> _startInstallProcess() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = path.join(tempDir.path, 'SolianSetup.exe');

      await Dio().download(
        widget.installUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != 0) {
            progress.value = received / total;
          }
        },
      );

      status.value = '正在启动安装程序';
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
          ValueListenableBuilder(
            valueListenable: progress,
            builder: (_, p, __) => LinearProgressIndicator(value: p),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: status,
            builder: (_, txt, __) => Text(txt),
          ),
        ],
      ),
    );
  }
}

// ========= 重点修复：Widget与State名字严格配对 =========
class UpdateSheet extends StatefulWidget {
  final GithubRelease release;
  final CustomUpdateInfo updateData;
  final bool forceUpdate;

  const UpdateSheet({
    super.key,
    required this.release,
    required this.updateData,
    required this.forceUpdate,
  });

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: '发现新版本',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.release.name).titleMedium().bold(),
            Text(widget.release.tagName),
            if (widget.forceUpdate)
              const Text('⚠️ 强制更新，旧版本无法继续使用', color: Colors.red),
            const SizedBox(height: 16),
            MarkdownWidget(data: widget.release.body),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Windows按钮
                if (!kIsWeb && Platform.isWindows && widget.updateData.windowsSetupUrl.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => UpdateService().downloadAndInstallWindows(context, widget.updateData.windowsSetupUrl),
                    icon: Icon(Symbols.install_desktop),
                    label: const Text('一键安装更新'),
                  ),
                const SizedBox(height: 8),
                // 安卓按钮
                if (!kIsWeb && Platform.isAndroid && widget.updateData.androidArm64Url.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () async {
                      final model = UpdateModel(
                        widget.updateData.androidArm64Url,
                        'Solian.apk',
                        'launcher_icon',
                        '',
                      );
                      AzhonAppUpdate.update(model);
                    },
                    icon: Icon(Symbols.system_update),
                    label: const Text('安卓一键更新'),
                  ),
                const SizedBox(height: 8),
                // Linux / Web 统一跳转
                OutlinedButton.icon(
                  onPressed: widget.forceUpdate ? null : () async {
                    await launchUrl(Uri.parse(widget.updateData.releaseUrl));
                  },
                  icon: Icon(Icons.open_in_browser),
                  label: const Text('浏览器下载 Linux / Web 版本'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
