import 'package:flutter/material.dart';

class SessionSummaryCard extends StatelessWidget {
  final String summary;

  const SessionSummaryCard({Key? key, required this.summary}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          summary,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
