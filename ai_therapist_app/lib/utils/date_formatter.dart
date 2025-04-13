// lib/utils/date_formatter.dart

import 'package:intl/intl.dart';

class DateFormatter {
  static String formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }
  
  static String formatDateTime(DateTime date) {
    return DateFormat('MMM d, yyyy - h:mm a').format(date);
  }
  
  static String formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }
  
  static String formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }
  
  static String formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds} seconds';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes} minutes';
    } else if (duration.inDays < 1) {
      return '${duration.inHours} hours';
    } else {
      return '${duration.inDays} days';
    }
  }
}