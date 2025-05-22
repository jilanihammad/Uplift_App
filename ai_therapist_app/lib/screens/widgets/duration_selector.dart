import 'package:flutter/material.dart';

class DurationSelector extends StatelessWidget {
  final int? selectedDuration;
  final void Function(int) onDurationSelected;

  const DurationSelector({
    Key? key,
    this.selectedDuration,
    required this.onDurationSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).primaryColor.withOpacity(0.05),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Select Session Duration',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDurationButton(context, 5),
                const SizedBox(width: 24),
                _buildDurationButton(context, 15),
                const SizedBox(width: 24),
                _buildDurationButton(context, 30),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationButton(BuildContext context, int minutes) {
    final isSelected = selectedDuration == minutes;
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onDurationSelected(minutes),
          splashColor: Theme.of(context).primaryColor.withOpacity(0.3),
          highlightColor: Theme.of(context).primaryColor.withOpacity(0.2),
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? Theme.of(context).primaryColor.withOpacity(0.3)
                  : Theme.of(context).primaryColor.withOpacity(0.15),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$minutes',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Text(
                  'min',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).primaryColor.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
