# Premium Widgets Guide 🦋

Коллекция премиальных Flutter виджетов, следующих **flutter-taste-skill** паттернам для высококачественного мобильного UI.

## Design Philosophy

### Три главных принципа:

1. **Glassmorphism** — не стандартный Material, а стекло с внутренними границами
2. **Mesh Gradients** — для hero-элементов вместо плоских цветов
3. **Spring Physics** — вместо tween-анимаций

### Anti-Slop Ban List 🚫

- ❌ Дефолтный `Scaffold` без кастомного фона
- ❌ AI-фиолетовый `#7C3AED` и generic indigo-purple градиенты
- ❌ Стандартный `ListTile` для основного контента
- ❌ Одинаковые скругления везде
- ❌ Tween-анимации `Duration(milliseconds: 300)`

## Design Dials

Каждый виджет настроен по трём параметрам:

### VARIANCE (сложность layout)
- `1-3`: Простой column/list
- `4-6`: Асимметричные ячейки
- **`7-9`**: Bento grids, Stack overlays ← наши виджеты здесь
- `10`: Multi-span bento, perspective transforms

### MOTION (анимации)
- `1-3`: Простые fade
- `4-6`: Staggered entrance, press feedback
- **`7-9`**: Scroll-driven эффекты ← здесь
- `10`: Rive, physics interactions

### DENSITY (плотность информации)
- `1-3`: Editorial spacing (32-48px)
- **`4-6`**: Standard mobile (16-20px) ← здесь
- `7-9`: Dashboard (8-12px)

---

## Компоненты

### PremiumCard
Базовая карточка с glassmorphism.

```dart
PremiumCard(
  child: Column(
    children: [
      Text('Заголовок', style: TextStyle(fontWeight: FontWeight.w800)),
      Text('Подзаголовок'),
    ],
  ),
)
```

**Фичи:**
- Inner border 1px white @ 12% alpha
- Compound shadow (soft ambient + sharp rim)
- Spring scale на tap

---

### PremiumButton
Кнопки с четырьмя вариантами.

```dart
// Primary — mesh gradient + neon glow
PremiumButton(
  label: 'Войти',
  variant: PremiumButtonVariant.primary,
  icon: Icons.login_rounded,
  onPressed: () {},
)

// Secondary — glassmorphism
PremiumButton(
  label: 'Отмена',
  variant: PremiumButtonVariant.secondary,
  onPressed: () {},
)
```

**Варианты:**
- `primary` — mesh gradient, белый текст, neon glow
- `secondary` — glassmorphism, accent цвет
- `outlined` — transparent с border
- `text` — без декорации

**Фичи:**
- Pill-shaped (999px radius) по Material 3 Expressive
- Spring scale feedback
- Loading state с spinner
- Full width опция

---

### PremiumTextField
Текстовое поле с glassmorphism и focus glow.

```dart
PremiumTextField(
  controller: _emailController,
  labelText: 'Email',
  hintText: 'example@email.com',
  prefixIcon: Icons.email_rounded,
  keyboardType: TextInputType.emailAddress,
)
```

**Фичи:**
- Pill-shaped
- Focus state с neon glow анимацией
- Animated border color transition
- Label + hint + error support
- Prefix/suffix icons

---

### PremiumChatTile
Плитка чата в списке чатов.

```dart
PremiumChatTile(
  avatarUrl: chat.avatarUrl,
  displayName: chat.name,
  lastMessage: chat.lastMessage,
  timestamp: chat.updatedAt,
  unreadCount: chat.unreadCount,
  onTap: () => _openChat(chat.id),
  onDismissed: () => _deleteChat(chat.id),
)
```

**Фичи:**
- Glassmorphism + inner border
- Unread badge с mesh gradient
- Spring scale на tap
- Swipe-to-delete с Dismissible
- Emphasized typography для unread
- Neon glow на активном чате

---

### PremiumMessageBubble
Пузырь сообщения в чате.

```dart
PremiumMessageBubble(
  text: message.text,
  isMine: message.userId == currentUserId,
  timestamp: message.createdAt,
  isRead: message.isRead,
  onLongPress: () => _showMessageMenu(message),
)
```

**Фичи:**
- Исходящие: mesh gradient + neon glow
- Входящие: glassmorphism
- Asymmetric corners с «хвостиком»
- Read status indicator
- Spring scale на interactions

