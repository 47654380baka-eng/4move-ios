# Сборка .ipa без своего Mac

`.ipa` нельзя собрать на Windows. Можно собрать его в облаке на macOS-раннере GitHub Actions — бесплатно для публичного репозитория.

## 1. Залей проект на GitHub

1. Создай публичный репозиторий, например `4move-ios`.
2. Скопируй в репозиторий всё из `W:\AI-Assistant-iOS`:
   - `AIAssistant/`
   - `AIAssistant.xcodeproj/`
   - `.github/workflows/build-ios.yml`
   - `README.md`
3. Папку `Legacy/` можно не заливать — она не входит в сборку.

Команды из PowerShell:

```powershell
cd W:\AI-Assistant-iOS
git init
git add AIAssistant AIAssistant.xcodeproj .github README.md
git commit -m "feat: add 4MOVE code-only iOS client"
git remote add origin https://github.com/<твой-логин>/4move-ios.git
git push -u origin main
```

## 2. Запусти сборку

1. Открой репозиторий на GitHub → вкладка **Actions**.
2. Выбери **Build 4MOVE unsigned IPA** → **Run workflow**.
3. Дождись завершения (обычно 5–15 минут).
4. Скачай артефакт `4MOVE-unsigned-ipa` → распакуй → получи `4MOVE-unsigned.ipa`.

## 3. Что внутри

Workflow собирает **unsigned IPA**:

```
xcodebuild ... CODE_SIGNING_ALLOWED=NO archive
zip -qry 4MOVE-unsigned.ipa Payload
```

Подпись не нужна: AltServer подпишет IPA твоим Apple ID при установке.

## 4. Установка по кабелю

1. Подключи iPhone, разблокируй, нажми «Доверять».
2. Запусти AltServer (`C:\Program Files (x86)\AltServer\AltServer.exe`) — он уже стоит в трее.
3. В трее AltServer → **Install AltStore** → выбери устройство.
4. Введи Apple ID и пароль приложения **в окне AltServer** (не в чат, не в терминал).
5. После установки AltStore открой `.ipa` через AltStore или перетащи его в AltServer.

Бесплатный Apple ID → сертификат на 7 дней, AltStore умеет автообновлять.

## Важно

- Пароль от Apple ID никому не передавай — вводи только в GUI на своём ПК.
- Если `xcodebuild` упадёт, скинь сюда лог из Actions — исправлю проект.
- Я не могу проверить Swift-компиляцию на этом ПК: здесь нет macOS/Xcode.
