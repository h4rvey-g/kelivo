import "../../../support/business_test_harness.dart";
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/home_page_controller.dart';
import 'package:Kelivo/features/home/controllers/scroll_controller.dart';
import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('initializes chat controller before timeline scroll callbacks', (
    tester,
  ) async {
    HomePageController? controller;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(createBusinessTestPreferences()),
          ),
          ChangeNotifierProvider(create: (_) => ChatService()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _ControllerHarness(
            onCreated: (value, _, __) => controller = value,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(controller, isNotNull);
    expect(
      controller!.scrollCtrl.scrollController,
      same(controller!.scrollController),
    );

    final replacement = ChatAutoFollowScrollController();
    controller!.replaceScrollController(replacement);
    expect(controller!.scrollController, same(replacement));
    expect(controller!.scrollCtrl.scrollController, same(replacement));

    controller!.scrollCtrl.handleUserScrollIntent();
    expect(controller!.scrollCtrl.isUserScrolling, isTrue);
    await controller!.forceScrollToBottom(animate: false);
    expect(controller!.scrollCtrl.isUserScrolling, isFalse);
    expect(controller!.scrollCtrl.autoStickToBottom, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    replacement.dispose();
  });

  testWidgets('quotes selected text into the draft and focuses the input', (
    tester,
  ) async {
    late HomePageController controller;
    late TextEditingController inputController;
    late FocusNode inputFocus;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(createBusinessTestPreferences()),
          ),
          ChangeNotifierProvider(create: (_) => ChatService()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _ControllerHarness(
            onCreated: (value, textController, focusNode) {
              controller = value;
              inputController = textController;
              inputFocus = focusNode;
            },
          ),
        ),
      ),
    );

    inputController.text = 'Existing draft';
    controller.quoteSelectedText('Selected text');
    await tester.pump();

    expect(inputController.text, 'Existing draft\nSelected text\n');
    expect(inputController.selection.extentOffset, inputController.text.length);
    expect(inputFocus.hasFocus, isTrue);

    controller.quoteSelectedText('Next line\n');
    await tester.pump();
    expect(inputController.text, 'Existing draft\nSelected text\nNext line\n');
    expect(inputController.selection.extentOffset, inputController.text.length);
  });
}

class _ControllerHarness extends StatefulWidget {
  const _ControllerHarness({required this.onCreated});

  final void Function(
    HomePageController controller,
    TextEditingController inputController,
    FocusNode inputFocus,
  )
  onCreated;

  @override
  State<_ControllerHarness> createState() => _ControllerHarnessState();
}

class _ControllerHarnessState extends State<_ControllerHarness>
    with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputBarKey = GlobalKey();
  final _inputFocus = FocusNode();
  final _inputController = TextEditingController();
  final _mediaController = ChatInputBarController();
  final _scrollController = ChatAutoFollowScrollController();
  late final HomePageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomePageController(
      context: context,
      vsync: this,
      scaffoldKey: _scaffoldKey,
      inputBarKey: _inputBarKey,
      inputFocus: _inputFocus,
      inputController: _inputController,
      mediaController: _mediaController,
      scrollController: _scrollController,
    );
    widget.onCreated(_controller, _inputController, _inputFocus);
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _scaffoldKey,
    body: TextField(controller: _inputController, focusNode: _inputFocus),
  );
}
