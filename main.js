import { Command } from 'commander';
import http from 'node:http';
import { mkdir } from 'node:fs/promises';

const program = new Command();

program
  .name('main.js')
  .description('Кешуючий проксі-сервер для зображень http.cat')
  // -h зарезервовано для host згідно з методичкою.
  .helpOption('--help', 'показати довідку')
  .requiredOption('-h, --host <address>', 'адреса сервера')
  .requiredOption('-p, --port <number>', 'порт сервера (1–65535)')
  .requiredOption('-c, --cache <path>', 'шлях до теки кешу');

program.parse();

const options = program.opts();
const port = Number(options.port);

if (!/^\d+$/.test(options.port) || !Number.isInteger(port) || port < 1 || port > 65535) {
  program.error('Порт має бути цілим числом від 1 до 65535.');
}

if (options.host.trim().length === 0) {
  program.error('Адреса сервера не може бути порожньою.');
}

if (options.cache.trim().length === 0) {
  program.error('Шлях до теки кешу не може бути порожнім.');
}

function sendText(response, statusCode, message, headers = {}) {
  response.writeHead(statusCode, {
    'Content-Type': 'text/plain; charset=utf-8',
    ...headers,
  });
  response.end(message + '\n');
}

try {
  // Створюємо також батьківські теки; наявна тека не є помилкою.
  await mkdir(options.cache, { recursive: true });
  console.log(`Тека кешу готова: ${options.cache}`);

  const server = http.createServer(async (request, response) => {
    try {
      if (!['GET', 'PUT', 'DELETE'].includes(request.method)) {
        sendText(response, 405, 'Метод не дозволено. Використовуйте GET, PUT або DELETE.', {
          Allow: 'GET, PUT, DELETE',
        });
        return;
      }

      // Перевіряємо початковий URL без нормалізації: лише /100 ... /599.
      if (!/^\/[1-5]\d{2}$/.test(request.url)) {
        sendText(response, 400, 'Некоректний шлях. Очікується /<код> від /100 до /599.');
        return;
      }

      // Реалізація кожного дозволеного методу — в окремому наступному етапі.
      sendText(response, 501, `Метод ${request.method} ще не реалізовано.`);
    } catch (error) {
      console.error(`Помилка обробки запиту: ${error.message}`);
      if (!response.headersSent && !response.destroyed) {
        sendText(response, 500, 'Внутрішня помилка сервера.');
      } else {
        // Якщо відповідь уже почалася, надіслати інший статус неможливо.
        response.destroy();
      }
    }
  });

  server.listen(port, options.host);
  console.log(`Запуск HTTP-сервера: host=${options.host}, port=${port}`);
} catch (error) {
  console.error(`Помилка підготовки сервера: ${error.message}`);
  process.exitCode = 1;
}
