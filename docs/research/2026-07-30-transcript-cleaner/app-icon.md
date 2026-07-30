---
generated: {"by": "claude-code/opus-5","at": "2026-07-30T17:29:02+03:00"}
type: "Analysis"
title: "Иконки «Русификатора»"
description: "Выбор образа, геометрия app icon и значка строки меню, требования Apple и путь до сборки"
tags: ["app-icon","menu-bar-glyph","macos-utility","icon-design"]
---
# Иконки «Русификатора»

## Текущий вывод

Взято направление **«Ровный абзац»**: разорванные строки текста сверху оседают в
целые снизу. App icon — зелёная плита с абзацем из пяти строк, значок строки
меню — та же мысль в трёх полосах с разрывом в верхней. Запасное направление —
**«Знак корректора»**, типографский знак «закрыть пробел» на светлой плите.

Готовые файлы лежат в [artifacts/icons/](artifacts/icons/):

| Файл | Что это |
|---|---|
| `app-icon-paragraph.svg` | app icon основного направления, 1024 |
| `menubar-paragraph.svg` | значок строки меню основного направления, 18 |
| `app-icon-closeup-mark.svg` | app icon запасного направления |
| `menubar-closeup-mark.svg` | значок строки меню запасного направления |
| `*-1024.png`, `*-18.png`, `*-36.png` | растры из тех же исходников |
| `preview.html` | лист проверки: маска, уменьшение, светлая и тёмная строка меню |

Иконки нарисованы в векторе по числам из раздела «Геометрия», а не сгенерированы.
Промпты для `gpt-image-2` сохранены в конце — они нужны, только если понадобится
поискать образ за пределами уже выбранного.

## Что требует Apple сейчас

Проверено 30 июля 2026 года.

**App icon.** Холст `1024 × 1024`, фон до краёв, слои квадратные: «provide square
layers so the system can apply rounded corners». Скругление накладывает система,
рисовать его нельзя. Содержимое держат по центру, иначе маска обрежет края.

Изменилось главное: macOS собирает иконку из слоёв через `Icon Composer`, а
свет оставляет себе. Apple прямо просит не встраивать эффекты — «there's no need
to include specular highlights, drop shadows between layers, beveled edges,
blurs, glows». Система сама добавляет свойства Liquid Glass: блики, преломление,
полупрозрачность. Поэтому исходник должен быть плоским и неосвещённым; любой
нарисованный объём столкнётся с системным светом.

Фон в `Icon Composer` задаётся сплошным цветом или градиентом, отдельная
картинка подложки не нужна.

**Строка меню.** Высота строки — 24 pt. Значок использует только чёрный и
прозрачность: «interface icons and symbols use black and clear colors to define
their shapes», дальше система красит форму под светлый или тёмный фон и под
выделение.

Приложение работает с `LSUIElement = true` (см. [техническое
решение](technical-design.md)), то есть постоянной иконки в Dock нет. App icon
всё равно нужен: Finder, «Системные настройки», элементы входа.

## Четыре направления

Микрофон, флаг, языковые символы, метафора перевода и штампы вроде искр,
палочки, мозга и нейросетевой сетки отброшены заранее: приложение не пишет звук,
не распознаёт речь и не привязано к языку. Осталось четыре образа.

**A. «Ровный абзац».** Один абзац, прочитанный сверху вниз: первые строки рваные
и с провалами, нижние целые и выровненные. Не «до и после» рядом, а одно
вещество, которое успокаивается. Слабое место — стопка полос затаскана: заметки,
списки, любой «текст». В маленьком размере три равные полосы читаются как
гамбургер, поэтому в глифе строки они намеренно разной длины и верхняя разорвана.

**B. «Развязанная строка».** Один непрерывный штрих: слева тугой клубок, справа
прямая линия. Сильнее всех передаёт переход от сбивчивого к ясному и меньше
всего похоже на соседей. Отпало из-за строки меню: три витка при толщине 2
единицы на 18 px схлопываются в кляксу, зазоры уходят ниже допустимого. Плюс
«каракуля превращается в линию» — уже ходовой знак у редакторов текста с ИИ.

