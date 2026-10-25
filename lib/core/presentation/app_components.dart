import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_theme.dart';

final class MichizureHomeAction extends StatelessWidget {
  const MichizureHomeAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('home-navigation-button'),
      tooltip: 'ホームへ戻る',
      onPressed: () => context.go('/home'),
      icon: const Icon(Icons.home_outlined),
    );
  }
}

/// 画面内で最も重要な1操作。1画面に1つだけ置く。
final class MichizurePrimaryButton extends StatelessWidget {
  const MichizurePrimaryButton({
    required this.onPressed,
    required this.child,
    this.icon,
    this.buttonKey,
    this.accent = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Key? buttonKey;

  /// 負債の返済など、朱色で強調すべき操作。
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final style = accent
        ? FilledButton.styleFrom(
            backgroundColor: MichizureColors.accent,
            foregroundColor: MichizureColors.onAccent,
          )
        : null;
    if (icon == null) {
      return FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }
    return FilledButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: style,
      icon: icon,
      label: child,
    );
  }
}

final class MichizureMetricCard extends StatelessWidget {
  const MichizureMetricCard({
    required this.label,
    required this.value,
    this.description,
    this.icon,
    this.valueKey,
    this.progress,
    this.child,
    super.key,
  });

  final String label;
  final String value;
  final String? description;
  final IconData? icon;
  final Key? valueKey;

  /// 0.0〜1.0の進捗。nullなら表示しない。
  final double? progress;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MichizureSpacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: MichizureColors.textSecondary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(label, style: MichizureTextStyles.overline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              key: valueKey,
              style: MichizureTextStyles.counter.copyWith(
                fontSize: 40,
                color: MichizureColors.accent,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 16),
              MichizureProgressBar(value: progress!),
            ],
            if (description != null) ...[
              const SizedBox(height: 10),
              Text(description!),
            ],
            if (child != null) ...[const SizedBox(height: 14), child!],
          ],
        ),
      ),
    );
  }
}

final class MichizureStatusPill extends StatelessWidget {
  const MichizureStatusPill({
    required this.label,
    required this.icon,
    this.color = MichizureColors.textSecondary,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(MichizureRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class MichizureSectionHeader extends StatelessWidget {
  const MichizureSectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, MichizureSpacing.section, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: MichizureTextStyles.overline)),
          ?trailing,
        ],
      ),
    );
  }
}

final class MichizureProgressBar extends StatelessWidget {
  const MichizureProgressBar({
    required this.value,
    this.height = 6,
    this.color = MichizureColors.accent,
    super.key,
  });

  final double value;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MichizureRadii.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        color: color,
        backgroundColor: MichizureColors.elevatedSurface,
      ),
    );
  }
}

/// 表示名の頭文字だけを使う、画像なしのアバター。
final class MichizureAvatar extends StatelessWidget {
  const MichizureAvatar({
    required this.name,
    this.size = 36,
    this.highlighted = false,
    super.key,
  });

  final String name;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highlighted
            ? MichizureColors.accent
            : MichizureColors.elevatedSurface,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: highlighted
              ? MichizureColors.onAccent
              : MichizureColors.textPrimary,
        ),
      ),
    );
  }
}

final class MichizureEmptyState extends StatelessWidget {
  const MichizureEmptyState({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MichizureSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: MichizureColors.textTertiary),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

final class MichizureLoadingState extends StatelessWidget {
  const MichizureLoadingState({this.label = '読み込んでいます', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(label),
        ],
      ),
    );
  }
}

final class MichizureErrorState extends StatelessWidget {
  const MichizureErrorState({
    required this.message,
    this.onRetry,
    this.messageKey,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    return MichizureEmptyState(
      icon: Icons.error_outline,
      message: message,
      action: onRetry == null
          ? null
          : MichizurePrimaryButton(
              onPressed: onRetry,
              child: const Text('再試行'),
            ),
      key: messageKey,
    );
  }
}

/// 「残り N 回」を数字だけ大きく表示する。
///
/// 1つの[Text]として描画するため、文言全体で検索・読み上げできる。
final class MichizureRepCount extends StatelessWidget {
  const MichizureRepCount({
    required this.reps,
    this.prefix = '残り',
    this.fontSize = 56,
    this.color = MichizureColors.accent,
    this.textKey,
    super.key,
  });

  final int reps;
  final String prefix;
  final double fontSize;
  final Color color;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final unitStyle = TextStyle(
      fontSize: fontSize * 0.34,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: color,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$prefix ', style: unitStyle),
          TextSpan(
            text: '$reps',
            style: MichizureTextStyles.counter.copyWith(
              fontSize: fontSize,
              color: color,
            ),
          ),
          TextSpan(text: ' 回', style: unitStyle),
        ],
      ),
      key: textKey,
    );
  }
}
