import pool from '../db.js';
import multer from 'multer';
import csvParser from 'csv-parser';
import xlsx from 'xlsx';
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
    
    if (allowedMimes.includes(file.mimetype) || 
        file.originalname.endsWith('.csv') || 
        file.originalname.endsWith('.xlsx') || 
        file.originalname.endsWith('.xls')) {
      cb(null, true);
    } else {
      cb(new Error('Неподдерживаемый формат файла. Используйте CSV или Excel (.xlsx, .xls)'));
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
    
    stream
      .pipe(csvParser({
        separator,
        mapHeaders: ({ header }) => header ? header.trim() : header
      }))
      .on('data', (data) => results.push(data))
      .on('end', () => resolve(results))
      .on('error', (error) => reject(error));
  });
};

// Парсинг Excel файла
const parseExcel = (buffer) => {
  const workbook = xlsx.read(buffer, { type: 'buffer' });
  const sheetName = workbook.SheetNames[0];
  const worksheet = workbook.Sheets[sheetName];
  return xlsx.utils.sheet_to_json(worksheet);
};

// Поиск студента по описанию платежа
const findStudentByPaymentDescription = async (description) => {
  if (!description || typeof description !== 'string') {
    return null;
  }

  const desc = description.toLowerCase().trim();
  
  // Получаем всех студентов
  const studentsResult = await pool.query(
    `SELECT id, name, parent_name, phone FROM students`
  );

  // Ищем совпадения по имени, имени родителя или телефону
  for (const student of studentsResult.rows) {
    const studentName = student.name?.toLowerCase() || '';
    const parentName = student.parent_name?.toLowerCase() || '';
    const phone = student.phone?.replace(/\D/g, '') || '';
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

    // Определяем формат файла и парсим
    if (file.originalname.endsWith('.csv') || file.mimetype === 'text/csv') {
      rows = await parseCSV(file.buffer);
    } else if (file.originalname.endsWith('.xlsx') || file.originalname.endsWith('.xls')) {
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
        const student = await findStudentByPaymentDescription(description);

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
          error: error.message
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
    res.status(500).json({ message: 'Ошибка обработки файла выписки', error: error.message });
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

        // Проверяем, что студент существует
        const studentCheck = await pool.query(
          'SELECT id, name FROM students WHERE id = $1',
          [studentId]
        );

        if (studentCheck.rows.length === 0) {
          errors.push({
            payment,
            error: 'Студент не найден'
          });
          continue;
        }

        // Создаем транзакцию пополнения (из банковской выписки)
        const finalDescription = description || `Пополнение из банковской выписки${date ? ' от ' + date : ''}`;
        const result = await pool.query(
          `INSERT INTO transactions (student_id, amount, type, description, created_by, created_at)
           VALUES ($1, $2, 'deposit', $3, $4, $5)
           RETURNING *`,
          [
            studentId,
            amount,
            finalDescription,
            userId,
            date ? new Date(date) : new Date()
          ]
        );

        results.push({
          transaction: result.rows[0],
          student: studentCheck.rows[0]
        });
      } catch (error) {
        errors.push({
          payment,
          error: error.message
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
    res.status(500).json({ message: 'Ошибка применения платежей', error: error.message });
  }
};

