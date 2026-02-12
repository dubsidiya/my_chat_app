import nodemailer from 'nodemailer';

let transporter = null;

function getTransporter() {
  if (transporter) return transporter;
  const host = process.env.SMTP_HOST;
  const port = parseInt(process.env.SMTP_PORT || '587', 10);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  const secure = process.env.SMTP_SECURE === 'true';
  if (!host || !user || !pass) {
    throw new Error('SMTP не настроен. Установите SMTP_HOST, SMTP_USER, SMTP_PASS в .env');
  }
  transporter = nodemailer.createTransport({
    host,
    port,
    secure,
    auth: { user, pass },
  });
  return transporter;
}

/**
 * Отправить код сброса пароля на email
 * @param {string} to - email получателя
 * @param {string} code - код сброса (plain text)
 * @returns {Promise<void>}
 */
export async function sendPasswordResetEmail(to, code) {
  const from = process.env.MAIL_FROM || process.env.SMTP_USER;
  if (!from) throw new Error('Укажите MAIL_FROM или SMTP_USER');
  const transport = getTransporter();
  await transport.sendMail({
    from: `"Reol Chat" <${from}>`,
    to,
    subject: 'Код сброса пароля',
    text: `Ваш код для сброса пароля: ${code}\n\nКод действителен 15 минут.\n\nЕсли вы не запрашивали сброс пароля, проигнорируйте это письмо.`,
    html: `
      <p>Ваш код для сброса пароля:</p>
      <p style="font-size:24px;font-family:monospace;background:#f0f0f0;padding:12px;border-radius:8px;">${code}</p>
      <p>Код действителен 15 минут.</p>
      <p style="color:#666;">Если вы не запрашивали сброс пароля, проигнорируйте это письмо.</p>
    `,
  });
}
