import ExcelJS from 'exceljs';

const MONEY_FORMAT = '#,##0.00 [$₽-419];[Red]-#,##0.00 [$₽-419]';
const INT_FORMAT = '#,##0';
const DATE_FORMAT = 'dd.mm.yyyy';

const COLORS = {
  headerBg: 'FF4F46E5',
  headerText: 'FFFFFFFF',
  zebraBg: 'FFF8FAFC',
  totalsBg: 'FFFEF3C7',
  okText: 'FF15803D',
  debtText: 'FFB91C1C',
  borderLight: 'FFE5E7EB',
  borderDark: 'FF94A3B8',
  sectionBg: 'FFE0E7FF',
};

const STATUS_LABELS = {
  attended: 'Проведено',
  missed: 'Пропуск',
  makeup: 'Отработка',
  cancel_same_day: 'Отмена в день',
};

const TX_TYPE_LABELS = {
  deposit: 'Пополнение',
  refund: 'Возврат',
  lesson: 'Списание за занятие',
};

const setBorder = (cell, color = COLORS.borderLight, style = 'thin') => {
  cell.border = {
    top: { style, color: { argb: color } },
    left: { style, color: { argb: color } },
    bottom: { style, color: { argb: color } },
    right: { style, color: { argb: color } },
  };
};

const styleHeaderRow = (row) => {
  row.eachCell((cell) => {
    cell.font = { bold: true, color: { argb: COLORS.headerText }, size: 11 };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLORS.headerBg } };
    cell.alignment = { vertical: 'middle', horizontal: 'left', wrapText: true };
    setBorder(cell, COLORS.borderDark, 'thin');
  });
  row.height = 28;
};

const styleZebra = (sheet, startRow) => {
  for (let r = startRow; r <= sheet.lastRow.number; r += 1) {
    if ((r - startRow) % 2 === 1) {
      const row = sheet.getRow(r);
      row.eachCell((cell) => {
        cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLORS.zebraBg } };
      });
    }
  }
};

const styleTotalsRow = (row) => {
  row.eachCell((cell) => {
    cell.font = { bold: true };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLORS.totalsBg } };
    setBorder(cell, COLORS.borderDark, 'thin');
  });
  row.height = 22;
};

const writeSummarySheet = (sheet, payload) => {
  sheet.columns = [
    { width: 38 },
    { width: 24 },
  ];

  const period = payload.period;
  const totals = payload.totals;
  const now = new Date();

  const addTitleRow = (label) => {
    const row = sheet.addRow([label, '']);
    sheet.mergeCells(`A${row.number}:B${row.number}`);
    row.getCell(1).font = { bold: true, size: 14, color: { argb: COLORS.headerText } };
    row.getCell(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLORS.headerBg } };
    row.getCell(1).alignment = { vertical: 'middle', horizontal: 'left' };
    row.height = 26;
    return row;
  };

  const addSectionRow = (label) => {
    const row = sheet.addRow([label, '']);
    sheet.mergeCells(`A${row.number}:B${row.number}`);
    row.getCell(1).font = { bold: true, size: 12 };
    row.getCell(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLORS.sectionBg } };
    row.getCell(1).alignment = { vertical: 'middle', horizontal: 'left' };
    row.height = 22;
    return row;
  };

  const addKV = (label, value, { format } = {}) => {
    const row = sheet.addRow([label, value]);
    row.getCell(1).font = { bold: false };
    row.getCell(2).alignment = { horizontal: 'right' };
    if (format) row.getCell(2).numFmt = format;
    setBorder(row.getCell(1), COLORS.borderLight);
    setBorder(row.getCell(2), COLORS.borderLight);
    return row;
  };

  addTitleRow('Выгрузка для бухгалтерии');
  addKV('Период с', period.from);
  addKV('Период по', period.to);
  addKV('Сформировано', now.toLocaleString('ru-RU'));
  addKV(
    'Только оплата на расчётный счёт',
    payload.bankTransferOnly ? 'Да' : 'Нет'
  );

  sheet.addRow([]);
  addSectionRow('Занятия за период');
  addKV('Всего занятий', totals.lessonsCount, { format: INT_FORMAT });
  addKV('• Проведено', totals.attendedCount, { format: INT_FORMAT });
  addKV('• Пропусков', totals.missedCount, { format: INT_FORMAT });
  addKV('• Отмен в день (бесплатных)', totals.cancelSameDayFreeCount, { format: INT_FORMAT });
  addKV('• Отмен в день (платных)', totals.cancelSameDayPaidCount, { format: INT_FORMAT });
  addKV('• Отработок', totals.makeupCount, { format: INT_FORMAT });
  addKV('К отработке (открытых долгов)', totals.makeupPendingCount, { format: INT_FORMAT });

  sheet.addRow([]);
  addSectionRow('Деньги за период');
  addKV('Сумма занятий', totals.lessonsAmount, { format: MONEY_FORMAT });
  addKV('Оплачено (из депозитов)', totals.paidAmount, { format: MONEY_FORMAT });
  addKV('Долг по урокам периода', totals.unpaidAmount, { format: MONEY_FORMAT });

  sheet.addRow([]);
  addSectionRow('Депозиты и остатки');
  addKV('Внесено за период', totals.depositsAmount, { format: MONEY_FORMAT });
  addKV('Остаток предоплаты на конец', totals.prepaidAmount, { format: MONEY_FORMAT });
  addKV('Долг учеников на конец периода', totals.debtAmount, { format: MONEY_FORMAT });

  const salariesTotals = payload.salariesTotals;
  if (salariesTotals) {
    sheet.addRow([]);
    addSectionRow('Зарплаты за период');
    addKV('Доход в зарплату', salariesTotals.incomeCounted || 0, { format: MONEY_FORMAT });
    addKV('Поздние отчёты (не в доход)', salariesTotals.lateAmount || 0, { format: MONEY_FORMAT });
    addKV('Итого зарплат (50%)', salariesTotals.salary || 0, { format: MONEY_FORMAT });
  }

  sheet.views = [{ state: 'normal' }];
};

