# ДЗ-1: ETL-пайплайн сбора исторических метеоданных

Пайплайн разово и идемпотентно извлекает почасовые метеорологические наблюдения из публичного REST API Open-Meteo, очищает и обогащает их в Python и загружает в реляционную БД PostgreSQL 15, развёрнутую в Docker.

---

## 1. Описание источника данных

- **Название и тип:** Open-Meteo Historical Weather API (публичный REST API, формат ответа — JSON).
- **Endpoint:** `https://archive-api.open-meteo.com/v1/archive`
- **Параметры запроса:** `latitude`, `longitude`, `start_date`, `end_date`, `hourly=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m`, `timezone=UTC`.
- **Объём данных:** 43 800 почасовых наблюдений для 5 городов (Bergen, Budapest, Moscow, Vienna, Zurich) за период с `2025-01-01` по `2025-12-31` (365 дней × 24 часа × 5 городов).
- **Обоснование выбора:** API не требует авторизации и секретных ключей (воспроизводимость запуска из коробки), поддерживает батчевое извлечение по временным окнам и координатам, а также возвращает вложенные массивы временных рядов, требующие нормализации и приведения типов на этапе Transform.

---

## 2. Схема данных источника

API возвращает JSON-объект, в котором метаданные координат находятся на верхнем уровне, а массивы почасовых измерений — внутри ключа `hourly`:

| Поле JSON | Тип в API | Описание |
| :--- | :--- | :--- |
| `latitude` | `float` | Широта точки наблюдения (WGS84) |
| `longitude` | `float` | Долгота точки наблюдения (WGS84) |
| `hourly.time` | `array[string]` | Метка времени в формате ISO-8601 (`YYYY-MM-DDTHH:MM`, UTC) |
| `hourly.temperature_2m` | `array[float]` | Температура воздуха на высоте 2 м (°C) |
| `hourly.relative_humidity_2m` | `array[float]` | Относительная влажность воздуха (%) |
| `hourly.precipitation` | `array[float]` | Количество осадков за час (мм) |
| `hourly.wind_speed_10m` | `array[float]` | Скорость ветра на высоте 10 м (км/ч) |

**Пример фрагмента ответа API:**
```json
{
  "latitude": 60.39,
  "longitude": 5.32,
  "timezone": "GMT",
  "hourly": {
    "time": ["2025-01-01T00:00", "2025-01-01T01:00"],
    "temperature_2m": [-1.6, -1.8],
    "relative_humidity_2m": [85.0, 86.0],
    "precipitation": [0.1, 0.0],
    "wind_speed_10m": [9.1, 8.7]
  }
}
```

---

## 3. Схема целевой таблицы (`raw_weather.hourly_observations`)

DDL-скрипт находится в `init/init.sql` и автоматически выполняется при первом запуске контейнера PostgreSQL.

| Колонка | Тип PostgreSQL | Ограничения | Описание |
| :--- | :--- | :--- | :--- |
| `city` | `VARCHAR(64)` | `PRIMARY KEY (1)`, `NOT NULL` | Название города |
| `latitude` | `NUMERIC(8, 4)` | `NOT NULL` | Широта |
| `longitude` | `NUMERIC(8, 4)` | `NOT NULL` | Долгота |
| `measured_at` | `TIMESTAMP` | `PRIMARY KEY (2)`, `NOT NULL` | Время измерения (UTC) |
| `temperature_c` | `NUMERIC(5, 2)` | `NULL` | Температура воздуха (°C) |
| `humidity_pct` | `NUMERIC(5, 2)` | `NULL` | Относительная влажность (%) |
| `precipitation_mm` | `NUMERIC(6, 2)` | `NULL` | Осадки (мм) |
| `wind_speed_kmh` | `NUMERIC(6, 2)` | `NULL` | Скорость ветра (км/ч) |
| `heat_index_c` | `NUMERIC(5, 2)` | `NULL` | Расчётный индекс теплового комфорта (°C) |
| `loaded_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | Время загрузки/обновления записи в БД |

---

## 4. Архитектура пайплайна

```mermaid
flowchart LR
    A[Open-Meteo REST API\nJSON / Hourly Arrays] -->|Extract\nrequests + pagination chunks| B[Python ETL\npandas DataFrame]
    B -->|Transform\nClean NaN, Cast Types,\nCalc Heat Index| C[Validated Batch\n43 800 rows]
    C -->|Load\npsycopg2 execute_values\nON CONFLICT DO UPDATE| D[(PostgreSQL 15\nraw_weather.hourly_observations)]
```

---

## 5. Инструкция по запуску

### Шаг 1. Клонирование репозитория и настройка переменных окружения
```bash
git clone [https://github.com/krasnovdanial/Open_Meteo_Data_ETL](https://github.com/krasnovdanial/Open_Meteo_Data_ETL)
cd Open_Meteo_Data_ETL
cp .env.example .env
```

### Шаг 2. Поднятие PostgreSQL в Docker
```bash
docker compose up -d
docker compose ps
```

### Шаг 3. Установка Python-зависимостей
Через `uv`:
```bash
uv sync
source .venv/bin/activate
```
Или через стандартный `venv` + `pip`:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Шаг 4. Запуск ETL-ноутбука
Откройте `notebooks/etl.ipynb` в Jupyter / PyCharm, выберите интерпретатор `.venv` и выполните все ячейки сверху вниз.

### Шаг 5. Проверка данных в БД
```bash
docker exec -it hw1_postgres psql -U etl_user -d weather_dw -c "SELECT COUNT(*) FROM raw_weather.hourly_observations;"
```

---

## 6. Результат выполнения последней ячейки ноутбука

После выполнения ноутбука в таблицу загружается **43 800** записей (почасовые наблюдения за 365 дней для 5 городов). Сводка по городам и первые 5 строк таблицы приведены ниже:

```text
Всего строк в таблице raw_weather.hourly_observations: 43800

Сводка по городам:
       city  rows_cnt  avg_temp_c  avg_comfort_c
0    Bergen      8760        7.88           4.73
1  Budapest      8760       12.50          10.27
2    Moscow      8760        8.16           5.21
3    Vienna      8760       11.53           8.86
4    Zurich      8760       10.40           8.88

Первые 5 записей в БД:
       city measured_at  temperature_c  humidity_pct  precipitation_mm  wind_speed_kmh  heat_index_c
0    Bergen  2025-01-01          -1.60         85.00              0.10            9.10         -5.85
1  Budapest  2025-01-01          -1.80         96.00              0.00            4.00         -4.88
2    Moscow  2025-01-01          -3.50         85.00              0.00           13.50         -8.80
3    Vienna  2025-01-01          -4.20         94.00              0.00            7.20         -8.21
4    Zurich  2025-01-01          -1.90         99.00              0.00            2.60         -4.67
```

---

## 7. Что можно улучшить

1. **Оркестрация и расписание:** Перенести логику из ноутбука в модульный Python-пакет и запускать по расписанию через Apache Airflow с инкрементальной загрузкой за вчерашний день.
2. **Валидация контрактов данных:** Подключить Pydantic перед загрузкой в БД для проверки физических границ показателей.
3. **Слой витрин:** Добавить SQL-представления или dbt-модели для расчёта среднесуточных аномалий и ветро-холодового индекса.
