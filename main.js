import { Command } from 'commander';
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

try {
  // Створюємо також батьківські теки; наявна тека не є помилкою.
  await mkdir(options.cache, { recursive: true });
  console.log(`Тека кешу готова: ${options.cache}`);
  console.log(`Параметри сервера: host=${options.host}, port=${port}`);
  console.log('HTTP-сервер ще не реалізовано.');
} catch (error) {
  console.error(`Не вдалося створити теку кешу "${options.cache}": ${error.message}`);
  process.exitCode = 1;
}
