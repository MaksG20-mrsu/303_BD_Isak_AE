-- Лабораторная работа 6. База данных станции технического обслуживания (СТО).
-- Запуск: sqlite3 sto.db < db_init.sql
--
-- Основные решения:
--  * уволенные мастера остаются в employees (дата увольнения dismissal_date), физически не удаляются:
--    все внешние ключи на employees имеют ON DELETE RESTRICT, поэтому история работ сохраняется;
--  * цена услуги на момент выполнения копируется в work_order_items.price, поэтому изменение
--    прайс-листа не меняет прошлую выручку;
--  * зарплата = процент мастера (employees.salary_percent) x выручка за период (см. запрос в конце файла).

PRAGMA foreign_keys = OFF;

DROP VIEW    IF EXISTS v_work_order_totals;
DROP TABLE   IF EXISTS work_order_items;
DROP TABLE   IF EXISTS work_orders;
DROP TABLE   IF EXISTS appointment_services;
DROP TABLE   IF EXISTS appointments;
DROP TABLE   IF EXISTS cars;
DROP TABLE   IF EXISTS clients;
DROP TABLE   IF EXISTS work_schedules;
DROP TABLE   IF EXISTS services;
DROP TABLE   IF EXISTS employees;

PRAGMA foreign_keys = ON;

-- Работники (мастера). Уволенные имеют заполненную dismissal_date.
CREATE TABLE employees (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    last_name      TEXT NOT NULL,
    first_name     TEXT NOT NULL,
    middle_name    TEXT,
    phone          TEXT NOT NULL UNIQUE,
    email          TEXT UNIQUE CHECK (email IS NULL OR email LIKE '%_@_%'),
    specialization TEXT,
    hire_date      TEXT NOT NULL DEFAULT (date('now')) CHECK (date(hire_date) IS NOT NULL),
    dismissal_date TEXT CHECK (dismissal_date IS NULL OR
                               (date(dismissal_date) IS NOT NULL AND dismissal_date >= hire_date)),
    salary_percent REAL NOT NULL DEFAULT 30 CHECK (salary_percent > 0 AND salary_percent <= 100)
);

-- Индивидуальный график работы мастеров (смены по датам).
CREATE TABLE work_schedules (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id INTEGER NOT NULL REFERENCES employees (id) ON UPDATE CASCADE ON DELETE RESTRICT,
    work_date   TEXT NOT NULL CHECK (date(work_date) IS NOT NULL),
    start_time  TEXT NOT NULL CHECK (time(start_time) IS NOT NULL),
    end_time    TEXT NOT NULL CHECK (time(end_time) IS NOT NULL),
    CHECK (start_time < end_time),
    UNIQUE (employee_id, work_date, start_time)
);

-- Справочник услуг.
CREATE TABLE services (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL UNIQUE,
    duration_min INTEGER NOT NULL CHECK (duration_min > 0),
    price        REAL NOT NULL CHECK (price >= 0),
    is_active    INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE clients (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    last_name  TEXT NOT NULL,
    first_name TEXT NOT NULL,
    phone      TEXT NOT NULL UNIQUE,
    email      TEXT CHECK (email IS NULL OR email LIKE '%_@_%')
);

CREATE TABLE cars (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id INTEGER NOT NULL REFERENCES clients (id) ON UPDATE CASCADE ON DELETE RESTRICT,
    make      TEXT NOT NULL,
    model     TEXT NOT NULL,
    plate     TEXT NOT NULL UNIQUE,
    year      INTEGER CHECK (year IS NULL OR year BETWEEN 1900 AND 2100)
);

-- Предварительная запись к мастеру. end_time = start_time + сумма длительностей выбранных услуг.
CREATE TABLE appointments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    car_id      INTEGER NOT NULL REFERENCES cars (id)      ON UPDATE CASCADE ON DELETE RESTRICT,
    employee_id INTEGER NOT NULL REFERENCES employees (id) ON UPDATE CASCADE ON DELETE RESTRICT,
    start_time  TEXT NOT NULL CHECK (datetime(start_time) IS NOT NULL),
    end_time    TEXT NOT NULL CHECK (datetime(end_time) IS NOT NULL),
    status      TEXT NOT NULL DEFAULT 'scheduled'
                CHECK (status IN ('scheduled', 'completed', 'cancelled', 'no_show')),
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    CHECK (start_time < end_time),
    CHECK (date(start_time) = date(end_time))
);

