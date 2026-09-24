import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';
import 'package:corterm_mobile/shared/widgets/app_shell.dart';
import 'package:corterm_mobile/shared/widgets/push_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const screen = Size(390, 844);

  Widget harness(
    PushDrawerController controller,
    GlobalKey bodyKey,
    GlobalKey menuKey,
  ) {
    return MaterialApp(
      home: PushDrawerShell(
        controller: controller,
        width: 304,
        menu: SizedBox(
          key: menuKey,
          child: const ColoredBox(
            color: Colors.black,
            child: Center(child: Text('menu')),
          ),
        ),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('custom-appbar'),
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: controller.toggle,
            ),
          ),
          body: Container(
            key: bodyKey,
            color: Colors.white,
            child: const Center(child: Text('home')),
          ),
        ),
      ),
    );
  }

  Future<void> pumpHarness(
    WidgetTester tester,
    PushDrawerController controller,
    GlobalKey bodyKey,
    GlobalKey menuKey,
  ) async {
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(controller, bodyKey, menuKey));
  }

  testWidgets('打开：内容（含 AppBar）精确右移 304，尺寸不变=纯平移', (tester) async {
    final controller = PushDrawerController();
    final bodyKey = GlobalKey();
    final menuKey = GlobalKey();
    await pumpHarness(tester, controller, bodyKey, menuKey);

    // 关闭态：内容在 x=0，菜单未挂载（不白建侧栏）。
    final bodyBefore = tester.getTopLeft(find.byKey(bodyKey));
    final bodySizeBefore = tester.getSize(find.byKey(bodyKey));
    expect(bodyBefore.dx, 0);
    expect(find.byKey(menuKey), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(bodyKey)).dx, closeTo(304, 0.01));
    expect(tester.getTopLeft(find.byKey(bodyKey)).dy, bodyBefore.dy);
    expect(tester.getSize(find.byKey(bodyKey)), bodySizeBefore);
    // 菜单占满高度、宽 304。
    expect(tester.getSize(find.byKey(menuKey)), const Size(304, 844));
    // AppBar 跟着一起右移（不是只有 body 动）。
    expect(tester.getTopLeft(find.byType(AppBar)).dx, closeTo(304, 0.01));
    expect(controller.isOpen, isTrue);

    // 汉堡按钮随内容右移后仍在屏内，再点一次收回。
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(bodyKey)).dx, 0);
    expect(controller.isOpen, isFalse);
  });

  testWidgets('展开时系统返回先收侧栏，不吃掉页面返回', (tester) async {
    final controller = PushDrawerController();
    final bodyKey = GlobalKey();
    final menuKey = GlobalKey();
    await pumpHarness(tester, controller, bodyKey, menuKey);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(controller.isOpen, isFalse);
    expect(tester.getTopLeft(find.byKey(bodyKey)).dx, 0);
  });

  testWidgets('手势：左边缘右滑打开、内容区左滑关闭、非边缘起手不误开', (tester) async {
    final controller = PushDrawerController();
    final bodyKey = GlobalKey();
    final menuKey = GlobalKey();
    await pumpHarness(tester, controller, bodyKey, menuKey);

    // 内容区中心起手右滑：不在边缘热区，不应打开。
    await tester.drag(find.byKey(bodyKey), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);

    // 左边缘起手右滑：打开。
    await tester.dragFrom(const Offset(5, 400), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    // 打开后内容只露出右移后的一条，从这条上左滑收回。
    await tester.dragFrom(const Offset(340, 400), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
  });

  testWidgets('内容区的横向手势组件优先：左边缘起手也不抢它的横滑', (tester) async {
    final controller = PushDrawerController();
    final bodyKey = GlobalKey();
    final menuKey = GlobalKey();
    var innerDrags = 0;

    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PushDrawerShell(
          controller: controller,
          width: 304,
          menu: SizedBox(
            key: menuKey,
            child: const ColoredBox(color: Colors.black),
          ),
          child: Scaffold(
            body: Container(
              key: bodyKey,
              color: Colors.white,
              // 模拟首页卡片的 flutter_slidable：自己吃掉横向拖动。
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (_) => innerDrags++,
                child: const Center(child: Text('home')),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(5, 400), const Offset(250, 0));
    await tester.pumpAndSettle();

    expect(innerDrags, greaterThan(0), reason: '内层横滑应当胜出并收到拖动');
    expect(controller.isOpen, isFalse, reason: '不应抢走内层的横向手势');
  });

  testWidgets('真实 AppShellScaffold：汉堡按钮接的是右推侧栏', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final auth = AuthController(_FakeStore());
    auth.state = const AuthState(
      status: AuthStatus.authenticated,
      username: 'tester',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: ShadApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppShellScaffold(
            tab: ShellTab.home,
            title: 'Home',
            body: Center(child: Text('home-body')),
          ),
        ),
      ),
    );
    await tester.pump();

    final barBefore = tester.getTopLeft(find.byType(AppBar));
    await tester.tap(find.byIcon(LucideIcons.menu));
    await tester.pumpAndSettle();

    // 汉堡按钮驱动的是内容整体右移（而不是 Scaffold.drawer 的覆盖层）。
    expect(
      tester.getTopLeft(find.byType(AppBar)).dx - barBefore.dx,
      closeTo(304, 0.01),
    );
    // 侧栏内容（底部用户行）随展开一起出现。
    expect(find.text('tester'), findsOneWidget);
  });
}

class _FakeStore implements TokenStore {
  @override
  String? get token => 'fake-token';
  @override
  String? get username => 'tester';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
