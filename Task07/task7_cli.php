<?php

declare(strict_types=1);

/**
 * Консольное приложение: список услуг, оказанных мастерами СТО.
 * Запуск: php task7_cli.php
 * В консоли Windows перед запуском выполните: chcp 65001
 */

require_once __DIR__ . '/repository.php';

/** Количество символов в строке (корректно для UTF-8, не требует расширения mbstring). */
function textWidth(string $text): int
{
    return (int) preg_match_all('/./su', $text);
}

function padText(string $text, int $width, bool $alignRight = false): string
{
    $padding = str_repeat(' ', max(0, $width - textWidth($text)));

    return $alignRight ? $padding . $text : $text . $padding;
}

/** @param int[] $widths */
function buildBorder(array $widths, string $left, string $middle, string $right): string
{
    $segments = array_map(static fn(int $width): string => str_repeat('─', $width + 2), $widths);

    return $left . implode($middle, $segments) . $right . PHP_EOL;
}

/**
 * @param string[] $cells
 * @param int[]    $widths
 * @param int[]    $rightAligned номера колонок, выравниваемых по правому краю
 */
function buildRow(array $cells, array $widths, array $rightAligned): string
{
    $formatted = [];
    foreach ($cells as $index => $cell) {
        $formatted[] = ' ' . padText($cell, $widths[$index], in_array($index, $rightAligned, true)) . ' ';
    }

    return '│' . implode('│', $formatted) . '│' . PHP_EOL;
}

/**
 * Рисует таблицу псевдографикой.
 *
 * @param string[]   $headers
 * @param string[][] $rows
 * @param int[]      $rightAligned
 */
function renderTable(array $headers, array $rows, array $rightAligned = []): string
{
    $widths = array_map('textWidth', $headers);
    foreach ($rows as $row) {
        foreach ($row as $index => $cell) {
            $widths[$index] = max($widths[$index], textWidth($cell));
        }
    }

    $table = buildBorder($widths, '┌', '┬', '┐');
    $table .= buildRow($headers, $widths, []);
    $table .= buildBorder($widths, '├', '┼', '┤');
    foreach ($rows as $row) {
        $table .= buildRow($row, $widths, $rightAligned);
    }
    $table .= buildBorder($widths, '└', '┴', '┘');

    return $table;
}

/**
 * Запрашивает номер мастера. Пустой ввод (Enter) означает «все мастера» (null).
 * При некорректном вводе сообщение об ошибке выводится, и запрос повторяется.
 *
 * @param array<int, array<string, mixed>> $employees
 */
function askEmployeeId(array $employees): ?int
{
    while (true) {
        echo 'Введите номер мастера или нажмите Enter для вывода всех: ';
        $line = fgets(STDIN);

        if ($line === false || trim($line) === '') {
            return null;
        }

        $employeeId = parseEmployeeId($line, $employees);
        if ($employeeId !== null) {
            return $employeeId;
        }

        echo 'Ошибка: нужно ввести номер мастера из списка выше.' . PHP_EOL;
    }
}

try {
    $pdo = createConnection();
    $employees = fetchEmployees($pdo);

    if (count($employees) === 0) {
        fwrite(STDERR, 'В базе данных нет мастеров.' . PHP_EOL);
        exit(1);
    }

    echo 'Мастера:' . PHP_EOL;
    foreach ($employees as $employee) {
        $note = $employee['dismissal_date'] === null ? '' : ' (уволен ' . $employee['dismissal_date'] . ')';
        echo '  ' . $employee['id'] . ' - ' . formatFullName($employee) . $note . PHP_EOL;
    }
    echo PHP_EOL;

    $selectedEmployeeId = askEmployeeId($employees);
    $works = fetchPerformedServices($pdo, $selectedEmployeeId);
} catch (PDOException $exception) {
    fwrite(STDERR, 'Ошибка работы с базой данных: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}

echo PHP_EOL;

if (count($works) === 0) {
    echo 'Оказанных услуг не найдено.' . PHP_EOL;
    exit(0);
}

$rows = [];
$totalCost = 0.0;
foreach ($works as $work) {
    $rows[] = [
        (string) $work['employee_id'],
        formatFullName($work),
        (string) $work['work_date'],
        (string) $work['service_name'],
        formatMoney($work['cost']),
    ];
    $totalCost += $work['cost'];
}

echo renderTable(
    ['№ мастера', 'ФИО мастера', 'Дата работы', 'Услуга', 'Стоимость, руб.'],
    $rows,
    [0, 4]
);
echo 'Всего услуг: ' . count($works) . ', общая стоимость: ' . formatMoney($totalCost) . ' руб.' . PHP_EOL;
