import 'package:flutter/material.dart';

import '../core/theme.dart';

Future<String?> requestParentPin(
  BuildContext context, {
  String title = '家长确认',
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: BraveColors.polar,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: const InputDecoration(
          labelText: '输入 4 位家长 PIN',
          counterText: '',
        ),
        onSubmitted: (value) {
          if (value.length == 4) Navigator.pop(context, value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result?.length == 4 ? result : null;
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFF9E3B4D) : BraveColors.midnight,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class BusyView extends StatelessWidget {
  const BusyView(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SnowFoxMark(size: 72),
          const SizedBox(height: 22),
          const CircularProgressIndicator(color: BraveColors.aurora),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: BraveColors.mist)),
        ],
      ),
    );
  }
}
