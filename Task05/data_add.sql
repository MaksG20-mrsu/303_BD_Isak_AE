-- Лабораторная работа 5. Добавление новых данных.
-- Запросы не зависят от имеющихся id: все связи находятся подзапросами.
PRAGMA foreign_keys = ON;

-- 1. Пять новых пользователей (я и четыре ближайших соседа по списку группы).
--    Дата регистрации не указана: берётся значение по умолчанию date('now').
--    Я — Исак Анастасия (№8 в списке), соседи — №6, №7, №9, №10.
INSERT INTO users (first_name, last_name, email, gender, occupation_id)
VALUES ('Anastasia', 'Isak', 'anastasia.isak@example.com', 'female',
        (SELECT id FROM occupations WHERE name = 'student'));
INSERT INTO users (first_name, last_name, email, gender, occupation_id)
VALUES ('Vyacheslav', 'Ivanov', 'vyacheslav.ivanov@example.com', 'male',
        (SELECT id FROM occupations WHERE name = 'student'));
INSERT INTO users (first_name, last_name, email, gender, occupation_id)
VALUES ('Ulyana', 'Ignateva', 'ulyana.ignateva@example.com', 'female',
        (SELECT id FROM occupations WHERE name = 'student'));
INSERT INTO users (first_name, last_name, email, gender, occupation_id)
VALUES ('Marat', 'Kadryakov', 'marat.kadryakov@example.com', 'male',
        (SELECT id FROM occupations WHERE name = 'student'));
INSERT INTO users (first_name, last_name, email, gender, occupation_id)
VALUES ('Alexander', 'Kachurin', 'alexander.kachurin@example.com', 'male',
        (SELECT id FROM occupations WHERE name = 'student'));

-- 2. Три новых фильма разных жанров.
INSERT INTO movies (title, year) VALUES ('Oppenheimer', 2023);
INSERT INTO movies (title, year) VALUES ('Barbie', 2023);
INSERT INTO movies (title, year) VALUES ('Top Gun: Maverick', 2022);

-- Жанры фильмов (жанры берутся из справочника genres).
INSERT INTO movie_genres (movie_id, genre_id)
SELECT m.id, g.id FROM movies m, genres g
WHERE m.title = 'Oppenheimer' AND m.year = 2023 AND g.name IN ('Drama', 'War');
INSERT INTO movie_genres (movie_id, genre_id)
SELECT m.id, g.id FROM movies m, genres g
WHERE m.title = 'Barbie' AND m.year = 2023 AND g.name IN ('Adventure', 'Comedy', 'Fantasy');
INSERT INTO movie_genres (movie_id, genre_id)
SELECT m.id, g.id FROM movies m, genres g
WHERE m.title = 'Top Gun: Maverick' AND m.year = 2022 AND g.name IN ('Action', 'Drama');

-- 3. Три отзыва от меня на добавленные фильмы.
--    Дата отзыва по умолчанию — текущее время.
INSERT INTO ratings (user_id, movie_id, rating)
VALUES ((SELECT id FROM users WHERE email = 'anastasia.isak@example.com'),
        (SELECT id FROM movies WHERE title = 'Oppenheimer' AND year = 2023), 5.0);
INSERT INTO ratings (user_id, movie_id, rating)
VALUES ((SELECT id FROM users WHERE email = 'anastasia.isak@example.com'),
        (SELECT id FROM movies WHERE title = 'Barbie' AND year = 2023), 4.5);
INSERT INTO ratings (user_id, movie_id, rating)
VALUES ((SELECT id FROM users WHERE email = 'anastasia.isak@example.com'),
        (SELECT id FROM movies WHERE title = 'Top Gun: Maverick' AND year = 2022), 4.0);
