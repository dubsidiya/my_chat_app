import pool from '../db.js';
import multer from 'multer';
import csvParser from 'csv-parser';
import ExcelJS from 'exceljs';
import iconv from 'iconv-lite';
import { Readable } from 'stream';

// Настройка multer для загрузки файлов в память
const storage = multer.memoryStorage();
export const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB максимум
  },
  fileFilter: (req, file, cb) => {
    // Разрешаем CSV, Excel и текстовые файлы
    const allowedMimes = [
      'text/csv',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'text/plain',
      'application/octet-stream' // Для некоторых браузеров
    ];
    const allowExcel = process.env.ALLOW_EXCEL_UPLOADS === 'true';
    const ext = (file.originalname || '').toLowerCase();
    const isCsv = ext.endsWith('.csv') || file.mimetype === 'text/csv';
    const isExcel = ext.endsWith('.xlsx');
    const isOldExcel = ext.endsWith('.xls');

    if ((isExcel || isOldExcel) && !allowExcel) {
      return cb(new Error('Загрузка Excel отключена на сервере. Используйте CSV.'));
    }
    if (isOldExcel) {
      return cb(new Error('Поддерживается только .xlsx. Сохраните файл в формате Excel (.xlsx).'));
    }

    if (allowedMimes.includes(file.mimetype) || isCsv || (allowExcel && isExcel)) {
      cb(null, true);
    } else {
      cb(new Error('Неподдерживаемый формат файла. Используйте CSV или Excel (.xlsx)'));
    }
  }
});

// Декодирование буфера (UTF-8 или cp1251/win1251)
const decodeBufferToText = (buffer) => {
  // Если есть BOM UTF-8
  const hasUtf8Bom = buffer.length >= 3 &&
    buffer[0] === 0xEF && buffer[1] === 0xBB && buffer[2] === 0xBF;

  if (hasUtf8Bom) {
    return buffer.toString('utf8');
  }

  const utf8 = buffer.toString('utf8');
  // Если в тексте много �, пробуем cp1251
  const replacementCount = (utf8.match(/�/g) || []).length;
  if (replacementCount > 2) {
    return iconv.decode(buffer, 'win1251');
  }

  return utf8;
};

// Определение разделителя: таб, точка с запятой или запятая
const detectDelimiter = (text) => {
  const firstLine = text.split(/\r?\n/)[0] || '';
  if (firstLine.includes('\t')) return '\t';
  if (firstLine.includes(';')) return ';';
  return ',';
};

// Парсинг CSV файла (с поддержкой cp1251 и таб/; разделителей)
const parseCSV = (buffer) => {
  return new Promise((resolve, reject) => {
    const decodedText = decodeBufferToText(buffer);
    const separator = detectDelimiter(decodedText);
    const results = [];
    const stream = Readable.from(decodedText);
    const blockedKeys = new Set(['__proto__', 'prototype', 'constructor']);
    
    stream
      .pipe(csvParser({
        separator,
        mapHeaders: ({ header }) => {
          if (!header) return header;
          const h = header.toString().trim();
          const lower = h.toLowerCase();
          if (!h) return null;
          // Защита от prototype pollution через заголовки
          if (blockedKeys.has(lower)) return null;
          // Ограничим длину ключа
          if (h.length > 120) return h.substring(0, 120);
          return h;
        }
      }))
      .on('data', (data) => results.push(data))
      .on('end', () => resolve(results))
      .on('error', (error) => reject(error));
  });
};

// Парсинг Excel файла (.xlsx) через exceljs (без уязвимостей xlsx)
const parseExcel = async (buffer) => {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);
  const worksheet = workbook.worksheets[0];
  if (!worksheet) return [];

  const blockedKeys = new Set(['__proto__', 'prototype', 'constructor']);
  const maxRows = 10000;
  const rows = [];
  worksheet.eachRow((row, rowNumber) => {
    if (rows.length >= maxRows + 1) return;
    const values = row.values || [];
    const arr = [];
    for (let i = 1; i < values.length; i++) arr.push(values[i] ?? '');
    rows.push(arr);
  });

  if (rows.length === 0) return [];

  const headersRaw = (rows[0] || []).map((h) => (h ?? '').toString().trim());
  const headers = headersRaw.map((h) => {
    const lower = (h || '').toLowerCase();
    if (!h) return null;
    if (blockedKeys.has(lower)) return null;
    return h.length > 120 ? h.substring(0, 120) : h;
  });

  const out = [];
  for (let i = 1; i < rows.length && out.length < maxRows; i++) {
    const r = rows[i] || [];
    const obj = {};
    for (let c = 0; c < headers.length; c++) {
      const key = headers[c];
      if (!key) continue;
      obj[key] = r[c];
    }
    out.push(obj);
  }
  return out;
};

