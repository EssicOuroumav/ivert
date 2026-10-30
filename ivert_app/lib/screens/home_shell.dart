import 'package:flutter/material.dart';

import '../widgets/floating_nav.dart';
import 'accueil_screen.dart';
import 'boutique_screen.dart';
import 'carnet_screen.dart';
import 'profil_screen.dart';
import 'scan/prescan_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _carnet = GlobalKey<CarnetScreenState>();

  Future<void> _scanner() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrescanScreen()));
    _carnet.currentState?.recharger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          AccueilScreen(onScan: _scanner, onOuvrirCarnet: () => setState(() => _index = 2)),
          const BoutiqueScreen(),
          CarnetScreen(key: _carnet, onScan: _scanner),
          const ProfilScreen(),
        ],
      ),
      bottomNavigationBar: FloatingNav(
        index: _index,
        onTap: (i) {
          setState(() => _index = i);
          if (i == 2) _carnet.currentState?.recharger();
        },
        onScan: _scanner,
      ),
    );
  }
}
