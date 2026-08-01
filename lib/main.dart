import 'package:flutter/material.dart';

import 'tabs/live.dart';
import 'tabs/recordings.dart';
import 'tabs/settings.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.teal,
      fontFamily: 'Poppins',
    ),
    home: Home(),
  ),
);

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  late TabController _tabController;
  int value = 1;

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
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
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
            Tab(icon: Icon(Icons.favorite), text: 'Live'),
            Tab(icon: Icon(Icons.folder), text: "Recordings"),
            Tab(icon: Icon(Icons.settings), text: "Settings"),
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
