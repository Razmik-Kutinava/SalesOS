# Сгруппировано: ассеты Rails, reverse proxy, качество кода и тесты

Документ описывает технологии **фронтенд-ассетов без Webpack по умолчанию**, **прокси перед приложением**, а также **статический анализ** и **автотесты** в Ruby/Rails-экосистеме. Обще, без привязки к конкретному продукту.

---

## Часть 1. Propshaft

**Propshaft** — упрощённый **asset pipeline** в Rails 7+: копирует файлы из `app/assets`, `lib/assets`, `vendor/assets` (и путей гемов) в директорию вывода с **фингерпринтом** в имени для кэширования (`application-abc123.css`).

Нет встроенной трансформации как в Sprockets (без конфигурируемого компилятора в ядре pipeline). **Сборка JS/CSS** при необходимости выносится в **jsbundling-rails** / **cssbundling-rails** или внешние инструменты.

Плюсы: предсказуемость, скорость, меньше магии. Минусы: для сложного PostCSS без доп. шагов — подключать отдельный процесс сборки.

---

## Часть 2. importmap-rails

**Import maps** — стандарт браузера для разрешения **ESM-модулей** по логическим именам без bundler: в `config/importmap.rb` pin `pin "application", preload: true` и зависимости с CDN **jspm**/**esm.sh** или vendored файлов.

Подходит для **Hotwire** (Turbo, Stimulus) без npm. Для больших SPA с tree-shaking — обычно **esbuild**/**rollup**.

**CDN риски**: доступность стороннего хоста, целостность через **SRI** (`integrity` атрибут) при поддержке.

---

## Часть 3. Thruster

**Thruster** (в контексте Rails 8) — **HTTP прокси** и оптимизатор перед Puma: сжатие (gzip/brotli), кэширование статики, X-Sendfile раздача файлов с диска, иногда HTTP/2 в зависимости от сборки.

Снижает нагрузку на Ruby-воркеры для статических ответов и улучшает TTFB для сжимаемого контента.

---

## Часть 4. Классический Nginx / Caddy

Вне Rails экосистемы **Nginx** остаётся стандартом: TLS termination, reverse proxy к Unix-socket Puma, лимиты соединений, gzip_static.

**Caddy** — автоматический TLS, простой конфиг.

Выбор между Thruster-only и Nginx — зависит от хостинга и команды.

---

## Часть 5. RuboCop

**RuboCop** — статический анализатор Ruby с политиками стиля и некоторыми проверками сложности/безопасности. **rubocop-rails** — правила специфичные для Rails. **rubocop-rails-omakase** — мнение Basecamp/37signals о стиле.

Настройка `.rubocop.yml`, автоисправление `-A` для части копов. Интеграция в CI: fail build при регрессии.

---

## Часть 6. Brakeman

**Brakeman** — статический анализ **уязвимостей** Rails-приложений: массовое присваивание, SQL injection шаблонов, опасные `eval`, XSS в шаблонах (эвристики).

Ложные срабатывания возможны; требуется человеческий triage. Запуск в CI обязателен как baseline.

---

## Часть 7. bundler-audit

Проверка **известных CVE** в установленных гемах против базы **ruby-advisory-db**. `bundle audit check --update`.

Дополняет Brakeman (код) аудитом зависимостей.

---

## Часть 8. Minitest

Стандартный фреймворк тестирования Ruby: классы `ActiveSupport::TestCase`, `test "name" do`, assertions. **Параллельный** запуск на ядрах, **fixtures** для БД.

Простой вход, низкий оверхед.

---

## Часть 9. RSpec (упоминание)

Альтернатива с BDD-синтаксисом `describe`/`it`, богатая экосистема гемов. Выбор — вкус команды.

---

## Часть 10. Capybara

DSL для **симуляции пользователя** в браузере: `visit`, `click_button`, `fill_in`, матчеры. Драйверы: **Selenium** (реальный браузер), **Cuprite** (CDP), ранее **Webkit**.

Используется в **system tests** Rails для проверки полного стека.

---

## Часть 11. Selenium WebDriver

Управление Chrome/Firefox через **WebDriver** протокол. Требует **chromedriver**/**geckodriver** совместимых версий с браузером.

В CI — headless режим, кэширование бинарников.

---

## Часть 12. FactoryBot и фикстуры

**FactoryBot** строит объекты для тестов с дефолтами и traits; **fixtures** YAML — быстрые снимки данных. Комбинируют в разных стилях команд.

---

## Часть 13. VCR и WebMock

Запись HTTP взаимодействий для детерминированных тестов без реальных API (**VCR** cassettes, **WebMock** стабы).

---

## Часть 14. SimpleCov

Покрытие кода тестами; целевые пороги в CI.

---

## Часть 15. Заключение

Современный Rails-фронт по умолчанию — **Propshaft + importmap + Hotwire**; **Thruster** усиливает продакшен без полной настройки Nginx. Качество поддерживают **RuboCop**, **Brakeman**, **bundler-audit** и пирамида тестов с **Capybara** на вершине.

---

## Приложение: source maps

Для отладки минифицированного JS в production — генерация и раздача `.map` с ограничением доступа.

---

## Приложение: Content Security Policy

Rails helper `content_security_policy` снижает XSS-риск для inline скриптов.

---

## Приложение: integrity в importmap

SRI хэши для pinned модулей.

---

## Приложение: HTTP caching

`Cache-Control`, `ETag` от Rails для динамики; статика с immutable fingerprint.

---

## Приложение: Spring (legacy)

Предыдущий preloader dev; в новых версиях заменён/снижен в пользу быстрого bootsnap.

---

## Приложение: Bootsnap

Компиляция кэша YAML/Irb и путей загрузки для ускорения старта Rails.

---

## Приложение: parallel_tests gem

Шардирование RSpec/Minitest по БД для крупных suite.

---

## Приложение: flaky tests

Повтор в CI с ограничением, quarantine метки, изоляция времени (`travel_to`).

---

## Приложение: visual regression

Percy, Chromatic — вне ядра Rails, для UI-стабильности.

## Часть 16. Dartsass / Tailwind с cssbundling

Современная связка: отдельный watcher компилирует CSS в `app/assets/builds`, Propshaft раздаёт артефакт.

## Часть 17. jsbundling с esbuild

`esbuild app/javascript/* --bundle` для npm-зависимостей при отказе от importmap-only стека.

## Часть 18. rack-mini-profiler

Профилирование запросов в development с flamegraph для поиска узких мест до продакшена.

## Часть 19. bullet gem

Детект N+1 запросов и избыточного eager loading в development.

## Часть 20. standardrb

Альтернативный пресет стиля без конфигурации — конкурирует с omakase RuboCop.

## Часть 21. spring-commands-rspec (история)

Ускорение запуска в legacy-проектах; в новых установках реже нужен из-за Bootsnap.

## Часть 22. rails test:system

Запуск только system suite отдельно от unit в CI matrix.

---

*Сгруппированный справочник: Propshaft, importmap, Thruster, Nginx, RuboCop, Brakeman, bundler-audit, Minitest, Capybara, Selenium.*
