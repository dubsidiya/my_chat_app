import validator from 'validator';

// Валидация логина
export const validateUsername = (username) => {
  if (!username || typeof username !== 'string') {
    return { valid: false, message: 'Логин обязателен' };
  }
  
  // Нормализуем логин (убираем пробелы, приводим к нижнему регистру)
  const normalizedUsername = username.trim().toLowerCase();
  
  if (!normalizedUsername) {
    return { valid: false, message: 'Логин обязателен' };
  }
  
  // Проверка минимальной длины
  if (normalizedUsername.length < 4) {
    return { valid: false, message: 'Логин должен содержать минимум 4 символа' };
  }
  
  // Проверка максимальной длины
  if (normalizedUsername.length > 50) {
    return { valid: false, message: 'Логин слишком длинный (максимум 50 символов)' };
  }
  
  // Проверка формата: только буквы, цифры, подчеркивания и дефисы
  const usernameRegex = /^[a-z0-9_-]+$/;
  if (!usernameRegex.test(normalizedUsername)) {
    return { valid: false, message: 'Логин может содержать только буквы, цифры, подчеркивания и дефисы' };
  }
  
  return { valid: true };
};

// Валидация пароля
export const validatePassword = (password) => {
  if (!password || typeof password !== 'string') {
    return { valid: false, message: 'Пароль обязателен' };
  }
  
  if (password.length < 6) {
    return { valid: false, message: 'Пароль должен содержать минимум 6 символов' };
  }
  
  if (password.length > 128) {
    return { valid: false, message: 'Пароль слишком длинный (максимум 128 символов)' };
  }
  
  return { valid: true };
};

// Валидация данных регистрации
export const validateRegisterData = (username, password) => {
  const usernameValidation = validateUsername(username);
  if (!usernameValidation.valid) {
    return usernameValidation;
  }
  
  const passwordValidation = validatePassword(password);
  if (!passwordValidation.valid) {
    return passwordValidation;
  }
  
  return { valid: true };
};

// Валидация данных входа
export const validateLoginData = (username, password) => {
  if (!username || !password) {
    return { valid: false, message: 'Логин и пароль обязательны' };
  }
  
  return { valid: true };
};

