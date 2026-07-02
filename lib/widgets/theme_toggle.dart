import 'package:flutter/material.dart';
import 'package:omr_app/services/theme_service.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemeMode>(
      icon: Icon(
        ThemeService.isDarkMode ? Icons.dark_mode : Icons.light_mode,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      tooltip: 'Change theme',
      onSelected: (ThemeMode mode) async {
        await ThemeService.setThemeMode(mode);
        // Force rebuild by using a different approach
        if (context.mounted) {
          // Just let the widget rebuild naturally when theme changes
          // The MaterialApp will handle theme switching automatically
        }
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem(
          value: ThemeMode.light,
          child: Row(
            children: [
              Icon(Icons.light_mode, 
                   color: ThemeService.currentTheme == ThemeMode.light 
                       ? Theme.of(context).colorScheme.primary 
                       : null),
              const SizedBox(width: 12),
              const Text('Light'),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: Row(
            children: [
              Icon(Icons.dark_mode,
                   color: ThemeService.currentTheme == ThemeMode.dark 
                       ? Theme.of(context).colorScheme.primary 
                       : null),
              const SizedBox(width: 12),
              const Text('Dark'),
            ],
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.system,
          child: Row(
            children: [
              Icon(Icons.settings_system_daydream,
                   color: ThemeService.currentTheme == ThemeMode.system 
                       ? Theme.of(context).colorScheme.primary 
                       : null),
              const SizedBox(width: 12),
              const Text('System'),
            ],
          ),
        ),
      ],
    );
  }
}
