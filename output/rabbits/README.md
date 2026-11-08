# Кролі для перевірки PUT

Зображення створено вбудованим інструментом imagegen за оригінальними картинками з кешу. PNG перетворено на JPEG засобами System.Drawing у PowerShell; код Node.js та його залежності не змінювалися.

- `200.jpg` — білий кріль біля ноутбука, підпис `200 / OK`.
- `404.jpg` — кріль ховається в пакеті, підпис `404 / Not Found`.

Обидва файли завантажено через PUT у кеш і перевірено через GET. Підписи візуально перевірено; SHA-256 вихідного JPEG, кешу та відповіді GET збігся. Команди та результати збережені в локальному `test.txt`.

Якщо кеш очищено, сервер знову завантажить оригінали з http.cat. Для повторного завантаження кролів виконайте з кореня проєкту, коли сервер працює на порту 3000:

```powershell
curl.exe -i -X PUT -H "Content-Type: image/jpeg" --data-binary "@./output/rabbits/200.jpg" http://127.0.0.1:3000/200
curl.exe -i -X PUT -H "Content-Type: image/jpeg" --data-binary "@./output/rabbits/404.jpg" http://127.0.0.1:3000/404
```

## Точні запити до генератора

### 200

Use case: precise-object-edit. Edit target: attached HTTP status poster. Replace only the white cat with a photorealistic white rabbit sitting in the same position in front of the laptop. Give the rabbit natural long ears and realistic rabbit anatomy. Preserve the laptop, setting, photographic style, black poster background, thin white rectangular frame, layout and aspect ratio. Preserve the exact existing white captions verbatim: large '200' and small 'OK' below it. Do not add or change any text. Deliver one finished image for a local web server image cache. Prefer JPEG output if supported.

### 404

Use case: precise-object-edit. Edit target: attached HTTP status poster. Replace the cat hiding inside a paper gift bag with a photorealistic rabbit hiding inside the same bag. Its furry hindquarters and natural short fluffy rabbit tail should peek out of the bag in place of the cat's long tail; it is a rabbit, not a cat. Preserve the carpet, scattered papers, gift bag, photographic style, black poster background, thin white rectangular frame, layout and aspect ratio. Preserve the exact existing white captions verbatim: large '404' and smaller 'Not Found' beneath it. Do not add or change any text. Deliver one finished image for a local web server image cache. Prefer JPEG output if supported.
