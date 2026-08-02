import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'themes/light.dart';
import 'themes/dark.dart';

import 'providers/theme.dart';
import 'providers/language.dart';

import 'tabs/live.dart';
import 'tabs/recordings.dart';
import 'tabs/settings.dart';

void main() => runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
    ],
    child: App(),
  ),
);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lightMode,
      darkTheme: darkMode,
      themeMode: themeProvider.darkmode ? ThemeMode.dark : ThemeMode.light,
      home: Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq, color: Colors.teal[800], size: 30),
            SizedBox(width: 10),
            Text.rich(
              TextSpan(
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22),
                children: [
                  TextSpan(
                    text: 'APEX',
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[800],
                    ),
                  ),
                  TextSpan(
                    text: ' CARDIO',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.teal[800],
                    ), // Poppins-Medium
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.favorite),
              text: languageProvider.translate("live_tab"),
            ),
            Tab(
              icon: Icon(Icons.folder),
              text: languageProvider.translate("recordings_tab"),
            ),
            Tab(
              icon: Icon(Icons.settings),
              text: languageProvider.translate("settings_tab"),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [Live(), Recordings(), Settings()],
      ),
    );
  }
}