const writeTeachersSheet = (sheet, payload) => {
  sheet.columns = [
    { header: 'Преподаватель', key: 'teacher', width: 30 },
    { header: 'Учеников', key: 'students', width: 12, style: { numFmt: INT_FORMAT } },
    { header: 'Занятий', key: 'lessons', width: 12, style: { numFmt: INT_FORMAT } },
    { header: 'Сумма', key: 'amount', width: 18, style: { numFmt: MONEY_FORMAT } },
    { header: 'Оплачено', key: 'paid', width: 18, style: { numFmt: MONEY_FORMAT } },
    { header: 'Долг', key: 'unpaid', width: 18, style: { numFmt: MONEY_FORMAT } },
  ];

  styleHeaderRow(sheet.getRow(1));

  for (const t of payload.teachers) {
    const row = sheet.addRow({
      teacher: t.teacherUsername || '—',
      students: t.studentsCount,
      lessons: t.lessonsCount,
      amount: t.amount,
      paid: t.paidAmount,
      unpaid: t.unpaidAmount,
    });
    if (t.unpaidAmount > 0) {
      row.getCell('unpaid').font = { color: { argb: COLORS.debtText }, bold: true };
    } else {
      row.getCell('unpaid').font = { color: { argb: COLORS.okText } };
    }
    row.eachCell((cell) => setBorder(cell));
  }

  if (payload.teachers.length > 0) {
    const totalsRow = sheet.addRow({
      teacher: 'ИТОГО',
      students: payload.teachers.reduce((acc, t) => acc + (t.studentsCount || 0), 0),
      lessons: payload.totals.lessonsCount,
      amount: payload.totals.lessonsAmount,
      paid: payload.totals.paidAmount,
      unpaid: payload.totals.unpaidAmount,
    });
    styleTotalsRow(totalsRow);
  }

  if (sheet.lastRow.number > 1) styleZebra(sheet, 2);

  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: sheet.columnCount },
  };
};

