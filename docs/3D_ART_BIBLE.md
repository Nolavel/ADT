
# 3D Art Bible — ADT / Blackrock

> **Рабочее название стиля:**  
> **Stylized Middle-Poly Painterly Realism / Graphic Sci-Fi**

Это не маркетинговый термин. Это внутренний язык форм и конструкций.

Документ фиксирует **неизменяемый художественный язык** проекта.  
Всё, что генерируется AI или рисуется человеком, должно подчиняться этим правилам, а не интерпретировать их заново каждый раз.

**Ключевые ориентиры:**
- GTA Vice City — уровень читаемости форм и детализации
- Disco Elysium — живописность, намеренная нереалистичность, цвет как характер
- Hanna Chie Stef — конкретный язык лиц, масс и painterly shading персонажей

---

## 0. Главный принцип (одной фразой)

> **Реалистично спроектировано → художественно упрощено → графически освещено → живописно окрашено.**

Мы **не** делаем:
- low-poly (Fortnite / PS1 / toy-like)
- photorealism / photogrammetry
- pure flat-shaded cartoon

Мы работаем в **промежуточной зоне** между low и middle poly, где важна не плотность полигонов, а **способ упрощения формы**.

---

## 1. Form Language (единая система для всего)

Любой объект (персонаж, здание, транспорт, prop) строится по одной иерархии:

```
Level 1 — SILHOUETTE
        ↓
Level 2 — PRIMARY FORMS          (основные массы)
        ↓
Level 3 — SECONDARY FORMS        (конструктивные элементы)
        ↓
Level 4 — ACCENT DETAILS         (характерные акценты)
        ↓
Level 5 — SURFACE DETAIL         (только если действительно нужно)
```

**Правило:**  
Последний уровень (Surface Detail) **никогда** не должен диктовать стиль.  
80 % характера объекта создаётся силуэтом + primary + secondary forms.  
20 % — акцентами и поверхностью.

### Ключевое правило геометрии

> **Geometry should describe planes, not surfaces.**

Геометрия должна ловить свет крупными плоскостями, а не пытаться имитировать реальную поверхность.

Вместо continuous realistic mesh → читаемые крупные плоскости с достаточно резкими переходами.

---

## 2. Персонажи (с опорой на Hanna Chie Stef)

### Основной язык

Персонажи строятся в стиле **Hanna Chie Stef + Disco Elysium мышление**:

- Характер важнее анатомической точности
- Лицо и тело собираются **крупными массами**, а не мелкой геометрией
- Сильный, читаемый силуэт
- Painterly treatment кожи и материалов
- Контролируемая асимметрия
- Преувеличенные характерные признаки

### Конструкция лица

Лицо не строится как скан. Оно строится крупными плоскостями:

```
волосы (масса / силуэт)
───────────────────────
         лоб
    ┌─────────────┐
    │ глаз   глаз │
    │     нос     │
    │     рот     │
    └─────────────┘
      челюсть / борода
```

**Что видно на референсах Hanna Chie Stef и что нужно переносить:**

- Крупные плоскости лба, скул, носа, подбородка
- Достаточно резкие переходы между массами
- Минимум мелкой «каши»
- Волосы — скорее объём и силуэт, чем тысячи прядей
- Глаза, брови, губы — графичные и выразительные
- Кожа — painterly, с крупными тональными вариациями
- Пирсинг, тату, аксессуары — как акценты, а не как детализация ради детализации

### Что запрещено

- Photogrammetry / realistic skin / pores / micro-wrinkles
- Тысячи отдельных прядей волос
- Ultra-realistic PBR + subsurface scattering
- Огромное количество мелких bevel
- Toy-like / Fortnite proportions
- Полностью flat-shaded low-poly
- PS1/PS2 grotesque

### Что разрешено и желательно

- Крупные плоскости лица и тела
- Контролируемая асимметрия
- Одежда крупными конструктивными формами
- Минимум мелкой геометрической «каши»
- Характер через массу, силуэт и 3–5 сильных акцентов

### Цвет и материал кожи

```
base skin tone          → тёплый muted
large tonal variation   → да
controlled roughness    → да
strong planes           → обязательно
subtle painted accents  → да
pores / micro-detail    → нет
```

---

## 3. Окружение (здания и архитектура)

Язык персонажей переносится на здания один в один.

Здание — это **не** «реалистичный небоскрёб с 400 материалами».

Это:
- Большая выразительная форма
- Несколько крупных конструктивных слоёв
- Несколько очень характерных деталей

Пример иерархии:
```
┌─────────────┐
│             │
│  верхний    │
│   объём     │
└─────┬───────┘
      │
┌─────┴───────┐
│  HVAC /     │
│  pipes /    │
│  инфраструк.│
└─────┬───────┘
      │
┌─────┴───────┐
│             │
│ MAIN MASS   │
│             │
└─────────────┘
```

**80 %** визуального характера = силуэт + пропорции + major planes + value + color blocks.  
**20 %** = трубы, кабели, вывески, кондиционеры, двери, мусор, антенны, мелкие props.

---

## 4. Транспорт

Транспорт — **industrial-designed**, а не realistic vehicle.

Процесс:
```
real vehicle
    ↓
simplify
    ↓
exaggerate proportions
    ↓
strong silhouette
    ↓
3–7 major construction masses
    ↓
functional details only where they explain construction
```

