import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/download_provider.dart';
import 'screens/home_screen.dart';
import 'utils/string_utils.dart';

/// Loads required resources and starts the Flutter application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StringUtils.load();
  runApp(const DownloadManagerApp());
}

/// Root widget that wires providers and application theme.
class DownloadManagerApp extends StatelessWidget {
  /// Creates the root application widget.
  const DownloadManagerApp({super.key});

  static const Color _seedColor = Color(0xFF006D77);

  /// Builds the app shell and dependency provider tree.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DownloadProvider>(
      create: (_) => DownloadProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: StringUtils.get('appTitle'),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