const writeStudentsSheet = (sheet, payload) => {
  sheet.columns = [
    { header: 'Ученик', key: 'name', width: 28 },
    { header: 'Способ оплаты', key: 'payType', width: 18 },
    { header: 'Родитель', key: 'parent', width: 24 },
    { header: 'Телефон', key: 'phone', width: 18 },
    { header: 'Email', key: 'email', width: 24 },
    { header: 'Преподаватели', key: 'teachers', width: 30 },
    { header: 'Пополнено за период', key: 'deposits', width: 20, style: { numFmt: MONEY_FORMAT } },
    { header: 'Долг на конец', key: 'debt', width: 18, style: { numFmt: MONEY_FORMAT } },
    { header: 'Предоплата', key: 'prepaid', width: 18, style: { numFmt: MONEY_FORMAT } },
  ];

  styleHeaderRow(sheet.getRow(1));

  for (const s of payload.students) {
    const teachersStr = (s.teachers || [])
      .map((t) => t.teacherUsername || `#${t.teacherId}`)
      .filter(Boolean)
      .join(', ');
    const row = sheet.addRow({
      name: s.name || '—',
      payType: s.payByBankTransfer ? 'Расчётный счёт' : 'Наличные',
      parent: s.parentName || '',
      phone: s.phone || '',
      email: s.email || '',
      teachers: teachersStr,
      deposits: s.depositsInPeriod || 0,
      debt: s.debtAsOfTo || 0,
      prepaid: s.prepaidAsOfTo || 0,
    });
    if ((s.debtAsOfTo || 0) > 0) {
      row.getCell('debt').font = { color: { argb: COLORS.debtText }, bold: true };
    }
    if ((s.prepaidAsOfTo || 0) > 0) {
      row.getCell('prepaid').font = { color: { argb: COLORS.okText } };
    }
    row.eachCell((cell) => setBorder(cell));
  }

  if (payload.students.length > 0) {
    const totalsRow = sheet.addRow({
      name: 'ИТОГО',
      payType: '',
      parent: '',
      phone: '',
      email: '',
      teachers: '',
      deposits: payload.totals.depositsAmount,
      debt: payload.totals.debtAmount,
      prepaid: payload.totals.prepaidAmount,
    });
    styleTotalsRow(totalsRow);
  }

  if (sheet.lastRow.number > 1) styleZebra(sheet, 2);

  sheet.views = [{ state: 'frozen', ySplit: 1, xSplit: 1 }];
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: sheet.columnCount },
  };
};

const writeLessonsSheet = (sheet, payload) => {
  sheet.columns = [
    { header: 'Дата', key: 'date', width: 12, style: { numFmt: DATE_FORMAT } },
    { header: 'Время', key: 'time', width: 10 },
    { header: 'Длительность, мин', key: 'duration', width: 14, style: { numFmt: INT_FORMAT } },
    { header: 'Преподаватель', key: 'teacher', width: 26 },
    { header: 'Ученик', key: 'student', width: 26 },
    { header: 'Способ оплаты', key: 'payType', width: 16 },
    { header: 'Цена', key: 'price', width: 14, style: { numFmt: MONEY_FORMAT } },
    { header: 'Оплачено', key: 'paid', width: 14, style: { numFmt: MONEY_FORMAT } },
    { header: 'Долг', key: 'unpaid', width: 14, style: { numFmt: MONEY_FORMAT } },
    { header: 'Оплачен', key: 'isPaidLabel', width: 12 },
    { header: 'Статус', key: 'statusLabel', width: 18 },
    { header: 'В зарплату', key: 'chargeableLabel', width: 12 },
    { header: 'За пропуск от', key: 'originDate', width: 16, style: { numFmt: DATE_FORMAT } },
    { header: 'Заметка', key: 'notes', width: 30 },
  ];

  styleHeaderRow(sheet.getRow(1));

  for (const l of payload.lessons) {
    const dateValue = l.lessonDate ? new Date(`${l.lessonDate}T00:00:00`) : null;
    const originDateValue = l.originLessonDate ? new Date(`${l.originLessonDate}T00:00:00`) : null;
    const row = sheet.addRow({
      date: dateValue,
      time: l.lessonTime || '',
      duration: l.durationMinutes || 60,
      teacher: l.teacherUsername || '',
      student: l.studentName || '',
      payType: l.payByBankTransfer ? 'Расчётный счёт' : 'Наличные',
      price: l.price,
      paid: l.paidAmount,
      unpaid: l.unpaidAmount,
      isPaidLabel: l.isPaid ? 'Да' : 'Нет',
      statusLabel: STATUS_LABELS[l.status] || l.status,
      chargeableLabel: l.isChargeable ? 'Да' : 'Нет',
      originDate: originDateValue,
      notes: l.notes || '',
    });
    if (!l.isPaid) {
      row.getCell('unpaid').font = { color: { argb: COLORS.debtText }, bold: true };
      row.getCell('isPaidLabel').font = { color: { argb: COLORS.debtText }, bold: true };
    } else {
      row.getCell('isPaidLabel').font = { color: { argb: COLORS.okText }, bold: true };
    }
    if (l.status === 'missed' || (l.status === 'cancel_same_day' && !l.isChargeable)) {
      row.getCell('statusLabel').font = { color: { argb: COLORS.debtText }, bold: true };
    } else if (l.status === 'makeup') {
      row.getCell('statusLabel').font = { color: { argb: COLORS.okText }, bold: true };
    }
    row.eachCell((cell) => setBorder(cell));
  }

  if (payload.lessons.length > 0) {
    const totalsRow = sheet.addRow({
      date: 'ИТОГО',
      time: '',
      duration: '',
      teacher: '',
      student: '',
      payType: '',
      price: payload.totals.lessonsAmount,
      paid: payload.totals.paidAmount,
      unpaid: payload.totals.unpaidAmount,
      isPaidLabel: '',
      statusLabel: '',
      chargeableLabel: '',
      originDate: '',
      notes: '',
    });
    styleTotalsRow(totalsRow);
  }

  if (sheet.lastRow.number > 1) styleZebra(sheet, 2);

  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: sheet.columnCount },
  };
};

