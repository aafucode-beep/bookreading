import 'package:brave_growth/core/auth_store.dart';
import 'package:brave_growth/core/theme.dart';
import 'package:brave_growth/ui/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('登录页展示原创雪狐品牌和家庭服务器字段', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: braveTheme(),
        home: LoginScreen(authStore: AuthStore(), onLoggedIn: (_) {}),
      ),
    );

    expect(find.text('勇敢成长'), findsOneWidget);
    expect(find.text('回到我们的雪屋'), findsOneWidget);
    expect(find.text('家庭服务器地址'), findsOneWidget);
    expect(find.byType(SnowFoxMark), findsOneWidget);
  });
}
