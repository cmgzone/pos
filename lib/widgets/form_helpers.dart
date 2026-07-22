import 'package:flutter/material.dart';

class FormValidator {
  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 10) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  static String? minLength(String? value, int length, [String fieldName = 'This field']) {
    if (value == null || value.length < length) {
      return '$fieldName must be at least $length characters';
    }
    return null;
  }

  static String? maxLength(String? value, int length, [String fieldName = 'This field']) {
    if (value != null && value.length > length) {
      return '$fieldName must be less than $length characters';
    }
    return null;
  }

  static String? number(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (double.tryParse(value.trim()) == null) {
      return 'Please enter a valid number';
    }
    return null;
  }

  static String? positiveNumber(String? value, [String fieldName = 'This field']) {
    final numError = number(value, fieldName);
    if (numError != null) return numError;
    if (double.parse(value!.trim()) <= 0) {
      return '$fieldName must be greater than zero';
    }
    return null;
  }

  static String? Function(String?) combine(List<String? Function(String?)> validators) {
    return (String? value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) return error;
      }
      return null;
    };
  }
}

class FormSubmitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const FormSubmitButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : icon != null
              ? Icon(icon)
              : const SizedBox.shrink(),
      label: Text(label),
    );
  }
}

class FormCancelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const FormCancelButton({
    super.key,
    this.label = 'Cancel',
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