// Поиск студента по описанию платежа (только среди студентов текущего преподавателя)
const findStudentByPaymentDescription = async (teacherId, description) => {
  if (!description || typeof description !== 'string') {
    return null;
  }

  const desc = description.toLowerCase().trim();
  
  // Получаем студентов, доступных текущему преподавателю
  const studentsResult = await pool.query(
    `SELECT s.id, s.name, s.parent_name, s.phone, s.email
     FROM teacher_students ts
     JOIN students s ON s.id = ts.student_id
     WHERE ts.teacher_id = $1`,
    [teacherId]
  );

  // Ищем совпадения по имени, имени родителя, телефону или email
  for (const student of studentsResult.rows) {
    const studentName = student.name?.toLowerCase() || '';
    const parentName = student.parent_name?.toLowerCase() || '';
    const phone = student.phone?.replace(/\D/g, '') || '';
    const email = student.email?.toLowerCase().trim() || '';
    const emailLocal = email.includes('@') ? email.split('@')[0] : '';
    const descClean = desc.replace(/\D/g, '');

    // Проверяем совпадение по имени студента
    if (studentName && desc.includes(studentName)) {
      return student;
    }

    // Проверяем совпадение по имени родителя
    if (parentName && desc.includes(parentName)) {
      return student;
    }

    // Проверяем совпадение по телефону (если есть в описании)
    if (phone && descClean.includes(phone) && phone.length >= 10) {
      return student;
    }

    // Проверяем совпадение по email (или "нику" = local-part)
    if (email && (desc.includes(email) || (emailLocal && desc.includes(emailLocal)))) {
      return student;
    }
  }

  return null;
};

// Извлечение суммы из строки
const extractAmount = (value) => {
  if (!value) return null;
  
  // Убираем все кроме цифр, точки и запятой
  const cleaned = String(value).replace(/[^\d.,-]/g, '');
  
  // Заменяем запятую на точку
  const normalized = cleaned.replace(',', '.');
  
  // Убираем минус в начале (если это расход)
  const amount = parseFloat(normalized.replace(/^-/, ''));
  
  return isNaN(amount) ? null : Math.abs(amount);
};

// Извлечение даты из строки
const extractDate = (value) => {
  if (!value) return null;
  
  // Пробуем разные форматы дат
  const dateFormats = [
    /(\d{2})\.(\d{2})\.(\d{4})/, // DD.MM.YYYY
    /(\d{4})-(\d{2})-(\d{2})/,   // YYYY-MM-DD
    /(\d{2})\/(\d{2})\/(\d{4})/,  // DD/MM/YYYY
  ];

  for (const format of dateFormats) {
    const match = String(value).match(format);
    if (match) {
      if (format === dateFormats[0]) {
        // DD.MM.YYYY
        return `${match[3]}-${match[2]}-${match[1]}`;
      } else if (format === dateFormats[1]) {
        // YYYY-MM-DD
        return value;
      } else if (format === dateFormats[2]) {
        // DD/MM/YYYY
        return `${match[3]}-${match[2]}-${match[1]}`;
      }
    }
  }

  return null;
};

