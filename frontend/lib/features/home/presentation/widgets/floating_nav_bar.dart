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
    final scheme = Theme.of(context).colorScheme;
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
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                // Without a center action the tiles just share the bar evenly.
                // With one, each side gets its OWN equal half (both Expanded)
                // separated by the fixed 56px button gap, so the FAB stays dead
                // centered no matter how many tiles land on each side. A flat
                // row of equal tiles + a fixed gap does not: an odd split (e.g.
                // a nursery's 3 tabs → 2 left / 1 right) pushes the FAB half a
                // tile off-centre.
                child: centerAction == null
                    ? Row(
                        children: [
                          for (var i = 0; i < leftItems.length; i++)
                            Expanded(
                              child: _NavTile(
                                item: leftItems[i],
                                selected: i == selectedIndex,
                                onTap: () => onDestinationSelected(i),
                              ),
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                for (var i = 0; i < leftItems.length; i++)
                                  Expanded(
                                    child: _NavTile(
                                      item: leftItems[i],
                                      selected: i == selectedIndex,
                                      onTap: () => onDestinationSelected(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 56),
                          Expanded(
                            child: Row(
                              children: [
                                for (var i = 0; i < rightItems.length; i++)
                                  Expanded(
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
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 0, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: 22,
              color: selected ? AppColors.primary : scheme.onSurfaceVariant,
            ),
            if (selected)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