---

### PremiumChatMessageTile
Полнофункциональная плитка сообщения (обёртка над `ChatMessageTile`).

```dart
PremiumChatMessageTile(
  msg: message,
  isMine: message.userId == myUserId,
  index: index, // для staggered entrance
  // ... остальные параметры из ChatMessageTile
)
```

**Фичи:**
- Staggered entrance (index * 50ms delay)
- Fade + slide transition
- Поддержка всех типов контента (текст, фото, видео, файлы)
- Forwards к существующему `ChatMessageTile`

---

### PremiumProfileCard
Карточка для профиля с hero variant.

```dart
// Hero card с mesh gradient
PremiumProfileCard(
  leading: CircleAvatar(...),
  title: 'Владимир Харин',
  subtitle: 'Premium пользователь',
  isHero: true,
)

// Обычная glass card
PremiumProfileCard(
  leading: Icon(Icons.settings),
  title: 'Настройки',
  trailing: Icon(Icons.chevron_right),
  onTap: () => _openSettings(),
)
```

**Фичи:**
- Hero variant: mesh gradient + neon glow
- Standard variant: glassmorphism
- Emphasized weight для hero title
- Spring scale feedback
- Leading/trailing widgets

---

### PremiumAppBar
AppBar с glassmorphism и backdrop blur.

```dart
PremiumAppBar(
  title: 'Чаты',
  actions: [
    PremiumAppBarAction(
      icon: Icons.search_rounded,
      onPressed: () => _openSearch(),
    ),
  ],
)
```

**Фичи:**
- Backdrop blur (sigma: 12)
- Glass + inner border по умолчанию
- Hero variant с mesh gradient
- Spring scale actions
- PreferredSizeWidget совместимость

---

### PremiumBottomNav
Bottom Navigation Bar с pill indicators.

```dart
PremiumBottomNav(
  currentIndex: _currentIndex,
  onTap: (index) => setState(() => _currentIndex = index),
  items: [
    PremiumNavItem(
      icon: Icons.chat_outlined,
      activeIcon: Icons.chat_rounded,
      label: 'Чаты',
    ),
    PremiumNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person_rounded,
      label: 'Профиль',
    ),
  ],
)
```

**Фичи:**
- Glassmorphism bar с backdrop blur
- Pill-shaped active indicator (Material 3 Expressive)
- Spring scale на buttons
- Active icon + neon glow
- SafeArea padding

---

### PremiumFab
Floating Action Button (rounded square, не круг!).

```dart
PremiumFab(
  icon: Icons.add_rounded,
  onPressed: () => _createNewChat(),
  tooltip: 'Новый чат',
)
```

**Фичи:**
- Rounded square по Material 3 Expressive (не круг!)
- Mesh gradient + neon glow
- Spring scale feedback
- 56x56 standard size

---

## Цветовая система

### Primary Colors
```dart
AppColors.primary          // #4A90E2 — основной accent
AppColors.primaryDeep      // #2E5A8A — тёмный вариант
AppColors.primaryGlow      // #5BA3FF — яркий для glow эффектов
```

### Cyber Accent
```dart
AppColors.cyberAccent      // #38BDF8 — cyan для read indicators
```

### Surface Hierarchy
```dart
scheme.surfaceContainerLowest    // Самый тёмный
scheme.surfaceContainerLow
scheme.surfaceContainer
scheme.surfaceContainerHigh
scheme.surfaceContainerHighest   // Самый светлый
```

---

## Spacing & Radius Tokens

### Spacing
```dart
AppSpacing.xxs   // 4px
AppSpacing.xs    // 8px
AppSpacing.sm    // 12px
AppSpacing.md    // 16px
AppSpacing.lg    // 20px
AppSpacing.xl    // 24px
AppSpacing.xxl   // 32px
```

### Radius
```dart
AppRadius.xs     // 6px
AppRadius.sm     // 8px
AppRadius.md     // 12px
AppRadius.lg     // 16px
AppRadius.xl     // 20px
AppRadius.xxl    // 24px
```

### Special
```dart
BorderRadius.circular(999)  // Pill shape для buttons/nav
```

---

## Motion Tokens

### Durations
```dart
AppMotion.fast    // 200ms — small components
AppMotion.medium  // 350ms — partial-screen
AppMotion.slow    // 500ms — full-screen transitions
```