Пример hover-taxi:
- Корпус — одна большая читаемая форма
- Кабина — отдельная масса
- Двигатели / nacelles — отдельные выразительные элементы
- Двери — **отдельные** элементы (не сливать с корпусом)
- Трубы / швы — только там, где они объясняют конструкцию

---

## 5. Props

Каждый prop должен иметь **визуальную икону** (signature).

Игрок должен понимать «это терминал» / «это урна» / «это оружие» по силуэту и 3–4 формам, а не по 48 мелким деталям.

Примеры:
- Trash can → цилиндр + крышка + один яркий элемент
- Terminal → корпус + экран + одна характерная стойка
- Weapon → 3–5 крупных масс + distinctive silhouette

---

## 6. Материалы

**PBR foundation + painterly material treatment.**

Физическая основа есть (roughness, metallic, normal, AO), но визуально материалы остаются **графичными**.

### Кожа
- Base skin tone
- Large tonal variation
- Controlled roughness
- Strong planes
- Subtle painted accents

**Не** pores, micro-normal, photorealistic specular, subsurface realism.

### Одежда и поверхности
- Large color/value masses
- Few seams
- Few functional details
- Wear только там, где он визуально значим

---

## 7. Цвет

Цвет **не** пытается быть физически правильным.  
Он работает на character design и читаемость.

Типичная схема:
```
skin          → warm muted base
clothes       → dominant color
accessories   → dark neutral
accent        → small high-saturation point
```

Мир должен быть **визуально грязным**, но не серо-коричневым.

Ориентир сеттинга:  
грязный sci-fi 70–80-х + cyberpunk + steampunk **без** буквальных steam-маркеров и без generic neon overload.

---

## 8. Свет

- Свет должен **раскрывать major planes**
- Soft cinematic light с controlled contrast
- Материалы остаются читаемыми
- Не photorealistic lighting

---

## 9. Что берём из Disco Elysium (и чего не берём)

**Берём:**
- Живописность
- Выразительную форму
- Намеренную нереалистичность
- Цветовые отношения
- Визуальную индивидуальность
- Ощущение, что каждый объект «нарисован человеком»

**Не берём:**
- 2D painterly language как геометрию
- Прямую попытку «сделать Disco Elysium в 3D»

Правильная формулировка:  
**3D-модели, построенные с мышлением Disco Elysium + stylized middle-poly production + язык Hanna Chie Stef.**

---

## 10. Immutable Style (никогда не меняется)

Эти пункты — **жёсткие ограничения** для любого ассета и любого AI-промпта:

- Middle-poly density
- Painterly / graphic, not photorealistic
- Strong readable silhouettes
- Large designed planes instead of micro-detail
- Anatomically believable but intentionally simplified
- Controlled asymmetry
- Dirty late-70s/80s industrial science fiction
- Cyberpunk without generic neon overload
- Steampunk influence without literal Victorian/steam machinery
- Muted industrial palette + selective saturated accents
- Geometry describes planes, not surfaces
- Primary forms dominate
- Character language inspired by Hanna Chie Stef (large facial planes, graphic features, painterly skin)

---

## 11. Структура работы с AI

AI всегда получает **две вещи**:

### 1. Immutable Style
(блок выше — копируется почти без изменений)

### 2. Asset Brief
(меняется под конкретный объект)

Пример структуры Asset Brief:

```
OBJECT:          hover taxi
FUNCTION:        cheap civilian transport
ERA:             2999 but retro-futuristic technology
MATERIAL:        painted metal / polymer / glass
DAMAGE:          moderate wear
SILHOUETTE:      compact, heavy, utilitarian
PRIMARY FORMS:   body, cabin, engine nacelles
SECONDARY:       separated doors, landing geometry, functional vents
ACCENTS:         ...
```

Схема:
```
STYLE BIBLE (Immutable)
        │
┌───────┼───────┐
↓       ↓       ↓
CHARACTER  VEHICLE  BUILDING / PROP
│          │          │
↓          ↓          ↓
brief      brief      brief
```

Это позволяет генерировать персонажа, ховер, дом и мусорный контейнер одним языком, а не четырьмя разными играми.

---

## 12. Краткая формула для промптов

**Хороший базовый блок для AI:**

```
STYLE IDENTITY
Stylized painterly middle-poly 3D.
Graphic rather than photorealistic.
Anatomically believable but intentionally simplified.
Strong readable silhouettes.
Large designed planes instead of micro-detail.
Controlled asymmetry.
Muted industrial palette with selective saturated accents.
Character language inspired by Hanna Chie Stef: large facial planes, graphic features, painterly skin treatment.

GEOMETRY
Medium polygon density.
Primary forms must dominate.
Secondary forms explain construction.
Avoid excessive bevels and micro-geometry.
No generic low-poly faceting.

MATERIALS
PBR-based but artistically simplified.
Large color/value regions.
Controlled roughness.
No photorealistic surface noise.

LIGHTING
Designed to reveal major planes.
Soft cinematic light with controlled contrast.

DESIGN
Dirty late-70s/80s science fiction.
Industrial. Used. Functional.
Slightly grotesque.
Cyberpunk without generic neon overload.
Steampunk influence without literal Victorian/steam machinery.
```

После этого блока идёт конкретный Asset Brief.

---

## 13. Запрещённые формулировки для AI

Никогда не писать просто:
- «Create a Disco Elysium cyberpunk character»
- «Make it like GTA Vice City»
- «Mid-poly cyberpunk»
- «Hanna Chie Stef style» (без раскрытия принципов)

Эти фразы расползаются.  
Всегда давать **иерархию ограничений** + конкретный brief.