-- Выбранные при записи услуги (связь «многие ко многим»).
CREATE TABLE appointment_services (
    appointment_id INTEGER NOT NULL REFERENCES appointments (id) ON UPDATE CASCADE ON DELETE CASCADE,
    service_id     INTEGER NOT NULL REFERENCES services (id)     ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (appointment_id, service_id)
);

-- Фактически выполненные работы (заказ-наряд); по одной записи на визит.
CREATE TABLE work_orders (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    appointment_id INTEGER NOT NULL UNIQUE REFERENCES appointments (id) ON UPDATE CASCADE ON DELETE RESTRICT,
    employee_id    INTEGER NOT NULL REFERENCES employees (id)           ON UPDATE CASCADE ON DELETE RESTRICT,
    started_at     TEXT NOT NULL CHECK (datetime(started_at) IS NOT NULL),
    finished_at    TEXT NOT NULL CHECK (datetime(finished_at) IS NOT NULL),
    comment        TEXT,
    CHECK (started_at < finished_at)
);

-- Выполненные услуги с фактической ценой.
CREATE TABLE work_order_items (
    work_order_id INTEGER NOT NULL REFERENCES work_orders (id) ON UPDATE CASCADE ON DELETE CASCADE,
    service_id    INTEGER NOT NULL REFERENCES services (id)    ON UPDATE CASCADE ON DELETE RESTRICT,
    quantity      INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    price         REAL NOT NULL CHECK (price >= 0),
    PRIMARY KEY (work_order_id, service_id)
);

-- Индексы
CREATE INDEX idx_employees_last_name   ON employees (last_name);
CREATE INDEX idx_cars_client_id        ON cars (client_id);
CREATE INDEX idx_clients_last_name     ON clients (last_name);
CREATE INDEX idx_appointments_employee ON appointments (employee_id, start_time);
CREATE INDEX idx_appointments_car      ON appointments (car_id);
CREATE INDEX idx_work_orders_employee  ON work_orders (employee_id, finished_at);
CREATE INDEX idx_work_order_items_serv ON work_order_items (service_id);
CREATE INDEX idx_appt_services_serv    ON appointment_services (service_id);

-- Запись возможна только в рабочее время мастера, на ещё не уволенного мастера и без пересечения с другими записями.
CREATE TRIGGER trg_appointments_check_insert
BEFORE INSERT ON appointments
BEGIN
    SELECT RAISE(ABORT, 'Мастер уволен на дату записи')
    WHERE EXISTS (SELECT 1 FROM employees e
                  WHERE e.id = NEW.employee_id
                    AND e.dismissal_date IS NOT NULL
                    AND date(NEW.start_time) > e.dismissal_date);
    SELECT RAISE(ABORT, 'Запись вне рабочего графика мастера')
    WHERE NOT EXISTS (SELECT 1 FROM work_schedules s
                      WHERE s.employee_id = NEW.employee_id
                        AND s.work_date = date(NEW.start_time)
                        AND time(NEW.start_time) >= s.start_time
                        AND time(NEW.end_time)   <= s.end_time);
    SELECT RAISE(ABORT, 'У мастера уже есть запись на это время')
    WHERE NEW.status <> 'cancelled'
      AND EXISTS (SELECT 1 FROM appointments a
                  WHERE a.employee_id = NEW.employee_id
                    AND a.status <> 'cancelled'
                    AND a.start_time < NEW.end_time
                    AND a.end_time   > NEW.start_time);
END;

CREATE TRIGGER trg_appointments_check_update
BEFORE UPDATE OF employee_id, start_time, end_time, status ON appointments
WHEN NEW.status <> 'cancelled'
BEGIN
    SELECT RAISE(ABORT, 'У мастера уже есть запись на это время')
    WHERE EXISTS (SELECT 1 FROM appointments a
                  WHERE a.id <> NEW.id
                    AND a.employee_id = NEW.employee_id
                    AND a.status <> 'cancelled'
                    AND a.start_time < NEW.end_time
                    AND a.end_time   > NEW.start_time);
END;

-- Сумма по каждому заказ-наряду (удобна для отчётов и расчёта зарплаты).
CREATE VIEW v_work_order_totals AS
SELECT wo.id AS work_order_id, wo.employee_id, wo.finished_at,
       SUM(i.quantity * i.price) AS total_amount
