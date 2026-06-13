/// Табличные сценарии для regression-тестов поведения скролла чата.
class ChatScrollScenario {
  final String id;
  final String description;

  const ChatScrollScenario(this.id, this.description);
}

const chatScrollScenarioCatalog = <ChatScrollScenario>[
  ChatScrollScenario('open_first_time', 'Первое открытие чата -> автоскролл вниз'),
  ChatScrollScenario(
    'open_while_reading_history',
    'Пользователь далеко от низа -> reload не скроллит',
  ),
  ChatScrollScenario(
    'open_load_more_blocked',
    'До первичного скролла load-more не срабатывает при pixels=0',
  ),
  ChatScrollScenario(
    'open_load_more_allowed',
    'После первичного скролла load-more у верха списка',
  ),
  ChatScrollScenario(
    'prepend_preserve_viewport',
    'Подгрузка старых сообщений сохраняет видимую область',
  ),
  ChatScrollScenario(
    'incoming_near_bottom',
    'Входящее сообщение при нахождении у низа -> скролл',
  ),
  ChatScrollScenario(
    'incoming_far_from_bottom',
    'Входящее сообщение при чтении истории -> без скролла',
  ),
  ChatScrollScenario(
    'settle_stop_on_stable_extent',
    'Первичный скролл останавливается при стабильном maxScrollExtent',
  ),
  ChatScrollScenario(
    'settle_stop_on_max_attempts',
    'Первичный скролл останавливается по лимиту попыток',
  ),
  ChatScrollScenario('empty_chat_open', 'Пустой чат сразу завершает первичное открытие'),
  ChatScrollScenario(
    'loading_blocks_load_more',
    'Во время _isLoading подгрузка истории заблокирована',
  ),
  ChatScrollScenario(
    'refresh_near_bottom',
    'Pull-to-refresh у низа -> автоскролл после reload',
  ),
  ChatScrollScenario(
    'refresh_reading_history',
    'Pull-to-refresh в середине истории -> без автоскролла',
  ),
];