**C. «Знак корректора».** Типографский знак «закрыть пробел»: две встречные дуги
стягивают место, откуда изъят текст. Почти не занят в софте, точно описывает
редакторскую правку. Риск в том, что знак малоизвестен: без объяснения он
читается как «сжать» или «свернуть», и есть пересечение с иконками свёртки кода.

**D. «Монограмма Р».** Буква как знак приложения: стойка и овал, у ножки уходит
вправо текстовая строка. Лучше всех выживает в строке меню. Отпало по трём
причинам: имя «Русификатор» рабочее и привязывать к нему опознавательный знак
рано; кириллическая буква подсказывает привязку к русскому языку, которой у
продукта нет; знак ничего не сообщает о деле.

## Сравнение

| | A. Ровный абзац | B. Развязанная строка | C. Знак корректора | D. Монограмма Р |
|---|---|---|---|---|
| Узнаваемость | средняя | высокая | средняя | высокая |
| Отличимость от других | слабая | высокая | высокая | высокая |
| Точность метафоры | высокая | высокая | очень высокая | низкая |
| Соответствие macOS | высокая | средняя | высокая | высокая |
| Работа при 16–18 px | высокая | низкая | средняя | очень высокая |

`B` выбывает по единственному, но решающему пункту: строка меню — главная
поверхность приложения, а там оно не живёт. `D` технически безупречно и
содержательно пусто.

`A` выбрано основным: совпадает с продуктом без натяжки, спокойное, системное,
держит связь двух иконок принципом, а не копированием. Его единственная слабость
снята адресно — глиф строки меню собран из полос разной длины с разрывом в
верхней.

`C` оставлено запасным как хедж ровно против слабого места основного: если
абзац в размере Dock окажется «просто заметками», у знака корректора есть
собственная форма и светлая плита, которая сразу отличает его от `A`.

## Геометрия

### A. Ровный абзац

**App icon, 1024 × 1024.** Плита во всё поле, вертикальный градиент `#2E7A61` →
`#1E5946`. Блок строк шириной 600 (x от 212 до 812), высота 472, оптический
центр со сдвигом 20 вверх. Полоса высотой 56, шаг 104, радиус углов 16, цвет
`#F3F0E8`. Ничего ближе 160 к краю.

| Строка | y | Форма | Конец меры | Непрозрачность |
|---|---|---|---|---|
| 1 | 256 | три сегмента, разрывы 44, дребезг ±6 | 75 % | 0.40 |
| 2 | 360 | два сегмента, разрыв 44, дребезг −3 | 88 % | 0.55 |
| 3 | 464 | целая | 70 % | 0.75 |
| 4 | 568 | целая | 100 % | 1.0 |
| 5 | 672 | целая, последняя строка абзаца | 60 % | 1.0 |

Переход держится на прозрачности, а не на втором цвете: правило одного акцента
из [визуальной системы](DESIGN.md) сохраняется.

**Значок строки меню, сетка 18 × 18.** Полосы высотой 2, шаг 5, левый край общий
на x = 2, поля 2 по бокам и 3 сверху и снизу.

- строка 1 (y = 3): сегменты x 2–8 и x 10–13.5, разрыв 2, правый край не дотягивает;
- строка 2 (y = 8): целая, x 2–16, полная мера;
- строка 3 (y = 13): целая, x 2–11, последняя строка абзаца.

Первая версия глифа была из двух полос. На проверке при 16 и 18 px она читалась
как «≂»: мало массы, две полосы выглядели несвязанными. Три полосы разной длины
дают силуэт абзаца и при этом не сходятся в гамбургер.

### C. Знак корректора

**App icon, 1024 × 1024.** Плита `#F6F3EC` → `#E9E5DA`. Три полосы высотой 52,
ширина блока 600 от x = 212. Верхняя (y = 300) на полную меру, средняя (y = 486)
разорвана пробелом 96 по центру, нижняя (y = 672) на 65 % меры. Полосы `#1D211F`
при 0.8.

Дуги: толщина 32, скруглённые концы, цвет `#28715A`, по 140 в ширину, брюшком к
пробелу — верхняя прогибается вниз, нижняя вверх. Пути `M442 409 Q512 449 582
409` и `M442 615 Q512 575 582 615`. Направление здесь несущее: при обратном
изгибе знак читается как «раздвинуть», а не «стянуть».

Между полосами оставлено по 134 вместо тесного шага абзаца — иначе дуги некуда
поставить. Плата за это в том, что три строки читаются как три линейки, а не как
текст.

