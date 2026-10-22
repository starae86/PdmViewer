import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/l10n/app_strings.dart';

Future<void> showAppAboutDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const LText('关于'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PdmViewer', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const LText('版本 1.0.0'),
            const SizedBox(height: 12),
            const LText('一个用于浏览、搜索和管理 PowerDesigner PDM 文件的桌面工具。'),
            const SizedBox(height: 8),
            const LText('支持表结构查看、DDL / DML 预览及可选的 JDBC 数据库逆向。'),
            const Divider(height: 24),
            const _ProjectLink(
              label: 'GitHub',
              url: 'https://github.com/starae86/PdmViewer',
            ),
            const _ProjectLink(
              label: 'Gitee',
              url: 'https://gitee.com/starae86/PdmViewer',
            ),
            const _ProjectLink(
              label: '问题反馈',
              url: 'https://github.com/starae86/PdmViewer/issues',
            ),
            const _ProjectLink(
              label: '版本发布',
              url: 'https://github.com/starae86/PdmViewer/releases',
            ),
            const Divider(height: 24),
            const LText('本项目采用 MIT 协议开源，可免费使用、修改和分发，需保留版权及许可声明。'),
            const SizedBox(height: 8),
            const LText('请通过上述官方仓库获取源码和发布版本。'),
            const SizedBox(height: 12),
            Text(
              'Copyright (c) 2026 xiangpc',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const LText('关闭'),
      ),
    ],
  ),
);

class _ProjectLink extends StatelessWidget {
  const _ProjectLink({required this.label, required this.url});

  final String label;
  final String url;

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Keep the URL available for manual copying if the OS cannot open it.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('无法打开链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText('请复制链接到浏览器中打开。'),
            const SizedBox(height: 8),
            SelectableText(url),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const LText('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LText(label),
          ),
        ),
        Expanded(
          child: TextButton(
            onPressed: () => _open(context),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              minimumSize: Size.zero,
              textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                decoration: TextDecoration.underline,
              ),
            ),
            child: Text(url),
          ),
        ),
      ],
    ),
  );
}