const writeTransactionsSheet = (sheet, transactions) => {
  sheet.columns = [
    { header: 'Дата/время', key: 'createdAt', width: 22, style: { numFmt: 'dd.mm.yyyy hh:mm' } },
    { header: 'Тип', key: 'type', width: 22 },
    { header: 'Сумма', key: 'amount', width: 16, style: { numFmt: MONEY_FORMAT } },
    { header: 'Ученик', key: 'student', width: 26 },
    { header: 'Способ оплаты', key: 'payType', width: 16 },
    { header: 'Кто создал', key: 'createdBy', width: 26 },
    { header: 'Кому (преподаватель)', key: 'targetTeacher', width: 26 },
    { header: 'Описание', key: 'description', width: 40 },
    { header: 'ID занятия', key: 'lessonId', width: 12 },
  ];

  styleHeaderRow(sheet.getRow(1));

  for (const t of transactions) {
    const createdAt = t.createdAt ? new Date(t.createdAt) : null;
    const row = sheet.addRow({
      createdAt,
      type: TX_TYPE_LABELS[t.type] || t.type || '',
      amount: t.amount,
      student: t.studentName || '',
      payType: t.payByBankTransfer ? 'Расчётный счёт' : 'Наличные',
      createdBy: t.createdByDisplayName || t.createdByEmail || (t.createdBy ? `#${t.createdBy}` : ''),
      targetTeacher: t.targetTeacherDisplayName || '',
      description: t.description || '',
      lessonId: t.lessonId || '',
    });
    if (t.type === 'lesson') {
      row.getCell('amount').font = { color: { argb: COLORS.debtText } };
    } else if (t.type === 'deposit' || t.type === 'refund') {
      row.getCell('amount').font = { color: { argb: COLORS.okText }, bold: true };
    }
    row.eachCell((cell) => setBorder(cell));
  }

  if (transactions.length > 0) {
    const depositSum = transactions
      .filter((t) => t.type === 'deposit' || t.type === 'refund')
      .reduce((acc, t) => acc + (t.amount || 0), 0);
    const lessonSum = transactions
      .filter((t) => t.type === 'lesson')
      .reduce((acc, t) => acc + (t.amount || 0), 0);
    const totalsRow = sheet.addRow({
      createdAt: 'ИТОГО',
      type: '',
      amount: '',
      student: '',
      payType: '',
      createdBy: `Пополнено: ${depositSum.toLocaleString('ru-RU', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ₽`,
      targetTeacher: `Списано за занятия: ${lessonSum.toLocaleString('ru-RU', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ₽`,
      description: '',
      lessonId: '',
    });
    styleTotalsRow(totalsRow);
  }

  if (sheet.lastRow.number > 1) styleZebra(sheet, 2);

  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: sheet.columnCount },
  };
};

