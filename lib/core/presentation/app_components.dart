import 'package:flutter/material.dart';

import 'app_theme.dart';

final class MichizurePrimaryButton extends StatelessWidget {
  const MichizurePrimaryButton({
    required this.onPressed,
    required this.child,
    this.icon,
    this.buttonKey,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? MichizureGradients.primary : null,
        color: enabled ? null : MichizureColors.elevatedSurface,
        borderRadius: BorderRadius.circular(MichizureRadii.control),
      ),
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStatePropertyAll(
            enabled ? const Color(0xFF161026) : MichizureColors.textSecondary,
          ),
          overlayColor: WidgetStatePropertyAll(
            MichizureColors.textPrimary.withValues(alpha: 0.10),
          ),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: icon == null
            ? child
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [icon!, const SizedBox(width: 8), child],
              ),
      ),
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
    this.child,
    super.key,
  });

  final String label;
  final String value;
  final String? description;
  final IconData? icon;
  final Key? valueKey;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: MichizureGradients.subtle),
        child: Padding(
          padding: const EdgeInsets.all(MichizureSpacing.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: MichizureColors.purple),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: MichizureColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                key: valueKey,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: MichizureColors.pink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(description!),
              ],
              if (child != null) ...[const SizedBox(height: 14), child!],
            ],
          ),
        ),
      ),
    );
  }
}

final class MichizureStatusPill extends StatelessWidget {
  const MichizureStatusPill({
    required this.label,
    required this.icon,
    this.color = MichizureColors.purple,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MichizureRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
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
            Icon(icon, size: 48, color: MichizureColors.purple),
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