// Обработка загруженного файла выписки
export const processBankStatement = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'Файл не загружен' });
    }

    const userId = req.user.userId;
    const file = req.file;
    let rows = [];

    // Дополнительная защита по размеру (помимо multer.limits)
    const size = file.size || file.buffer?.length || 0;
    if (size > 10 * 1024 * 1024) {
      return res.status(400).json({ message: 'Файл слишком большой (макс 10MB)' });
    }

    // Определяем формат файла и парсим
    const allowExcel = process.env.ALLOW_EXCEL_UPLOADS === 'true';
    if (file.originalname.endsWith('.csv') || file.mimetype === 'text/csv') {
      rows = await parseCSV(file.buffer);
    } else if (allowExcel && file.originalname.toLowerCase().endsWith('.xlsx')) {
      rows = await parseExcel(file.buffer);
    } else {
      return res.status(400).json({ message: 'Неподдерживаемый формат файла' });
    }

    if (!rows || rows.length === 0) {
      return res.status(400).json({ message: 'Файл пуст или не удалось распарсить' });
    }

    // Определяем колонки (автоматически определяем по заголовкам)
    const firstRow = rows[0];
    const columns = Object.keys(firstRow);
    
    // Ищем колонки с датой, суммой и описанием
    let dateColumn = null;
    let amountColumn = null;
    let descriptionColumn = null;

    // Автоматическое определение колонок
    for (const col of columns) {
      const colLower = col.toLowerCase();
      if (!dateColumn && (colLower.includes('дата') || colLower.includes('date'))) {
        dateColumn = col;
      }
      if (!amountColumn && (colLower.includes('сумма') || colLower.includes('amount') || 
                            colLower.includes('сум') || colLower.includes('сумм'))) {
        amountColumn = col;
      }
      if (!descriptionColumn && (colLower.includes('описание') || colLower.includes('description') ||
                                  colLower.includes('назначение') || colLower.includes('комментарий') ||
                                  colLower.includes('получатель') || colLower.includes('payer'))) {
        descriptionColumn = col;
      }
    }

    // Если не нашли автоматически, используем первые подходящие колонки
    if (!dateColumn && columns.length > 0) dateColumn = columns[0];
    if (!amountColumn && columns.length > 1) amountColumn = columns[1];
    if (!descriptionColumn && columns.length > 2) descriptionColumn = columns[2];

    // Обрабатываем каждую строку
    const processedPayments = [];
    const errors = [];

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      
      try {
        const dateStr = dateColumn ? extractDate(row[dateColumn]) : null;
        const amount = amountColumn ? extractAmount(row[amountColumn]) : null;
        const description = descriptionColumn ? String(row[descriptionColumn] || '') : '';

        // Пропускаем строки без суммы или с нулевой суммой
        if (!amount || amount === 0) {
          continue;
        }

        // Ищем студента по описанию платежа
        const student = await findStudentByPaymentDescription(userId, description);

        processedPayments.push({
          row: i + 1,
          date: dateStr,
          amount: amount,
          description: description,
          student: student ? {
            id: student.id,
            name: student.name
          } : null,
          raw: row
        });
      } catch (error) {
        errors.push({
          row: i + 1,
          error: 'Ошибка обработки строки'
        });
      }
    }

    // Возвращаем результаты для предпросмотра (без создания транзакций)
    res.json({
      totalRows: rows.length,
      processedPayments: processedPayments,
      errors: errors,
      columns: {
        date: dateColumn,
        amount: amountColumn,
        description: descriptionColumn
      }
    });

  } catch (error) {
    console.error('Ошибка обработки выписки:', error);
    res.status(500).json({ message: 'Ошибка обработки файла выписки' });
  }
};

// Применение платежей (создание транзакций пополнения)
export const applyPayments = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { payments } = req.body; // Массив { studentId, amount, date, description }

    if (!Array.isArray(payments) || payments.length === 0) {
      return res.status(400).json({ message: 'Не указаны платежи для применения' });
    }
    const MAX_PAYMENTS_PER_REQUEST = 200;
    if (payments.length > MAX_PAYMENTS_PER_REQUEST) {
      return res.status(400).json({ message: `Максимум ${MAX_PAYMENTS_PER_REQUEST} платежей за один запрос` });
    }

    const results = [];
    const errors = [];

    for (const payment of payments) {
      try {
        const { studentId, amount, date, description } = payment;

        if (!studentId || !amount || amount <= 0) {
          errors.push({
            payment,
            error: 'Не указан студент или сумма'
          });
          continue;
        }

        // Проверяем, что студент существует и доступен пользователю
        const studentCheck = await pool.query(
          `SELECT s.id, s.name
           FROM teacher_students ts
           JOIN students s ON s.id = ts.student_id
           WHERE ts.teacher_id = $1 AND s.id = $2
           LIMIT 1`,
          [userId, studentId]
        );

        if (studentCheck.rows.length === 0) {
          errors.push({
            payment,
            error: 'Студент не найден'
          });
          continue;
        }

        // Создаем транзакцию пополнения (из банковской выписки)
        const createdAt = date ? new Date(date) : new Date();
        const finalDescription = description || `Пополнение из банковской выписки${date ? ' от ' + date : ''}`;
        const result = await pool.query(
          `INSERT INTO transactions (student_id, amount, type, description, created_by, created_at)
           VALUES ($1, $2, 'deposit', $3, $4, $5)
           RETURNING *`,
          [studentId, amount, finalDescription, userId, createdAt]
        );

        results.push({
          transaction: result.rows[0],
          student: studentCheck.rows[0]
        });
      } catch (error) {
        errors.push({
          payment,
          error: 'Ошибка применения платежа'
        });
      }
    }

    res.json({
      success: results.length,
      failed: errors.length,
      results: results,
      errors: errors
    });

  } catch (error) {
    console.error('Ошибка применения платежей:', error);
    res.status(500).json({ message: 'Ошибка применения платежей' });
  }
};