const writeSalariesSheet = (sheet, payload) => {
  sheet.columns = [
    { header: 'Преподаватель', key: 'teacher', width: 30 },
    { header: 'Платных занятий', key: 'lessonsCount', width: 16, style: { numFmt: INT_FORMAT } },
    { header: 'Сумма платных', key: 'totalChargeable', width: 18, style: { numFmt: MONEY_FORMAT } },
    { header: 'Из них в поздних отчётах', key: 'lateAmount', width: 22, style: { numFmt: MONEY_FORMAT } },
    { header: 'Без отчёта (входит в доход)', key: 'noReportAmount', width: 24, style: { numFmt: MONEY_FORMAT } },
    { header: 'Доход в зарплату', key: 'incomeCounted', width: 20, style: { numFmt: MONEY_FORMAT } },
    { header: 'Зарплата 50%', key: 'salary', width: 18, style: { numFmt: MONEY_FORMAT } },
  ];

  styleHeaderRow(sheet.getRow(1));

  for (const s of payload.salaries || []) {
    const row = sheet.addRow({
      teacher: s.teacherUsername || '—',
      lessonsCount: s.chargeableLessonsCount,
      totalChargeable: s.totalChargeable,
      lateAmount: s.lateAmount,
      noReportAmount: s.noReportAmount,
      incomeCounted: s.incomeCounted,
      salary: s.salary,
    });
    row.getCell('salary').font = { bold: true, color: { argb: COLORS.okText } };
    if (s.lateAmount > 0) {
      row.getCell('lateAmount').font = { color: { argb: COLORS.debtText }, bold: true };
    }
    row.eachCell((cell) => setBorder(cell));
  }

  if ((payload.salaries || []).length > 0) {
    const t = payload.salariesTotals || {};
    const totalsRow = sheet.addRow({
      teacher: 'ИТОГО',
      lessonsCount: t.chargeableLessonsCount || 0,
      totalChargeable: t.totalChargeable || 0,
      lateAmount: t.lateAmount || 0,
      noReportAmount: t.noReportAmount || 0,
      incomeCounted: t.incomeCounted || 0,
      salary: t.salary || 0,
    });
    styleTotalsRow(totalsRow);
  } else {
    const row = sheet.addRow({
      teacher: 'Нет платных занятий в выбранном периоде',
    });
    sheet.mergeCells(`A${row.number}:G${row.number}`);
    row.getCell(1).alignment = { horizontal: 'center' };
    row.getCell(1).font = { italic: true, color: { argb: 'FF6B7280' } };
  }

  // Подсказка под таблицей, что считается зарплатой.
  sheet.addRow([]);
  const explainRow = sheet.addRow([
    'Зарплата = 50% от суммы платных занятий (без поздних отчётов). Уроки без отчёта засчитываются в доход.',
  ]);
  sheet.mergeCells(`A${explainRow.number}:G${explainRow.number}`);
  explainRow.getCell(1).alignment = { horizontal: 'left', wrapText: true };
  explainRow.getCell(1).font = { italic: true, color: { argb: 'FF374151' } };

  if (sheet.lastRow.number > 1) styleZebra(sheet, 2);

  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: sheet.columnCount },
  };
};

