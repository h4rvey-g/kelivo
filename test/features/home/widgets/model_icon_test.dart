import 'package:Kelivo/features/home/widgets/model_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('supports toolbar-sized brand artwork', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CurrentModelIcon(
            providerKey: 'openai',
            modelId: 'gpt-5',
            size: 20,
            contentScale: 0.9,
            withBackground: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(CurrentModelIcon)), const Size(20, 20));
    expect(tester.getSize(find.byType(SvgPicture)), const Size(18, 18));
  });
}
