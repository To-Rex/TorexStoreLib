# TorexStore Performance Benchmark

TorexStore kutubxonasining to'liq performance va stress testlari.

## 🚀 Ishlatish

```bash
# Barcha benchmarklarni ishga tushirish
flutter test benchmark/torexstore_benchmark.dart

# Ma'lum bir test guruhini ishga tushirish
flutter test benchmark/torexstore_benchmark.dart --name "Sequential Write"
flutter test benchmark/torexstore_benchmark.dart --name "Query"
flutter test benchmark/torexstore_benchmark.dart --name "Stress"

# Batafsil output bilan
flutter test benchmark/torexstore_benchmark.dart --reporter expanded
```

## 📋 Benchmark Turlari

| # | Test | Tavsif |
|---|------|--------|
| 1 | **Sequential Write** | 100, 500, 1000, 5000 ta hujjatni ketma-ket yozish |
| 2 | **Sequential Read** | 1000 ta hujjatni o'qish + null (cache miss) |
| 3 | **Query** | eq, gt, range, and, or, all filterlari |
| 4 | **Update** | 500 ta hujjatni yangilash |
| 5 | **Delete** | 500 ta hujjatni o'chirish |
| 6 | **Compaction** | Diskni tozalash samaradorligi |
| 7 | **Large Documents** | ~10KB hajmdagi hujjatlar |
| 8 | **Multi-Collection** | 10 ta kolleksiya × 100 ta hujjat |
| 9 | **Exists & Count** | Mavjudlikni tekshirish va sonlash |
| 10 | **Watch (Reactive)** | Real-time hodisalar |
| 11 | **Restart & Recovery** | WAL recovery va qayta yuklash |
| 12 | **Stress Test** | 5000 ta hujjat bilan to'liq CRUD |
| 13 | **ID Generation** | 10000 ta UUID v4 |
| 14 | **Disk Size** | Disk hajmi tahlili |

## 📊 Kutiladigan Natijalar

### Write Performance (Dart layer)

| Hujjatlar | Kutilgan vaqt | Tezlik |
|-----------|--------------|--------|
| 100 | 50-200ms | 500-2000 ops/s |
| 500 | 300-1500ms | 300-1600 ops/s |
| 1,000 | 800-4000ms | 250-1250 ops/s |
| 5,000 | 5-30s | 150-1000 ops/s |

> ⚠️ Har `put()` da butun kollektsiya qayta yoziladi — O(n) per write.

### Read Performance

| Hujjatlar | Kutilgan vaqt | Tezlik |
|-----------|--------------|--------|
| 1,000 | 5-50ms | 20,000-200,000 ops/s |
| 10,000 (null) | 50-500ms | 20,000-200,000 ops/s |

> ✅ Read O(1) — HashMap lookup, disk I/O yo'q.

### Query Performance

| Filter | 1000 docs | Tavsif |
|--------|-----------|--------|
| eq | 1-10ms | To'liq scan |
| gt | 1-10ms | To'liq scan |
| range | 1-10ms | To'liq scan |
| and (3 shart) | 2-15ms | To'liq scan |
| or (2 shart) | 2-15ms | To'liq scan |
| all | 1-5ms | Filtrlash yo'q |

## 🏗️ Arxitektura Tahlili

### Write Yo'li (har `put()` uchun)
```
1. WAL ga yozish (append-only)     → disk I/O #1
2. In-memory store ga yozish       → O(1)
3. Butun kolleksiyani diskka yozish → disk I/O #2 (O(n)!)
4. WAL commit (truncate)           → disk I/O #3
```

### Read Yo'li (har `get()` uchun)
```
1. In-memory HashMap lookup → O(1), disk I/O yo'q
```

### Query Yo'li
```
1. getAll() → barcha hujjatlarni yig'ish
2. where()  → har bir hujjatni filterdan o'tkazish (O(n))
```

## 🔑 Asosiy Xulosalar

1. **Read juda tez** — HashMap O(1), RAM da ishlaydi
2. **Write O(n)** — har write da butun kollektsiya qayta yoziladi
3. **Query O(n)** — Dart layer da full scan
4. **Rust layer kuchliroq** — PrimaryIndex O(1), SecondaryIndex O(log n)
5. **10K-50K docs** gacha optimal ishlaydi
6. **WAL** crash safety ta'minlaydi, lekin write ni sekinlashtiradi