const writeKpiSheet = (sheet, payload) => {
  sheet.columns = [
    { header: 'Преподаватель', key: 'teacher', width: 30 },
    { header: 'Всего занятий', key: 'total', width: 14, style: { numFmt: INT_FORMAT } },
    { header: 'Состоялось', key: 'happened', width: 14, style: { numFmt: INT_FORMAT } },
    { header: '• Проведено', key: 'attended', width: 14, style: { numFmt: INT_FORMAT } },
    { header: '• Отработок', key: 'makeup', width: 14, style: { numFmt: INT_FORMAT } },
    { header: 'Пропусков', key: 'missed', width: 14, style: { numFmt: INT_FORMAT } },
    { header: 'Отмен (бесплатных)', key: 'cancelFree', width: 20, style: { numFmt: INT_FORMAT } },
    { header: 'Отмен (платных)', key: 'cancelPaid', width: 18, style: { numFmt: INT_FORMAT } },
    { header: 'К отработке', key: 'openDebt', width: 14, style: { numFmt: INT_FORMAT } },
    { header: 'КПД, %', key: 'kpi', width: 12, style: { numFmt: '0.0' } },
  ];

  styleHeaderRow(sheet.getRow(1));

  for (const s of payload.teacherStats || []) {
    const row = sheet.addRow({
      teacher: s.teacherUsername || '—',
      total: s.totalLessons,
      happened: s.happenedCount,
      attended: s.attendedCount,
      makeup: s.makeupCount,
      missed: s.missedCount,
      cancelFree: s.cancelSameDayFreeCount,
      cancelPaid: s.cancelSameDayPaidCount,
      openDebt: s.openMakeupDebtCount,
      kpi: s.kpiPercent == null ? '' : s.kpiPercent,
    });

    if (s.missedCount > 0) {
      row.getCell('missed').font = { color: { argb: COLORS.debtText }, bold: true };
    }
    if (s.openMakeupDebtCount > 0) {
      row.getCell('openDebt').font = { color: { argb: COLORS.debtText }, bold: true };
    }
    if (typeof s.kpiPercent === 'number') {
      if (s.kpiPercent >= 90) {
        row.getCell('kpi').font = { color: { argb: COLORS.okText }, bold: true };
      } else if (s.kpiPercent < 70) {
        row.getCell('kpi').font = { color: { argb: COLORS.debtText }, bold: true };
      } else {
        row.getCell('kpi').font = { bold: true };
      }
    }
    row.eachCell((cell) => setBorder(cell));
  }

  const stats = payload.teacherStats || [];
  if (stats.length > 0) {
    const sum = (key) => stats.reduce((acc, s) => acc + (s[key] || 0), 0);
    const totalAttended = sum('attendedCount');
    const totalMakeup = sum('makeupCount');
    const totalMissed = sum('missedCount');
    const totalCancelFree = sum('cancelSameDayFreeCount');
    const happened = totalAttended + totalMakeup;
    const denom = happened + totalMissed + totalCancelFree;
    const kpi = denom > 0 ? Math.round((happened / denom) * 1000) / 10 : '';
    const totalsRow = sheet.addRow({
      teacher: 'ИТОГО',
      total: sum('totalLessons'),
      happened,
      attended: totalAttended,
      makeup: totalMakeup,
      missed: totalMissed,
      cancelFree: totalCancelFree,
      cancelPaid: sum('cancelSameDayPaidCount'),
      openDebt: sum('openMakeupDebtCount'),
      kpi,
    });
    styleTotalsRow(totalsRow);
  } else {
    const row = sheet.addRow({ teacher: 'В выбранном периоде нет занятий' });
    sheet.mergeCells(`A${row.number}:J${row.number}`);
    row.getCell(1).alignment = { horizontal: 'center' };
    row.getCell(1).font = { italic: true, color: { argb: 'FF6B7280' } };
  }

  sheet.addRow([]);
  const explainRow = sheet.addRow([
    'КПД = (Проведено + Отработок) ÷ (Проведено + Отработок + Пропуски + Отмены бесплатные). Платные отмены в КПД не учитываются.',
  ]);
  sheet.mergeCells(`A${explainRow.number}:J${explainRow.number}`);
  explainRow.getCell(1).alignment = { horizontal: 'left', wrapText: true };
  explainRow.getCell(1).font = { italic: true, color: { argb: 'FF374151' } };

  if (sheet.lastRow.number > 1) styleZebra(sheet, 2);

  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: sheet.columnCount },
  };
};

/**
 * Собирает Excel-книгу по бухгалтерии за период.
 * Листы: Сводка, Зарплаты, КПД, Преподаватели, Ученики, Занятия, Транзакции.
 *
 * @param {Object} payload результат buildAccountingExport(...)
 * @param {Array} transactions результат queryAccountingTransactions(...)
 * @returns {Promise<Buffer>}
 */
export const buildAccountingWorkbookBuffer = async (payload, transactions) => {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'Reollity / Учёт занятий';
  wb.created = new Date();
  wb.modified = new Date();
  wb.properties = { date1904: false };

  writeSummarySheet(wb.addWorksheet('Сводка', { properties: { tabColor: { argb: 'FF4F46E5' } } }), payload);
  writeSalariesSheet(wb.addWorksheet('Зарплаты', { properties: { tabColor: { argb: 'FF15803D' } } }), payload);
  writeKpiSheet(wb.addWorksheet('КПД', { properties: { tabColor: { argb: 'FFEA580C' } } }), payload);
  writeTeachersSheet(wb.addWorksheet('Преподаватели', { properties: { tabColor: { argb: 'FF22C55E' } } }), payload);
  writeStudentsSheet(wb.addWorksheet('Ученики', { properties: { tabColor: { argb: 'FFF59E0B' } } }), payload);
  writeLessonsSheet(wb.addWorksheet('Занятия', { properties: { tabColor: { argb: 'FF06B6D4' } } }), payload);
  writeTransactionsSheet(
    wb.addWorksheet('Транзакции', { properties: { tabColor: { argb: 'FFB91C1C' } } }),
    transactions
  );

  return wb.xlsx.writeBuffer();
};
