/// Премиальные виджеты с flutter-taste-skill паттернами
/// 
/// Этот файл экспортирует все премиальные компоненты для удобного импорта.
/// 
/// Design System:
/// - Glassmorphism с inner borders
/// - Mesh gradients для hero элементов
/// - Neon glow эффекты
/// - Spring-based animations
/// - Pill-shaped components (999px radius)
/// - Material 3 Expressive patterns
/// 
/// Использование:
/// ```dart
/// import 'package:my_chat_app/widgets/premium_widgets.dart';
/// 
/// // Primary button с mesh gradient
/// PremiumButton(
///   label: 'Войти',
///   variant: PremiumButtonVariant.primary,
///   onPressed: () {},
/// )
/// 
/// // Hero card для профиля
/// PremiumProfileCard(
///   title: 'Владимир',
///   subtitle: 'Premium пользователь',
///   isHero: true,
/// )
/// ```

export 'premium_app_bar.dart';
export 'premium_bottom_nav.dart';
export 'premium_button.dart';
export 'premium_buttons.dart';
export 'premium_chat_message_tile.dart';
export 'premium_chat_tile.dart';
export 'premium_message_bubble.dart';
export 'premium_profile_card.dart';
export 'premium_text_field.dart';
