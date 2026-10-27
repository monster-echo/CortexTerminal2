import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/shared/layout/corterm_toolbar.dart';

void main() {
  testWidgets('adapted menu dispatches the selected typed value', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final action = cortermToolbarAction(
              context,
              PopupMenuButton<String>(
                onSelected: (value) => selected = value,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'files', child: Text('Files')),
                ],
              ),
            );
            return TextButton(
              onPressed: () => action.selectMenuItem(0),
              child: const Text('Select'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Select'));
    expect(selected, 'files');
  });
}
