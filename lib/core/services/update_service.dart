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

  final String windowsSetupExe;
  final String windowsPortableZip;

  final String androidArm64;
  final String androidArmeabi;
  final String androidX86_64;

  final String linuxAppImage;
  final String linuxBundleZip;
  final String webPackage;

  final List<UpdateHistoryItem> history;

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
    required this.linuxBundleZip,
    required this.webPackage,
    required this.history,
  });

  factory CustomUpdateInfo.fromJson(Map<String, dynamic> json) {
    final historyList = json['update_history'] as List? ?? [];
    final history = historyList.map((e) => UpdateHistoryItem.fromJson(e)).toList();

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
      linuxBundleZip: json['linux_bundle_zip'] ?? '',
      webPackage: json['web_package'] ?? '',
      history: history,
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

/// 旧兼容Release结构
class GithubReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime createdAt;
  final List<GithubReleaseAsset> assets;

  const GithubReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.createdAt,
    this.assets = const [],
  });
}

class GithubReleaseAsset {
  final String name;
  final String browserDownloadUrl;

  const GithubReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
  });
}

/// 版本号解析对比
class _ParsedVersion implements Comparable<_ParsedVersion> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const _ParsedVersion(this.major, this.minor, this.patch, this.build);

  static _ParsedVersion? tryParse(String input) {
    final parts = input.split('+');
    final ver = parts[0].split('.');
    final build = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    if (ver.length != 3) return null;
    return _ParsedVersion(
      int.tryParse(ver[0]) ?? 0,
      int.tryParse(ver[1]) ?? 0,
      int.tryParse(ver[2]) ?? 0,
      build,
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
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;
  final bool useProxy;
  static const String updateJsonUrl = 'https://fs.dy.ci/d/meta/update_meta/index.json';

  CustomUpdateInfo? _updateData;

  Future<void> checkForUpdates(BuildContext context) async {
    if (!kEnableBuiltInUpdate) return;
    Logger.root.info('[更新] 开始检测云端版本');

    try {
      final data = await fetchUpdateConfig();
      if (data == null) return;
      _updateData = data;

      final pkg = await PackageInfo.fromPlatform();
      final local = '${pkg.version}+${pkg.buildNumber}';

      final localVer = _ParsedVersion.tryParse(local);
      final latestVer = _ParsedVersion.tryParse(data.versionTag);
      final minVer = _ParsedVersion.tryParse(data.minVersionTag);

      // 低于最低版本强制拦截
      if (minVer != null && localVer != null && localVer.compareTo(minVer) < 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前版本已过期，请升级应用')),
          );
        }
        return;
      }

      final hasNew = latestVer != null && localVer != null && latestVer.compareTo(localVer) > 0;
      if (!hasNew) {
        Logger.root.info('[更新] 当前已是最新版本');
        return;
      }

      if (!context.mounted) return;
      final release = GithubReleaseInfo(
        tagName: data.versionTag,
        name: data.title,
        body: data.changelog,
        htmlUrl: data.releaseUrl,
        createdAt: DateTime.now(),
        assets: [],
      );

      await showUpdateSheet(context, release);
    } catch (e) {
      Logger.root.severe('[更新检测失败] $e');
    }
  }

  Future<void> showUpdateSheet(BuildContext context, GithubReleaseInfo release) async {
    if (!context.mounted || _updateData == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => _UpdateSheet(
        release: release,
        updateData: _updateData!,
        forceUpdate: _updateData!.forceUpdate,
      ),
    );
  }

  /// Windows自动下载安装EXE
  Future<void> downloadAndInstallWindowsExe(BuildContext context, String url) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WindowsUpdateDialog(installUrl: url),
    );
  }

  Future<CustomUpdateInfo?> fetchUpdateConfig() async {
    final resp = await _dio.get(updateJsonUrl);
    if (resp.statusCode != 200) return null;
    return CustomUpdateInfo.fromJson(resp.data);
  }
}

/// Windows下载解压安装弹窗
class _WindowsUpdateDialog extends StatefulWidget {
  final String installUrl;
  const _WindowsUpdateDialog({required this.installUrl});

  @override
  State<_WindowsUpdateDialog> createState() => _WindowsUpdateDialogState();
}

class _WindowsUpdateDialogState extends State<_WindowsUpdateDialog> {
  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<String> status = ValueNotifier('正在下载安装包');

  @override
  void initState() {
    super.initState();
    _startInstall();
  }

  Future<void> _startInstall() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = path.join(tempDir.path, 'MeikeSetup.exe');

      await Dio().download(
        widget.installUrl,
        savePath,
        onReceiveProgress: (r, t) => progress.value = r / t,
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
      title: const Text('正在更新每刻'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, p, __) => LinearProgressIndicator(value: p),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, s, __) => Text(s),
          ),
        ],
      ),
    );
  }
}

/// 更新底部弹窗
class _UpdateSheet extends StatefulWidget {
  final GithubReleaseInfo release;
  final CustomUpdateInfo updateData;
  final bool forceUpdate;

  const _UpdateSheet({required this.release, required this.updateData, required this.forceUpdate});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: '发现新版本',
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // 【修复1】移除 mainAxisSize: MainAxisSize.min，避免与 Expanded 冲突导致弹窗无法显示
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.release.name, style: Theme.of(context).textTheme.titleMedium).bold(),
                  Text(widget.release.tagName),
                  if (widget.forceUpdate)
                    const Text('⚠️ 强制更新，不更新无法继续使用', color: Colors.red),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MarkdownTextContent(content: widget.release.body),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Windows 安装版
                  if (Platform.isWindows && widget.updateData.windowsSetupExe.isNotEmpty)
                    FilledButton.icon(
                      width: double.infinity,
                      onPressed: () => UpdateService().downloadAndInstallWindowsExe(
                          context, widget.updateData.windowsSetupExe),
                      icon: const Icon(Symbols.install_desktop),
                      label: const Text('一键安装更新'),
                    ),
                  const SizedBox(height: 8),
                  // 安卓自动更新
                  if (Platform.isAndroid && widget.updateData.androidArm64.isNotEmpty)
                    FilledButton.icon(
                      width: double.infinity,
                      // 【修复2】添加异常捕获，避免更新失败导致应用崩溃
                      onPressed: () async {
                        try {
                          final model = UpdateModel(
                            widget.updateData.androidArm64,
                            'Meike.apk',
                            'launcher_icon',
                            '',
                          );
                          AzhonAppUpdate.update(model);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('启动更新失败：$e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Symbols.update_app),
                      label: const Text('安卓一键更新'),
                    ),
                  const SizedBox(height: 8),
                  // 前往网页下载全平台
                  OutlinedButton.icon(
                    width: double.infinity,
                    onPressed: widget.forceUpdate
                        ? null
                        : () async {
                            await launchUrl(Uri.parse(widget.updateData.releaseUrl));
                          },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('浏览器下载Linux/便携版'),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