### Curves
```dart
AppMotion.spring  // Curves.easeOutBack — bouncy spring
```

---

## Design Tokens

### Compound Shadow
```dart
AppDesignTokens.compoundShadow(scheme)
// Soft ambient + sharp rim light
```

### Neon Glow
```dart
AppDesignTokens.neonGlow(intensity: 0.25)
// Primary color glow, customizable intensity
```

---

## Best Practices

### ✅ DO

1. **Используй compound expressiveness в hero moments:**
   ```dart
   // Combine: mesh gradient + emphasized typography + neon glow + spring scale
   PremiumButton(
     label: 'СОЗДАТЬ',
     variant: PremiumButtonVariant.primary,
     icon: Icons.add_rounded,
     onPressed: () {},
   )
   ```

2. **Stagger entrance animations:**
   ```dart
   ListView.builder(
     itemBuilder: (context, index) => PremiumChatTile(
       // Автоматически: fade + slide с (index * 50ms) delay
     ),
   )
   ```

3. **Inner borders везде:**
   ```dart
   border: Border.all(
     color: Colors.white.withValues(alpha: 0.12),
     width: 1,
   ),
   ```

4. **Pill-shaped buttons:**
   ```dart
   borderRadius: BorderRadius.circular(999)
   ```

### ❌ DON'T

1. **Не используй tween animations:**
   ```dart
   // ❌ Bad
   AnimationController(duration: Duration(milliseconds: 300))
   
   // ✅ Good
   AnimationController(duration: AppMotion.fast)
   curve: AppMotion.spring  // Bouncy spring, not linear
   ```

2. **Не применяй glass на контент:**
   ```dart
   // ❌ Bad — glassmorphism на content layer
   PremiumCard(child: Text('Message text'))
   
   // ✅ Good — glass только на navigation/controls
   PremiumBottomNav(...)
   PremiumAppBar(...)
   ```

3. **Не используй одинаковые radii везде:**
   ```dart
   // ❌ Bad
   borderRadius: BorderRadius.circular(12) // everywhere
   
   // ✅ Good — vary radii
   buttons: 999px (pill)
   cards: 16px (AppRadius.lg)
   app bar corners: 0px (square top)
   ```

4. **Не игнорируй emphasized typography:**
   ```dart
   // ❌ Bad — flat weight
   Text(title, style: TextStyle(fontWeight: FontWeight.w500))
   
   // ✅ Good — emphasized для hero
   Text(title, style: TextStyle(fontWeight: FontWeight.w800))
   ```

---

## Migration Guide

### Шаг 1: Замени базовые компоненты

```dart
// Before
ElevatedButton(
  onPressed: () {},
  child: Text('Войти'),
)

// After
PremiumButton(
  label: 'Войти',
  variant: PremiumButtonVariant.primary,
  onPressed: () {},
)
```

### Шаг 2: Обнови layout с bento grids

```dart
// Before — uniform ListView
ListView(
  children: items.map((item) => ListTile(title: Text(item))).toList(),
)

// After — bento с разными размерами
CustomScrollView(
  slivers: [
    // Hero card spans 2 columns
    SliverToBoxAdapter(
      child: PremiumProfileCard(isHero: true, ...),
    ),
    // Standard cards в 2-column grid
    SliverGrid(
      delegate: SliverChildBuilderDelegate(...),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
    ),
  ],
)
```

### Шаг 3: Добавь staggered entrance

```dart
// Before — instant appearance
ListView.builder(
  itemBuilder: (context, index) => ChatTile(...),
)

// After — staggered fade + slide
ListView.builder(
  itemBuilder: (context, index) => PremiumChatTile(
    // Автоматически: (index * 50ms) delay
    ...
  ),
)
```

---

## Performance Notes

1. **RepaintBoundary** уже добавлены в animated widgets
2. **Spring animations** прерываемые по design
3. **Backdrop blur** — GPU-intensive, используется только где нужно
4. **Staggered entrance** — только первые 20 items, дальше instant

---

## Поддержка Accessibility

Все виджеты соблюдают:
- ✅ 4.5:1 contrast для обычного текста
- ✅ 3:1 для крупного текста
- ✅ 44×44 minimum touch targets (где применимо)
- ✅ Semantic labels
- ⚠️ Reduce Motion — TODO: fallback на simple fade

---

Created with taste. Inspired by flutter-taste-skill v2 🦋