**Значок строки меню, сетка 18 × 18.** Полоса высотой 2, x 2–16, с пробелом 2.5
по центру. Дуги толщиной 2 и шириной 6, отступ 2 от полосы, пути `M6 3 Q9 6.5 12
3` и `M6 15 Q9 11.5 12 15`.

## Что показала проверка

Обе пары отрисованы и просмотрены при 256, 128, 64, 32 и 16, под маской и без
цвета, а глифы — при 16 и 18 в светлой и тёмной строке меню.

- `A` держит уменьшение уверенно: до 32 читается абзац, на 16 остаётся плотный
  зелёный знак с текстовой фактурой.
- `C` на 32 и 16 теряет дуги и превращается в три серые линии на бежевом. Это
  реальная слабость: в Finder при мелком размере знак почти не опознаётся.
- Глиф `A` в строке меню читается на обоих фонах и не путается с гамбургером.
- Глиф `C` читается, но ближе к элементу управления «свернуть», чем к знаку
  приложения.

Проверка визуальная, на рендерах. На настоящей строке меню macOS и в настоящем
Finder иконки пока не смотрели.

## Как довести до сборки

1. `SVG` — источник. Все правки вносить в него, растры перегенерировать.
2. App icon: собрать в `Icon Composer` двумя слоями — фон сплошным градиентом,
   абзац передним слоем. Свет, скругление и варианты для тёмной и монохромной
   темы оставить системе.
3. Значок строки меню: `SVG` или PDF как `template image`, имя ресурса с
   суффиксом `Template`, либо `isTemplate = true` у `NSImage`. Растры `18 × 18` и
   `36 × 36` лежат рядом как запасные.
4. Ничего не подкрашивать в коде: система сама решает цвет под фон и выделение.

## Открытые вопросы

- Не проверено, как обе иконки выглядят на настоящем экране в Dock, Finder и
  строке меню — только на рендерах.
- Не сделан монохромный вариант app icon для соответствующей темы macOS.
- Если имя приложения поменяется, направление `A` это переживёт: оно не завязано
  на название.

## Промпты для `gpt-image-2`

Нужны, только если понадобится поискать образ за пределами выбранного. Готовые
иконки они не заменяют: генератор не выдержит равные толщины, точные зазоры и
симметрию дуг, поэтому его результат — эскиз, а не файл.

Каждый промпт рассчитан на отдельную генерацию. Художественная часть отделена от
параметров экспорта.

### App icon, «Ровный абзац»

```text
Flat vector-style app icon artwork for a small macOS system utility.

SUBJECT
A single paragraph of abstract text resolving from broken to clean, read top to bottom. Five horizontal bars, all flush on the same left edge, stacked with even vertical spacing, centered on the canvas.
- Bar 1 (top): split into three uneven segments by two clear gaps; the segments sit at slightly different vertical offsets, as if jittering; the line stops short at about 75% of the full measure; low opacity.
- Bar 2: split into two segments by one gap; stops at about 88%; medium-low opacity.
- Bar 3: unbroken but short, stopping at about 70%; medium-high opacity.
- Bar 4: unbroken, spanning the full measure; full opacity.
- Bar 5: unbroken, stopping at about 60%, like the settled last line of a paragraph; full opacity.
The bars are plain rectangles with slightly softened corners — typeset text, not pills or capsules. Every bar has identical thickness. Nothing is tilted; the composition is strictly orthogonal and calm.

COLOR AND MATERIAL
Background: full-bleed deep muted green, soft vertical gradient from #2E7A61 at the top to #1E5946 at the bottom. No texture, no vignette, no pattern.
Bars: warm off-white #F3F0E8. The transition is expressed by opacity alone — roughly 40%, 55%, 75%, 100%, 100% from top to bottom. No second hue anywhere.
Completely flat and unlit: no gloss, no specular highlight, no bevel, no drop shadow, no inner shadow, no glow, no 3D, no grain, no paper texture.

COMPOSITION
The block of bars occupies about 60% of the canvas width and 46% of its height, optically centered and nudged slightly above true center. Generous empty margin on all four sides; nothing approaches the edges.

FORBIDDEN
No letters, numbers, words, signature or watermark. No microphone, sound wave, waveform, speech bubble, flag, sparkle, star, magic wand, robot, brain, network mesh, pencil, cursor or magnifier. No rounded corners on the canvas itself, no border, no frame, no outer shadow, no mockup, no device, no reflection, no presentation background.

TECHNICAL
Square 1:1 canvas, 1024 x 1024 px, sRGB. Background filled edge to edge. One single icon, centered, one flat image, no transparency, no padding artifacts.
```

