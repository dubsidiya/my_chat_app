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
    'Пользователь читает историю -> reload не скроллит',
  ),
  ChatScrollScenario(
    'open_load_more_blocked',
    'До первичного открытия load-more не срабатывает при pixels=0',
  ),
  ChatScrollScenario(
    'open_load_more_allowed',
    'После первичного открытия load-more у верха списка',
  ),
  ChatScrollScenario(
    'prepend_preserve_viewport',
    'Подгрузка старых сообщений сохраняет видимую область',
  ),
  ChatScrollScenario(
    'incoming_stuck_to_bottom',
    'Входящее сообщение при stickToBottom -> скрoll',
  ),
  ChatScrollScenario(
    'incoming_reading_history',
    'Входящее сообщение при чтении истории -> без скролла',
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
  ChatScrollScenario(
    'reanchor_content_growth',
    'Рост контента у низа -> reanchor только при stickToBottom',
  ),
  ChatScrollScenario(
    'reanchor_content_growth_stuck',
    'Рост контента у низа при stickToBottom -> возврат к самому низу (widget)',
  ),
  ChatScrollScenario(
    'reanchor_content_growth_reading',
    'Рост контента у низа при чтении истории -> без рывка вниз (widget)',
  ),
];
