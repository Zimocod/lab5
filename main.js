import { Command } from 'commander';
import superagent from 'superagent';
import http from 'node:http';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

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

      const code = request.url.slice(1);
      const cacheFile = `${options.cache}/${code}.jpg`;

      if (request.method === 'GET') {
        let image;
        let source = 'cache';

        try {
          // Без кодування readFile повертає Buffer із незміненими байтами.
          image = await readFile(cacheFile);
        } catch (error) {
          // Лише відсутність файлу означає промах кешу.
          if (error.code !== 'ENOENT') {
            throw error;
          }

          try {
            const upstream = await superagent
              .get(`https://http.cat/${code}`)
              .responseType('blob')
              .timeout({ response: 5000, deadline: 15000 });

            // У Node.js responseType('blob') повертає двійковий Buffer.
            if (upstream.type !== 'image/jpeg' || !Buffer.isBuffer(upstream.body) || upstream.body.length === 0) {
              throw new Error('Джерело не повернуло JPEG-зображення.');
            }

            image = upstream.body;
          } catch (error) {
            console.error(`Помилка http.cat для коду ${code}: ${error.message}`);
            sendText(response, 404, 'Картинку не знайдено або джерело http.cat недоступне.');
            return;
          }

          // Спочатку зберігаємо картинку, потім відповідаємо клієнтові.
          // Помилки диска обробляє зовнішній catch як 500, а не як 404 джерела.
          await writeFile(cacheFile, image);
          source = 'http.cat';
        }

        response.writeHead(200, {
          'Content-Type': 'image/jpeg',
          'X-Image-Source': source,
        });
        response.end(image);
        return;
      }

      if (request.method === 'PUT') {
        const chunks = [];

        // request є потоком: очікуємо всі частини тіла без колбеків .on().
        for await (const chunk of request) {
          chunks.push(chunk);
        }

        const image = Buffer.concat(chunks);
        if (image.length === 0) {
          sendText(response, 400, 'Тіло PUT-запиту не може бути порожнім. Надішліть картинку.');
          return;
        }

        // writeFile створює новий файл або повністю замінює наявний.
        await writeFile(cacheFile, image);
        sendText(response, 201, `Картинку для коду ${code} збережено в кеші.`);
        return;
      }

      // DELETE реалізуємо на наступному етапі.
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