### Значок строки меню, «Ровный абзац»

```text
Flat monochrome pictogram for a macOS menu bar template image.

SUBJECT
Three horizontal bars of different lengths, reading as a tiny paragraph whose first line is broken.
- Top bar: split into two segments by a single clear gap; the left segment is longer than the right, and the line stops short of the right edge of the middle bar.
- Middle bar: unbroken, the longest of the three, defining the full width of the mark.
- Bottom bar: unbroken and clearly shorter, like the last line of a paragraph.
All bars have the same thickness, share the same left edge, are strictly horizontal, and have square or barely softened ends.

PROPORTIONS
Think of an 18 x 18 unit grid. Bars are 2 units thick with 3 units of clearance between them. The gap in the top bar is 2 units wide. The mark is centered with about 2 units of margin left and right and 3 units top and bottom. Every stroke and every gap is at least 2 units — nothing hairline, nothing crowded.

COLOR
Pure black shape on a pure white background. Two values only, hard edges, no gray, no gradient, no shadow, no outline, no color.

FORBIDDEN
No letters, numbers or text. No microphone, waveform, speech bubble, sparkle, wand, robot, brain, mesh, pencil, cursor or magnifier. The three bars must never be equal in length — it must not read as a hamburger menu. No frame, no circle or square container, no background shape, no drop shadow, no perspective.

TECHNICAL
Square 1:1 canvas, 1024 x 1024 px, sRGB. One single pictogram, centered, drawn oversized and clean so it can be traced to vector and reduced to an 18 x 18 template glyph. Solid black fill on a flat white field, nothing else on the canvas.
```

### Лист вариаций формы глифа

```text
Exploration sheet of pictogram variants for a macOS menu bar template image. This is a study sheet for visual selection, not a final asset.

LAYOUT
A 3 x 2 grid of six separate pictograms on one white canvas, evenly spaced, each variant fully contained inside its own equal square cell with wide margins. No labels, captions, numbers, borders or dividing lines.

SHARED IDEA
Every variant expresses one thing: a broken, uneven line of text above resolving into whole, even lines below. All variants share the same stroke thickness, the same strictly horizontal geometry, the same common left edge, and the same clear margins.

VARIANTS
1. Three bars: top split into two segments by one gap, middle unbroken and full width, bottom unbroken and short.
2. Three bars: top split into three short uneven segments, middle unbroken and full width, bottom unbroken and short.
3. Three bars: top split into two segments, middle also split by one narrow gap, bottom unbroken and full width.
4. Three bars: top split into two segments sitting at slightly different heights, as if misaligned; middle and bottom unbroken and perfectly level.
5. Four bars: top two split into segments with clear gaps, bottom two unbroken, lengths decreasing toward the last line.
6. Two bars: upper split into two segments by one wide gap, lower unbroken and noticeably longer.

PROPORTIONS
Each variant must survive reduction to 18 x 18 px: strokes and gaps stay visually equal to at least 2 units of an 18-unit grid.

COLOR
Pure black shapes on a pure white background. Two values only, hard edges, no gray, no gradient, no shadow, no outline.

FORBIDDEN
No letters, numbers or text of any kind. No microphone, waveform, speech bubble, sparkle, wand, robot, brain, mesh, pencil or cursor. No variant made of three equal bars, i.e. a hamburger menu. No frames, containers, shadows or perspective.

TECHNICAL
Square 1:1 canvas, 1024 x 1024 px, sRGB, flat white field, exactly six pictograms.
```

### App icon, «Знак корректора»

