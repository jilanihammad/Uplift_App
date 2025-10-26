import 'package:flutter/material.dart';

class ActionItemsCard extends StatelessWidget {
  final List<String> actionItems;
  final String? sessionId;
  final Function(String actionItem)? onAddToTasks;
  final Function(String actionItem)? onRemoveFromTasks;
  final bool Function(String actionItem)? isItemAlreadyAdded;

  const ActionItemsCard({
    super.key,
    required this.actionItems,
    this.sessionId,
    this.onAddToTasks,
    this.onRemoveFromTasks,
    this.isItemAlreadyAdded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (actionItems.isEmpty) {
      return _buildEmptyState(context);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.secondary.withOpacity(0.1),
            colorScheme.secondary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.secondary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.task_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your Action Plan',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${actionItems.length} items',
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...actionItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildActionItem(context, item, index);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(BuildContext context, String item, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colorScheme.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.secondary.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: theme.textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Personalized for you',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color:
                            theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onAddToTasks != null)
            _buildAddToTasksButton(context, item)
          else
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: theme.iconTheme.color?.withOpacity(0.4),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.task_alt,
            size: 48,
            color: theme.iconTheme.color?.withOpacity(0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No action items available',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.textTheme.titleMedium?.color?.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Action items will appear here based on your conversation.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAddToTasksButton(BuildContext context, String item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAlreadyAdded = isItemAlreadyAdded?.call(item) ?? false;

    return Column(
      children: [
        IconButton(
          onPressed: () {
            if (isAlreadyAdded) {
              onRemoveFromTasks?.call(item);
            } else {
              onAddToTasks?.call(item);
            }
          },
          icon: Icon(isAlreadyAdded ? Icons.check_circle : Icons.add_task),
          iconSize: 20,
          color: isAlreadyAdded ? colorScheme.secondary : colorScheme.primary,
          tooltip: isAlreadyAdded ? 'Remove from Tasks' : 'Add to Tasks',
        ),
        Text(
          isAlreadyAdded ? 'Added to\nTasks' : 'Add to\nTasks',
          style: TextStyle(
            fontSize: 10,
            color: isAlreadyAdded ? colorScheme.secondary : colorScheme.primary,
            fontWeight: isAlreadyAdded ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
