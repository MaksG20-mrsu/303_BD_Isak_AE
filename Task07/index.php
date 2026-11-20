<?php

declare(strict_types=1);

require_once __DIR__ . '/repository.php';

/** Экранирует строку для безопасного вывода в HTML. */
function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

$errorMessage = null;
$employees = [];
$works = [];
$selectedEmployeeId = null;

try {
    $pdo = createConnection();
    $employees = fetchEmployees($pdo);

    $rawEmployeeId = $_GET['employee_id'] ?? '';
    if (!is_string($rawEmployeeId)) {
        $rawEmployeeId = 'invalid';
    }

    $selectedEmployeeId = parseEmployeeId($rawEmployeeId, $employees);
    if (trim($rawEmployeeId) !== '' && $selectedEmployeeId === null) {
        $errorMessage = 'Мастер с таким номером не найден, показаны все услуги.';
    }

    $works = fetchPerformedServices($pdo, $selectedEmployeeId);
} catch (PDOException $exception) {
    $errorMessage = 'Ошибка работы с базой данных: ' . $exception->getMessage();
}

$totalCost = array_sum(array_column($works, 'cost'));
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Оказанные услуги СТО</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2rem auto; max-width: 960px; padding: 0 1rem; color: #222; }
        h1 { font-size: 1.5rem; }
        form { margin-bottom: 1.5rem; }
        select, button { font-size: 1rem; padding: 0.3rem 0.6rem; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #bbb; padding: 0.4rem 0.7rem; text-align: left; }
        th { background: #2f5496; color: #fff; }
        td.number, th.number { text-align: right; }
        tfoot td { font-weight: bold; background: #f0f0f0; }
        .error { color: #b00020; }
    </style>
</head>
<body>
    <h1>Услуги, оказанные мастерами СТО</h1>

    <form method="get" action="index.php">
        <label for="employee_id">Мастер:</label>
        <select name="employee_id" id="employee_id">
            <option value="">Все мастера</option>
            <?php foreach ($employees as $employee): ?>
                <option value="<?= $employee['id'] ?>"<?= $employee['id'] === $selectedEmployeeId ? ' selected' : '' ?>>
                    <?= $employee['id'] ?> - <?= e(formatFullName($employee)) ?>
                </option>
            <?php endforeach; ?>
        </select>
        <button type="submit">Показать</button>
    </form>

    <?php if ($errorMessage !== null): ?>
        <p class="error"><?= e($errorMessage) ?></p>
    <?php endif; ?>

    <?php if (count($works) === 0): ?>
        <p>Оказанных услуг не найдено.</p>
    <?php else: ?>
        <table>
            <thead>
                <tr>
                    <th class="number">№ мастера</th>
                    <th>ФИО мастера</th>
                    <th>Дата работы</th>
                    <th>Услуга</th>
                    <th class="number">Стоимость, руб.</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($works as $work): ?>
                    <tr>
                        <td class="number"><?= $work['employee_id'] ?></td>
                        <td><?= e(formatFullName($work)) ?></td>
                        <td><?= e((string) $work['work_date']) ?></td>
                        <td><?= e((string) $work['service_name']) ?></td>
                        <td class="number"><?= e(formatMoney($work['cost'])) ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
            <tfoot>
                <tr>
                    <td colspan="4">Всего услуг: <?= count($works) ?></td>
                    <td class="number"><?= e(formatMoney((float) $totalCost)) ?></td>
                </tr>
            </tfoot>
        </table>
    <?php endif; ?>
</body>
</html>