```text
Flat vector-style app icon artwork for a small macOS system utility.

SUBJECT
A proofreader's close-up mark applied to a line of abstract text. Three horizontal bars stacked with even spacing, all flush on the same left edge, centered on the canvas: a top bar spanning the full measure, a middle bar interrupted by one clean rectangular gap at its center, and a bottom bar stopping at about 65% of the measure like the last line of a paragraph.
Directly above and below that gap sits the editorial close-up mark: two shallow arcs whose bellies face the gap — the upper arc sags down toward it, the lower arc bows up toward it, as if pinching the line shut. The arcs are wider than the gap, evenly weighted, with rounded ends, and are the only curved elements in the whole icon. Everything else is strictly orthogonal. Nothing is tilted.

COLOR AND MATERIAL
Background: full-bleed warm paper tone, soft vertical gradient from #F6F3EC at the top to #E9E5DA at the bottom. No texture, no vignette, no visible paper fibre.
Text bars: deep neutral #1D211F at about 80% opacity.
The two arcs: muted green #28715A — the single accent in the icon.
Completely flat and unlit: no gloss, no specular highlight, no bevel, no drop shadow, no inner shadow, no glow, no 3D, no grain.

COMPOSITION
The text block occupies about 58% of the canvas width; the whole mark including the arcs occupies about 45% of its height, optically centered. Generous empty margin on all four sides; nothing approaches the edges.

FORBIDDEN
No letters, numbers, words, signature or watermark. No microphone, sound wave, speech bubble, flag, sparkle, wand, robot, brain, network mesh, pencil, scissors, cursor or red correction ink. No document sheet outline, no folded page corner. No rounded corners on the canvas itself, no border, no frame, no outer shadow, no mockup, no device, no reflection.

TECHNICAL
Square 1:1 canvas, 1024 x 1024 px, sRGB. Background filled edge to edge. One single icon, centered, one flat image, no transparency.
```

### Значок строки меню, «Знак корректора»

```text
Flat monochrome pictogram for a macOS menu bar template image.

SUBJECT
One horizontal bar interrupted by a single clean gap at its center, with a shallow arc above the gap sagging down toward it and a mirrored shallow arc below bowing up toward it — the editorial mark for closing up a deleted passage. The bellies of both arcs face the gap, so the mark reads as pinching shut rather than pushing apart.
The bar is straight and level and defines the full width of the mark. The two arcs are symmetrical, centered on the gap, and slightly wider than the gap itself.

PROPORTIONS
Think of an 18 x 18 unit grid. The bar is 2 units thick and about 14 units wide. Its gap is about 2.5 units wide. Each arc is 2 units thick, about 6 units wide, and clears the bar by 2 units. The whole mark is about 14 units tall, centered with clear margin all around. Every stroke and every gap is at least 2 units — nothing hairline.

COLOR
Pure black shape on a pure white background. Two values only, hard edges, no gray, no gradient, no shadow, no outline, no color.

FORBIDDEN
No letters, numbers or text. No microphone, waveform, speech bubble, sparkle, wand, robot, brain, mesh, pencil, scissors, cursor or magnifier. No arrowheads on the arcs — they are arcs, not arrows. No frame, no circle or square container, no background shape, no drop shadow, no perspective.

TECHNICAL
Square 1:1 canvas, 1024 x 1024 px, sRGB. One single pictogram, centered, drawn oversized and clean so it can be traced to vector and reduced to an 18 x 18 template glyph. Solid black fill on a flat white field, nothing else on the canvas.
```

## Как выбирать результат генерации

Если промпты всё-таки пойдут в дело, отбирать по этому списку.

**App icon.** Уменьшить до 32 и 16: если переход от рваного к целому исчез,
вариант мёртв, сколько бы он ни нравился в полный размер. Обесцветить — силуэт
должен оставаться внятным. Проверить, что нет запечённых бликов, фасок, теней и
объёма: система наложит своё, и удвоение будет видно сразу. Толщина полос
одинаковая во всех строках. Ничего ближе 15 % холста к краю. Никакого текста,
рамок и артефактов по краям.

**Значок строки меню.** Смотреть только при 16 и 18 px, в светлой и тёмной
строке. Не должно читаться как гамбургер, список или выравнивание текста. Все
зазоры визуально не тоньше штриха. Только чистый чёрный и белый: полутона на
границах допустимы, серые заливки испортят трассировку.

**Обе.** Положить рядом: должно быть видно, что это одно семейство, но не что
одна — уменьшенная копия другой.

## Свежесть

Требования Apple проверены 30 июля 2026 года.

- [Apple: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Apple: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
