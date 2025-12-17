import pool from './db.js';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';

dotenv.config();

/**
 * Скрипт миграции паролей из открытого текста в bcrypt хеши
 * 
 * ВАЖНО:
 * 1. Запустите этот скрипт ОДИН РАЗ после обновления сервера
 * 2. После миграции удалите этот файл
 * 3. Убедитесь, что .env настроен правильно
 */

async function migratePasswords() {
  console.log('🚀 Начало миграции паролей...\n');

  try {
    // Получаем всех пользователей
    const users = await pool.query('SELECT id, email, password FROM users');
    
    console.log(`📊 Найдено ${users.rows.length} пользователей для проверки\n`);
    
    let migratedCount = 0;
    let alreadyHashedCount = 0;
    let errorCount = 0;

    for (const user of users.rows) {
      try {
        // Проверяем, не хеширован ли уже пароль
        // Bcrypt хеши начинаются с $2a$, $2b$ или $2y$
        if (user.password && user.password.startsWith('$2')) {
          console.log(`✅ Пользователь ${user.id} (${user.email}) уже имеет хешированный пароль`);
          alreadyHashedCount++;
          continue;
        }
        
        // Если пароль пустой или null, пропускаем
        if (!user.password || user.password.trim() === '') {
          console.log(`⚠️  Пользователь ${user.id} (${user.email}) имеет пустой пароль - пропускаем`);
          continue;
        }
        
        console.log(`🔄 Хеширование пароля для пользователя ${user.id} (${user.email})...`);
        
        // Хешируем пароль
        const hashedPassword = await bcrypt.hash(user.password, 10);
        
        // Обновляем в БД
        await pool.query(
          'UPDATE users SET password = $1 WHERE id = $2',
          [hashedPassword, user.id]
        );
        
        console.log(`✅ Пароль пользователя ${user.id} успешно перехеширован`);
        migratedCount++;
        
      } catch (error) {
        console.error(`❌ Ошибка при обработке пользователя ${user.id}:`, error.message);
        errorCount++;
      }
    }
    
    console.log('\n' + '='.repeat(50));
    console.log('📊 Результаты миграции:');
    console.log(`✅ Перехешировано: ${migratedCount}`);
    console.log(`ℹ️  Уже хешированы: ${alreadyHashedCount}`);
    console.log(`❌ Ошибок: ${errorCount}`);
    console.log('='.repeat(50));
    
    if (migratedCount > 0) {
      console.log('\n✅ Миграция завершена успешно!');
      console.log('⚠️  ВАЖНО: После проверки работы системы удалите этот файл!');
    } else {
      console.log('\nℹ️  Все пароли уже хешированы или нет пользователей для миграции');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Критическая ошибка миграции:', error);
    console.error('Stack:', error.stack);
    process.exit(1);
  }
}

// Запускаем миграцию
migratePasswords();

