# Фото 432 із рамкою

Створено вбудованим imagegen на основі фото користувача. Результат збережено як `432.jpg`, завантажено через PUT і перевірено через GET: 201, потім 200, image/jpeg, X-Image-Source: cache, SHA-256 збігається. Оригінал `cati.jpg` не змінено.

Підпис `Custom Image` — довільна назва власного зображення, а не офіційна назва HTTP-статусу.

Для повторного завантаження після очищення кешу, з кореня проєкту:

```powershell
curl.exe -i -X PUT -H "Content-Type: image/jpeg" --data-binary "@./output/custom/432.jpg" http://127.0.0.1:3000/432
```

## Точний запит до генератора

Use case: precise-object-edit. Edit target: user's attached portrait photo of a spotted kitten lying upside down on a dark shaggy blanket. Add only a classic HTTP status poster frame and caption outside the photo. Preserve the original photograph, kitten identity, pose, upside-down orientation, blanket, colors, and full uncropped image as faithfully as possible. Do not replace the kitten with another animal or redraw the scene. Expand the canvas with a solid black border around the original photo, a thin white rectangular outline immediately surrounding the photo, and a larger black area below the photo for the caption. Center exact white text '432' in large elegant serif lettering and 'Custom Image' beneath it in smaller white sans-serif lettering. This should match the black HTTP cat/rabbit status posters. Keep portrait composition. No other text, no watermark. Output a single finished framed photo.
