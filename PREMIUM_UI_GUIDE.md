# Premium UI Components — Upgrade Guide

Этот файл описывает новые премиальные компоненты дизайна, созданные согласно паттернам flutter-taste-skill для повышения визуального качества приложения.

## Design Philosophy

Все новые компоненты следуют паттернам:
- **Glassmorphism** с обязательными inner borders (1px white alpha 0.1)
- **Mesh gradients** (overlapping radial) вместо linear
- **Neon glows** вместо flat shadows
- **Spring animations** для feedback (scale to 0.96-0.98 on press)
- **Emphasized typography** для ключевых элементов
- **Compound shadows** (ambient + directional)

Design dials:
- **VARIANCE: 7** — bento grid layouts, Stack overlapping
- **MOTION: 5** — staggered entrance + spring feedback
- **DENSITY: 5** — стандартное mobile spacing

## Новые компоненты

### 1. PremiumChatTile

Замена стандартного ListTile для списка чатов.

**Паттерны:**
- Glassmorphism card с inner border
- Pulse animation для unread indicator
- Staggered entrance animation
- Compound shadows
- Mesh gradient overlay для pressed state

**Использование:**

```dart
// Старый способ
ListTile(
  leading: CircleAvatar(...),
  title: Text(chat.name),
  subtitle: Text(chat.lastMessage),
  onTap: () => _openChat(chat),
)

// Новый способ
PremiumChatTile(
  chat: chat,
  index: index, // для staggered animation
  onTap: () => _openChat(chat),
)
```

**Анатомия:**
- Avatar с neon ring для unread
- Title emphasized (w600)
- Subtitle muted (w500)
- Timestamp + unread badge
- Folder chip (pill shape)
- Pin indicator (icon)

### 2. PremiumMessageBubble

Замена стандартных message bubbles в чате.

**Паттерны:**
- Исходящие: mesh radial gradient + neon glow
- Входящие: glassmorphism + compound shadow
- Asymmetric corner radius (одна сторона острая)
- Spring scale on press
- Inner borders для depth

**Использование:**

```dart
// Старый способ
Container(
  decoration: BoxDecoration(
    color: isMine ? primary : surface,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(message.text),
)

// Новый способ
PremiumMessageBubble(
  text: message.text,
  isMine: message.senderId == currentUserId,
  timestamp: message.createdAt,
  isRead: message.isRead,
  onLongPress: () => _showMessageActions(message),
)
```

### 3. PremiumButton

Премиальная кнопка с mesh gradient и neon glow.

**Варианты:**
- **primary**: mesh gradient + strong neon glow
- **secondary**: glassmorphism outline
- **ghost**: transparent с hover

**Использование:**

```dart
// Primary CTA
PremiumButton(
  text: 'Отправить',
  icon: Icons.send_rounded,
  variant: PremiumButtonVariant.primary,
  expanded: true,
  onPressed: () => _send(),
)

// Secondary action
PremiumButton(
  text: 'Отмена',
  variant: PremiumButtonVariant.secondary,
  onPressed: () => Navigator.pop(context),
)

// Ghost
PremiumButton(
  text: 'Подробнее',
  variant: PremiumButtonVariant.ghost,
  icon: Icons.arrow_forward,
  onPressed: () => _showDetails(),
)
```

### 4. PremiumFAB

FAB с mesh gradient + strong neon glow.

**Использование:**

```dart
floatingActionButton: PremiumFAB(
  icon: Icons.add_rounded,
  tooltip: 'Новый чат',
  onPressed: () => _createChat(),
),
```

### 5. PremiumEmptyState

Empty state с mesh gradient icon + emphasized typography.

**Использование:**

```dart
if (chats.isEmpty)
  PremiumEmptyState(
    title: 'Нет чатов',
    subtitle: 'Начните новый диалог',
    icon: Icons.chat_bubble_outline_rounded,
  )
```

## Design Tokens

Все компоненты используют `AppDesignTokens` для:

```dart
// Glassmorphism card
AppDesignTokens.glassCard(scheme)

// Mesh gradient background
AppDesignTokens.meshGradientBackground()

// Neon glow shadows
AppDesignTokens.neonGlow(intensity: 0.4)

// Compound shadows
AppDesignTokens.compoundShadow(scheme)

// Staggered delay
AppDesignTokens.staggerDelay(index)
```

## Migration Strategy

1. **Постепенная миграция** — не переписывать всё сразу
2. **Начать с главных экранов:**
   - HomeScreen: заменить chat tiles на PremiumChatTile
   - ChatScreen: заменить message bubbles на PremiumMessageBubble
   - Dialogs: заменить кнопки на PremiumButton
3. **Сохранить старые компоненты** для legacy экранов
4. **Тестировать на разных темах** (Ultraviolet, Aurora, Ocean Pulse, Neon Samurai)

## Anti-Patterns (что НЕ делать)

❌ Uniform layout everywhere — нет variety
❌ Flat colors без градиентов
❌ Тени без glow/depth
❌ Standard Material ListTile для primary content
❌ Забывать inner borders на glass surfaces
❌ Spatial springs на color/opacity

✅ Mesh gradients для premium surfaces
✅ Glassmorphism с inner border
✅ Neon glows для accent elements
✅ Bento grids вместо uniform lists
✅ Emphasized typography для ключевых моментов
✅ Staggered animations для entrance

## Performance

- `AppDesignTokens` методы кешируют результаты где возможно
- Animations используют `SingleTickerProviderStateMixin`
- Staggered animations ограничены первыми 10 элементами списка
- Mesh gradients используют RadialGradient (hardware accelerated)

## Accessibility

Все компоненты:
- Минимум 48×48dp touch targets
- Contrast 4.5:1 для normal text
- Respect Reduce Motion (disable springs/staggers)
- Respect Reduce Transparency (fallback от glassmorphism)
- Support Dark/Light themes

## Примеры использования

См. примеры в:
- `lib/widgets/premium_chat_tile.dart` — комментарии и примеры
- `lib/widgets/premium_message_bubble.dart` — варианты использования
- `lib/widgets/premium_buttons.dart` — все варианты кнопок

## Дальнейшие улучшения

После миграции основных компонентов:
- Добавить PremiumSearchBar с glassmorphism
- Создать PremiumCard для profile/settings
- Улучшить AppBar с mesh gradient
- Добавить premium bottom sheets
- Создать animated PremiumTabBar
