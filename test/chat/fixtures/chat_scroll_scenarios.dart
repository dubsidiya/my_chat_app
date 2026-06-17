/// Табличные сценарии для regression-тестов поведения скролла чата
/// (модель `ListView(reverse: true)`: низ = смещение 0).
class ChatScrollScenario {
  final String id;
  final String description;

  const ChatScrollScenario(this.id, this.description);
}

const chatScrollScenarioCatalog = <ChatScrollScenario>[
  ChatScrollScenario(
    'open_at_bottom',
    'Открытие чата -> сразу у низа (новые сообщения), без скролла',
  ),
  ChatScrollScenario(
    'open_load_more_blocked',
    'До первичного открытия load-more не срабатывает',
  ),
  ChatScrollScenario(
    'load_more_near_top',
    'У верха (старые сообщения) -> догрузка истории',
  ),
  ChatScrollScenario(
    'load_more_preserves_position',
    'Догрузка истории сохраняет видимую область (reverse, без математики)',
  ),
  ChatScrollScenario(
    'incoming_at_bottom',
    'Входящее при положении у низа -> остаёмся у низа, сообщение видно',
  ),
  ChatScrollScenario(
    'incoming_reading_history',
    'Входящее при чтении истории -> не дёргает к низу',
  ),
  ChatScrollScenario(
    'media_growth_at_bottom',
    'Рост картинки у низа -> остаёмся у низа без «пружины»',
  ),
  ChatScrollScenario(
    'media_growth_top_reading',
    'Рост картинки сверху при чтении истории -> не дёргает',
  ),
  ChatScrollScenario('empty_chat_open', 'Пустой чат -> первичное открытие без скролла'),
  ChatScrollScenario(
    'loading_blocks_load_more',
    'Во время загрузки подгрузка истории заблокирована',
  ),
];