FROM work_orders wo
JOIN work_order_items i ON i.work_order_id = wo.id
GROUP BY wo.id;

BEGIN TRANSACTION;

INSERT INTO employees (id, last_name, first_name, middle_name, phone, email, specialization, hire_date, dismissal_date, salary_percent) VALUES (1, 'Петров', 'Иван', 'Сергеевич', '+7 900 100-00-01', 'petrov@sto.example', 'Двигатель, диагностика', '2021-03-01', NULL, 30);
INSERT INTO employees (id, last_name, first_name, middle_name, phone, email, specialization, hire_date, dismissal_date, salary_percent) VALUES (2, 'Сидорова', 'Ольга', 'Викторовна', '+7 900 100-00-02', 'sidorova@sto.example', 'Электрика, кондиционеры', '2022-06-15', NULL, 35);
INSERT INTO employees (id, last_name, first_name, middle_name, phone, email, specialization, hire_date, dismissal_date, salary_percent) VALUES (3, 'Козлов', 'Дмитрий', 'Андреевич', '+7 900 100-00-03', 'kozlov@sto.example', 'Ходовая часть, ГРМ', '2023-02-01', NULL, 32.5);
INSERT INTO employees (id, last_name, first_name, middle_name, phone, email, specialization, hire_date, dismissal_date, salary_percent) VALUES (4, 'Морозов', 'Алексей', 'Павлович', '+7 900 100-00-04', 'morozov@sto.example', 'Универсал', '2020-09-10', '2025-12-31', 28);
INSERT INTO employees (id, last_name, first_name, middle_name, phone, email, specialization, hire_date, dismissal_date, salary_percent) VALUES (5, 'Новикова', 'Елена', 'Игоревна', '+7 900 100-00-05', 'novikova@sto.example', 'Шиномонтаж, тормоза', '2024-04-01', NULL, 30);
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-09', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-10', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-11', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-12', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-13', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-16', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-17', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-18', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-19', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-20', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-23', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-24', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-25', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-26', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (1, '2026-11-27', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-10', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-11', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-12', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-13', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-14', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-17', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-18', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-19', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-20', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-21', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-24', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-25', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-26', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-27', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (2, '2026-11-28', '10:00', '19:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-09', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-11', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-13', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-16', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-18', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-20', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-23', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-25', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (3, '2026-11-27', '09:00', '17:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-09', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-10', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-11', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-12', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-16', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-17', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-18', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-19', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-23', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-24', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-25', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (5, '2026-11-26', '12:00', '20:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (4, '2025-11-10', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (4, '2025-11-11', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (4, '2025-11-12', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (4, '2025-11-13', '09:00', '18:00');
INSERT INTO work_schedules (employee_id, work_date, start_time, end_time) VALUES (4, '2025-11-14', '09:00', '18:00');
INSERT INTO services (id, name, duration_min, price) VALUES (1, 'Замена масла и масляного фильтра', 40, 2500);
INSERT INTO services (id, name, duration_min, price) VALUES (2, 'Диагностика ходовой части', 30, 1200);
INSERT INTO services (id, name, duration_min, price) VALUES (3, 'Замена тормозных колодок (одна ось)', 60, 3000);
INSERT INTO services (id, name, duration_min, price) VALUES (4, 'Шиномонтаж (комплект, 4 колеса)', 60, 2400);
INSERT INTO services (id, name, duration_min, price) VALUES (5, 'Балансировка колёс', 30, 1600);
INSERT INTO services (id, name, duration_min, price) VALUES (6, 'Замена свечей зажигания', 30, 1500);
INSERT INTO services (id, name, duration_min, price) VALUES (7, 'Компьютерная диагностика двигателя', 40, 1800);
INSERT INTO services (id, name, duration_min, price) VALUES (8, 'Замена ремня ГРМ', 180, 9000);
INSERT INTO services (id, name, duration_min, price) VALUES (9, 'Заправка кондиционера', 45, 2800);
INSERT INTO services (id, name, duration_min, price) VALUES (10, 'Развал-схождение', 60, 3200);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (1, 'Смирнов', 'Андрей', '+7 911 000-00-01', 'smirnov@mail.example');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (2, 'Кузнецова', 'Мария', '+7 911 000-00-02', 'kuznetsova@mail.example');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (3, 'Попов', 'Сергей', '+7 911 000-00-03', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (4, 'Васильев', 'Николай', '+7 911 000-00-04', 'vasiliev@mail.example');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (5, 'Соколова', 'Анна', '+7 911 000-00-05', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (6, 'Михайлов', 'Павел', '+7 911 000-00-06', 'mikhailov@mail.example');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (7, 'Фёдорова', 'Ирина', '+7 911 000-00-07', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (8, 'Орлов', 'Денис', '+7 911 000-00-08', 'orlov@mail.example');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (9, 'Никитина', 'Татьяна', '+7 911 000-00-09', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (10, 'Захаров', 'Игорь', '+7 911 000-00-10', 'zakharov@mail.example');
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (1, 1, 'Toyota', 'Camry', 'А123ВС77', 2018);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (2, 2, 'Volkswagen', 'Polo', 'В456ОК178', 2020);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (3, 3, 'Kia', 'Rio', 'Е789КХ50', 2019);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (4, 4, 'Hyundai', 'Solaris', 'К321МР77', 2017);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (5, 5, 'Skoda', 'Octavia', 'М654НТ99', 2021);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (6, 6, 'Lada', 'Vesta', 'Н987РО197', 2022);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (7, 7, 'Renault', 'Duster', 'О147СА77', 2016);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (8, 8, 'Ford', 'Focus', 'Р258ТУ78', 2015);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (9, 9, 'Nissan', 'Qashqai', 'С369ХМ50', 2019);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (10, 10, 'Mazda', '3', 'Т741АВ99', 2020);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (11, 1, 'Lada', 'Granta', 'У852КЕ77', 2023);
INSERT INTO cars (id, client_id, make, model, plate, year) VALUES (12, 2, 'BMW', 'X5', 'Х963НО178', 2021);
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (1, 1, 1, '2026-11-09 09:00', '2026-11-09 09:40', 'completed', '2026-11-06 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (2, 2, 1, '2026-11-09 10:00', '2026-11-09 11:30', 'completed', '2026-11-06 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (3, 3, 2, '2026-11-10 10:00', '2026-11-10 11:30', 'completed', '2026-11-07 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (4, 4, 3, '2026-11-11 09:00', '2026-11-11 12:00', 'completed', '2026-11-08 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (5, 5, 5, '2026-11-11 12:00', '2026-11-11 13:10', 'completed', '2026-11-08 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (6, 6, 1, '2026-11-12 11:00', '2026-11-12 12:00', 'completed', '2026-11-09 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (7, 7, 2, '2026-11-13 14:00', '2026-11-13 15:15', 'completed', '2026-11-10 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (8, 1, 3, '2026-11-13 09:00', '2026-11-13 10:10', 'completed', '2026-11-10 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (9, 8, 5, '2026-11-16 13:00', '2026-11-16 14:00', 'completed', '2026-11-13 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (10, 9, 1, '2026-11-17 09:00', '2026-11-17 10:10', 'cancelled', '2026-11-14 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (11, 10, 2, '2026-11-18 10:30', '2026-11-18 11:10', 'completed', '2026-11-15 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (12, 2, 5, '2026-11-18 15:00', '2026-11-18 16:30', 'completed', '2026-11-15 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (13, 11, 1, '2026-11-19 14:00', '2026-11-19 14:40', 'scheduled', '2026-11-16 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (14, 3, 2, '2026-11-20 11:00', '2026-11-20 12:30', 'scheduled', '2026-11-17 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (15, 12, 3, '2026-11-20 10:00', '2026-11-20 10:40', 'scheduled', '2026-11-17 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (16, 5, 1, '2026-11-23 09:00', '2026-11-23 12:00', 'scheduled', '2026-11-20 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (17, 6, 5, '2026-11-24 15:00', '2026-11-24 16:30', 'scheduled', '2026-11-21 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (18, 4, 2, '2026-11-21 12:00', '2026-11-21 12:45', 'scheduled', '2026-11-18 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (19, 9, 3, '2026-11-16 11:00', '2026-11-16 12:00', 'no_show', '2026-11-13 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (20, 1, 4, '2025-11-10 09:00', '2025-11-10 09:40', 'completed', '2025-11-07 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (21, 7, 4, '2025-11-11 10:00', '2025-11-11 11:30', 'completed', '2025-11-08 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (22, 8, 4, '2025-11-12 09:00', '2025-11-12 12:00', 'completed', '2025-11-09 12:00');
INSERT INTO appointments (id, car_id, employee_id, start_time, end_time, status, created_at) VALUES (23, 2, 4, '2025-11-13 13:00', '2025-11-13 14:10', 'completed', '2025-11-10 12:00');
INSERT INTO appointment_services (appointment_id, service_id) VALUES (1, 1);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (2, 3);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (2, 2);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (3, 4);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (3, 5);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (4, 8);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (5, 7);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (5, 6);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (6, 10);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (7, 9);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (7, 2);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (8, 1);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (8, 6);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (9, 3);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (10, 1);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (10, 2);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (11, 7);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (12, 5);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (12, 4);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (13, 1);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (14, 10);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (14, 5);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (15, 7);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (16, 8);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (17, 3);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (17, 6);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (18, 9);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (19, 4);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (20, 1);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (21, 3);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (21, 2);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (22, 8);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (23, 7);
INSERT INTO appointment_services (appointment_id, service_id) VALUES (23, 6);
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (1, 1, 1, '2026-11-09 09:00', '2026-11-09 09:40', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (2, 2, 1, '2026-11-09 10:00', '2026-11-09 11:30', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (3, 3, 2, '2026-11-10 10:00', '2026-11-10 11:40', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (4, 4, 3, '2026-11-11 09:00', '2026-11-11 12:00', 'Рекомендована замена фильтров при следующем ТО');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (5, 5, 5, '2026-11-11 12:00', '2026-11-11 13:10', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (6, 6, 1, '2026-11-12 11:00', '2026-11-12 12:10', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (7, 7, 2, '2026-11-13 14:00', '2026-11-13 15:15', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (8, 8, 3, '2026-11-13 09:00', '2026-11-13 10:10', 'Рекомендована замена фильтров при следующем ТО');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (9, 9, 5, '2026-11-16 13:00', '2026-11-16 14:10', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (11, 11, 2, '2026-11-18 10:30', '2026-11-18 11:10', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (12, 12, 5, '2026-11-18 15:00', '2026-11-18 16:40', 'Рекомендована замена фильтров при следующем ТО');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (20, 20, 4, '2025-11-10 09:00', '2025-11-10 09:40', 'Рекомендована замена фильтров при следующем ТО');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (21, 21, 4, '2025-11-11 10:00', '2025-11-11 11:40', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (22, 22, 4, '2025-11-12 09:00', '2025-11-12 12:00', 'Работы выполнены в полном объёме');
INSERT INTO work_orders (id, appointment_id, employee_id, started_at, finished_at, comment) VALUES (23, 23, 4, '2025-11-13 13:00', '2025-11-13 14:10', 'Работы выполнены в полном объёме');
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (1, 1, 1, 2500);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (2, 3, 1, 3000);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (2, 2, 1, 1200);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (3, 4, 1, 2400);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (3, 5, 1, 1600);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (4, 8, 1, 9000);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (5, 7, 1, 1800);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (5, 6, 1, 1500);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (6, 10, 1, 3200);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (7, 9, 1, 2800);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (7, 2, 1, 1200);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (8, 1, 1, 2500);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (8, 6, 1, 1500);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (9, 3, 1, 3000);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (11, 7, 1, 1800);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (12, 5, 1, 1600);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (12, 4, 1, 2400);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (20, 1, 1, 2200);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (21, 3, 1, 2700);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (21, 2, 1, 1100);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (22, 8, 1, 8100);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (23, 7, 1, 1600);
INSERT INTO work_order_items (work_order_id, service_id, quantity, price) VALUES (23, 6, 1, 1400);
COMMIT;

-- Примеры запросов (не выполняются при создании базы).
-- Зарплата мастеров за произвольный период (подставьте даты):
--   SELECT e.last_name || ' ' || e.first_name AS master,
--          ROUND(SUM(t.total_amount), 2) AS revenue,
--          e.salary_percent AS percent,
--          ROUND(SUM(t.total_amount) * e.salary_percent / 100, 2) AS salary
--   FROM v_work_order_totals t JOIN employees e ON e.id = t.employee_id
--   WHERE date(t.finished_at) BETWEEN '2026-11-01' AND '2026-11-30'
--   GROUP BY e.id ORDER BY master;
-- Работающие мастера:  SELECT * FROM employees WHERE dismissal_date IS NULL;
-- Уволенные мастера:   SELECT * FROM employees WHERE dismissal_date IS NOT NULL;

