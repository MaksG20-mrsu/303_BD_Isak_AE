<?php

declare(strict_types=1);

/**
 * Доступ к базе данных станции технического обслуживания.
 * Общий код для консольного (task7_cli.php) и веб-приложения (index.php).
 */

const DB_PATH = __DIR__ . '/sto.db';
const DB_INIT_SCRIPT = __DIR__ . '/db_init.sql';

/**
 * Подключается к SQLite через PDO.
 * Если файла базы ещё нет, он создаётся и заполняется скриптом db_init.sql.
 */
function createConnection(): PDO
{
    $isNewDatabase = !file_exists(DB_PATH);

    $pdo = new PDO('sqlite:' . DB_PATH, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA foreign_keys = ON');

    if ($isNewDatabase) {
        try {
            $pdo->exec((string) file_get_contents(DB_INIT_SCRIPT));
        } catch (PDOException $exception) {
            $pdo = null;
            unlink(DB_PATH);
            throw $exception;
        }
    }

    return $pdo;
}

/**
 * Возвращает всех мастеров (и работающих, и уволенных), отсортированных по фамилии.
 *
 * @return array<int, array<string, mixed>>
 */
function fetchEmployees(PDO $pdo): array
{
    $statement = $pdo->prepare(
        'SELECT id, last_name, first_name, middle_name, dismissal_date
         FROM employees
         ORDER BY last_name, first_name, id'
    );
    $statement->execute();

    $employees = [];
    foreach ($statement->fetchAll() as $row) {
        $row['id'] = (int) $row['id'];
        $employees[] = $row;
    }

    return $employees;
}

/**
 * Возвращает все оказанные услуги, отсортированные по фамилии мастера и дате выполнения.
 * Если указан $employeeId, выбираются только работы этого мастера.
 *
 * @return array<int, array<string, mixed>>
 */
function fetchPerformedServices(PDO $pdo, ?int $employeeId = null): array
{
    $sql = 'SELECT e.id AS employee_id,
                   e.last_name,
                   e.first_name,
                   e.middle_name,
                   date(wo.finished_at) AS work_date,
                   s.name AS service_name,
                   i.quantity * i.price AS cost
            FROM work_order_items i
            JOIN work_orders wo ON wo.id = i.work_order_id
            JOIN employees e    ON e.id = wo.employee_id
            JOIN services s     ON s.id = i.service_id';

    if ($employeeId !== null) {
        $sql .= ' WHERE e.id = :employee_id';
    }

    $sql .= ' ORDER BY e.last_name, e.first_name, e.id, wo.finished_at, s.name';

    $statement = $pdo->prepare($sql);
    if ($employeeId !== null) {
        $statement->bindValue(':employee_id', $employeeId, PDO::PARAM_INT);
    }
    $statement->execute();

    $works = [];
    foreach ($statement->fetchAll() as $row) {
        $row['employee_id'] = (int) $row['employee_id'];
        $row['cost'] = (float) $row['cost'];
        $works[] = $row;
    }

    return $works;
}

/**
 * Собирает ФИО из фамилии, имени и отчества (отчество может отсутствовать).
 *
 * @param array<string, mixed> $person
 */
function formatFullName(array $person): string
{
    $parts = [
        (string) $person['last_name'],
        (string) $person['first_name'],
        (string) ($person['middle_name'] ?? ''),
    ];

    return implode(' ', array_filter($parts, static fn(string $part): bool => $part !== ''));
}

/**
 * Проверяет введённый номер мастера: это должно быть целое число,
 * существующее в таблице employees. Возвращает номер или null, если ввод некорректен.
 *
 * @param array<int, array<string, mixed>> $employees
 */
function parseEmployeeId(string $input, array $employees): ?int
{
    $input = trim($input);
    if ($input === '' || !ctype_digit($input)) {
        return null;
    }

    $employeeId = (int) $input;
    foreach ($employees as $employee) {
        if ($employee['id'] === $employeeId) {
            return $employeeId;
        }
    }

    return null;
}

/** Форматирует сумму: 12 500,00 */
function formatMoney(float $amount): string
{
    return number_format($amount, 2, ',', ' ');
}
