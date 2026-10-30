import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../theme/app_theme.dart';

class NavItem {
  const NavItem(this.label, this.icone, this.iconeActive);

  final String label;
  final IconData icone;
  final IconData iconeActive;
}

const navItems = [
  NavItem('Accueil', Iconsax.home_2_copy, Iconsax.home_2),
  NavItem('Boutique', Iconsax.shop_copy, Iconsax.shop),
  NavItem('Carnet', Iconsax.note_2_copy, Iconsax.note_2),
  NavItem('Profil', Iconsax.profile_circle_copy, Iconsax.profile_circle),
];

/// Barre de navigation flottante en pilule + bouton rond « Scanner » détaché.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.index, required this.onTap, required this.onScan});

  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 64,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < navItems.length; i++)
                    _Onglet(item: navItems[i], actif: i == index, onTap: () => onTap(i)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _BoutonScan(onTap: onScan),
        ],
      ),
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet({required this.item, required this.actif, required this.onTap});

  final NavItem item;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: actif ? 2 : 1,
      child: Semantics(
        button: true,
        selected: actif,
        label: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: actif ? IvertColors.vertFond : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(actif ? item.iconeActive : item.icone,
                    size: 22, color: actif ? IvertColors.vert : IvertColors.brun),
                if (actif) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: IvertColors.vert)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoutonScan extends StatelessWidget {
  const _BoutonScan({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scanner une plante',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [IvertColors.vertClair, IvertColors.vert],
            ),
            boxShadow: [BoxShadow(color: Color(0x552C6B2F), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: const Icon(Iconsax.scan, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
