import 'package:flutter/material.dart';

import '../game/models.dart';

Color roleColor(Role r) => switch (r) {
      Role.duke => const Color(0xFF7B3FA0),
      Role.assassin => const Color(0xFF3A3A44),
      Role.captain => const Color(0xFF2D6CB5),
      Role.ambassador => const Color(0xFF2E8B57),
      Role.contessa => const Color(0xFFB8323C),
    };

IconData roleIcon(Role r) => switch (r) {
      Role.duke => Icons.account_balance,
      Role.assassin => Icons.dangerous,
      Role.captain => Icons.anchor,
      Role.ambassador => Icons.handshake,
      Role.contessa => Icons.diamond,
    };

Role? roleOrNull(dynamic name) =>
    name == null ? null : Role.values.byName(name as String);

/// A playing card. [role] null means face down.
class InfluenceCard extends StatelessWidget {
  const InfluenceCard({
    super.key,
    required this.role,
    this.revealed = false,
    this.width = 120,
    this.selected = false,
    this.showAbility = true,
    this.onTap,
  });

  final Role? role;
  final bool revealed;
  final double width;
  final bool selected;
  final bool showAbility;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.45;
    final r = role;
    final Widget face;
    if (r == null) {
      face = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.08),
          gradient: const LinearGradient(
            colors: [Color(0xFF2A2430), Color(0xFF1A161E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFD4A84B), width: 1.5),
        ),
        child: Center(
          child: Text('C',
              style: TextStyle(
                  fontSize: width * 0.35,
                  color: const Color(0xFFD4A84B),
                  fontWeight: FontWeight.w300)),
        ),
      );
    } else {
      final small = width < 90;
      face = Container(
        padding: EdgeInsets.all(width * 0.07),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.08),
          gradient: LinearGradient(
            colors: [roleColor(r), Color.lerp(roleColor(r), Colors.black, 0.5)!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(
              color: selected ? Colors.white : const Color(0x55FFFFFF),
              width: selected ? 3 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(roleIcon(r), size: width * 0.32, color: Colors.white),
            SizedBox(height: width * 0.05),
            FittedBox(
              child: Text(r.label.toUpperCase(),
                  style: TextStyle(
                      fontSize: width * 0.13,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            if (showAbility && !small) ...[
              SizedBox(height: width * 0.05),
              Text(r.ability,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: width * 0.075,
                      color: Colors.white70,
                      height: 1.25)),
            ],
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: h,
        transform: Matrix4.translationValues(0, selected ? -8 : 0, 0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: revealed ? 0.35 : 1, child: face),
            if (revealed && width >= 40)
              Center(
                child: Transform.rotate(
                  angle: -0.5,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.redAccent, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('LOST',
                        style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: width * 0.12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small coloured pill naming a role.
class RoleChip extends StatelessWidget {
  const RoleChip(this.role, {super.key});
  final Role role;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: roleColor(role),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(role.label,
            style: const TextStyle(fontSize: 11, color: Colors.white)),
      );
}
