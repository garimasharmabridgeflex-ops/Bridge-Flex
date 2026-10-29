import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

class NavItem {
  const NavItem({required this.icon, required this.selectedIcon, required this.label});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class NavCenterAction {
  const NavCenterAction({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
}

/// A floating "pill" bottom nav — the selected tab expands into an
/// icon+label pill in the brand color, everything else stays a plain grey
/// icon. Deliberately not the stock Material [NavigationBar] look, per the
/// UI-refresh request to modernize the nav chrome, not just the palette.
/// [centerAction], when set, adds a raised circular button straddling the
/// top edge of the bar — the "create" shortcut both reference designs put
/// front and center — independent of [items]'s tab/index bookkeeping.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.centerAction,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final NavCenterAction? centerAction;

  @override
  Widget build(BuildContext context) {
    final half = (items.length / 2).ceil();
    final leftItems = centerAction == null ? items : items.take(half).toList();
    final rightItems = centerAction == null ? <NavItem>[] : items.skip(half).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: SizedBox(
          height: centerAction != null ? 78 : 64,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2A4A),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x400F172A),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: centerAction == null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (var i = 0; i < leftItems.length; i++)
                            _NavTile(
                              item: leftItems[i],
                              selected: i == selectedIndex,
                              onTap: () => onDestinationSelected(i),
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                for (var i = 0; i < leftItems.length; i++)
                                  Flexible(
                                    child: _NavTile(
                                      item: leftItems[i],
                                      selected: i == selectedIndex,
                                      onTap: () => onDestinationSelected(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 48),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                for (var i = 0; i < rightItems.length; i++)
                                  Flexible(
                                    child: _NavTile(
                                      item: rightItems[i],
                                      selected: (half + i) == selectedIndex,
                                      onTap: () => onDestinationSelected(half + i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              if (centerAction != null)
                Positioned(
                  top: 0,
                  child: _CenterActionButton(action: centerAction!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterActionButton extends StatelessWidget {
  const _CenterActionButton({required this.action});
  final NavCenterAction action;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.tooltip ?? '',
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: AppColors.primary.withValues(alpha: 0.5),
        child: InkWell(
          onTap: action.onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            height: 56,
            width: 56,
            child: Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: 20,
              color: selected ? Colors.white : const Color(0xFF94A3B8),
            ),
            if (selected) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
