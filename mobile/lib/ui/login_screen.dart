import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/auth_store.dart';
import '../core/theme.dart';
import 'common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.authStore,
    required this.onLoggedIn,
    super.key,
  });
  final AuthStore authStore;
  final ValueChanged<ApiClient> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController(text: AuthStore.defaultBaseUrl);
  final _username = TextEditingController(text: 'parent');
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final api = await widget.authStore.login(
        baseUrl: _server.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      );
      widget.onLoggedIn(api);
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 44, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SnowFoxMark(),
                const SizedBox(height: 34),
                const Text(
                  '勇敢成长',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '把纸上的故事，变成陪孩子长大的声音。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    fontSize: 17,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 38),
                FrostedPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '回到我们的雪屋',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: BraveColors.ink,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _server,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '家庭服务器地址',
                          prefixIcon: Icon(Icons.cloud_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: '家长账号',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        onSubmitted: (_) => _busy ? null : _login(),
                        decoration: const InputDecoration(
                          labelText: '家长密码',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _busy ? null : _login,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_stories),
                        label: Text(_busy ? '正在推开门…' : '进入绘本馆'),
                      ),
                    ],
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
