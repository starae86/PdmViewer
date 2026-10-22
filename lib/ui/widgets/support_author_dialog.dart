import 'package:flutter/material.dart';

import '../../app/l10n/app_strings.dart';

Future<void> showSupportAuthorDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const LText('赞赏作者'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LText('如果这个工具对你有帮助，欢迎自愿赞赏支持。感谢你的支持！'),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 20,
              children: const [
                _PaymentCode(label: '支付宝', asset: 'assets/alipay.jpg'),
                _PaymentCode(label: '微信支付', asset: 'assets/wechat_pay.png'),
              ],
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

class _PaymentCode extends StatelessWidget {
  const _PaymentCode({required this.label, required this.asset});

  final String label;
  final String asset;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LText(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        ColoredBox(
          // Keep the original payment code readable in dark themes as well.
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              asset,
              width: 200,
              height: 200,
              fit: BoxFit.contain,
              semanticLabel: context.tr(label),
            ),
          ),
        ),
      ],
    ),
  );
}
