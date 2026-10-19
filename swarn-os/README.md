# Swarn-OS — working prototype

Swarn-OS is a multi-tenant jewellery store system (inventory, billing, purchase, repairs, tally) built from the Business Requirements Document
(`docs/AI_Jewellery_SWARN_BRD_v2.0.docx`). The back end is Java 21 / Spring Boot;
the front end is an installable web app (PWA) that works on desktop browsers,
Android and iOS. Everything is free and open-source software.

RFID is not wired in yet (by decision): every tag carries a **QR code**, and the
same scan endpoints will accept RFID EPCs from the Identium CX1500N later
(`item.rfid_epc` is already in the schema).

## Run it

```bash
cd swarn-os
./run-shop-server.sh        # Windows: run-shop-server.bat   (needs Java 21 and Maven)
```

Open <http://localhost:8080>. Other counters, phones and tablets on the shop
Wi-Fi open `http://<server-ip>:8080` and can "Add to home screen" to install it.

On first start a **demo shop** is created with stock in every category,
today's approved rate, one bill, one repair and purchases in every mode:

| Shop code | Users | Password |
| --- | --- | --- |
| `demo` | `owner`, `manager`, `sales`, `accounts`, `stock` | `demo123` |

Platform operator (creates shops): open `#/platform`, user `platform`,
password `platform@123` (set `SWARN_PLATFORM_PASSWORD` in production).

## What works

| Area | In the prototype |
| --- | --- |
| Metal rate | Owner types the 24K gold, silver and platinum rate each morning (per 10 g / per kg as configured) or fetches a live rate; a live rate is only a **proposal** until approved. 22K/20K/18K/14K/9K = 92/84/76/60/40 % of 24K. The approved rate holds all day; billing waits until a rate is approved. |
| Inventory & tags | Gold, diamond (stone details), platinum, silver, silver ornaments, gifting (MRP, quantity). Tag codes and printable **QR labels** (62 × 30 mm). Every stock change is a ledger movement; a ledger check compares item status with the ledger. |
| Sales | Scan by camera / USB scanner / typing, or find by voice. Auto-price (metal × purity rate + making + wastage + stones + GST), discount limit per role, old gold/silver exchange, split payments, credit, GST invoice (print / PDF / WhatsApp), full return. A sold tag cannot be sold again. |
| Purchase | Finished jewellery and gifting from vendors (tags created on receipt), old metal ("treat" purchase) by tested purity with deduction. Paid in **cash, bank, against gold (fine g), against silver (fine g), mixed or credit**; purchase return to vendor. |
| Seen / Unseen | Set automatically: GST invoice and no cash = Seen, otherwise Unseen; only the owner can change it, with a logged reason. Owner and accountant can **show / hide by class** (filter All / Seen / Unseen); other roles never see the class or cost. Stock, billing, tally and statutory exports always include everything. |
| Vendors, customers, karigars | Masters with GSTIN/PAN, full permanent history (items bought, exchanges, purchases, repairs), running account, receive/pay money. |
| Repairs | Intake with weight in, repair tag/receipt with QR, karigar issue and return weights, metal gain/loss, delivery with charges; kept out of sale stock. |
| Daily stock tally | Open a session per counter/category, scan (camera, scanner, or paste a bulk list), see matched / missing / extra / unknown and per-category counts with weights, manager decides each variance (mark lost / accept with reason), strict close, reopen with reason. Repair pieces are a separate bucket. |
| Reports | 20 reports (stock, ageing, tag-wise, sales, GST, purchase by mode and by class, old metal, outstanding, repairs, karigar, tally, rates, HUID, backup log) with date filter, Excel (CSV) and print/PDF. Cash, bank, gold, silver and platinum books with running balance. |
| Voice / AI search | Mic button on every screen (browser speech: English or Hindi). "diamond jewellery below 50000", "22 carat gold chains between 20 and 30 grams", "sone ki angoothi 50 hazar se kam", "हीरे की अंगूठी 1 लाख से कम", "show tag T000012", "aaj ka 22 carat rate kya hai", "repair for rahul". The understood filters are shown as chips; the answer is also spoken. |
| Multi-tenant | One database **per shop**: `LOCAL` = H2 file under `data/tenants/<code>/` (in-shop server, no internet needed) or `CLOUD` = its own PostgreSQL database `swarnos_<code>`. Separate control database for the shop registry only. Per-shop schema migrations at start-up. |
| Configuration | `application.yml` for deployment settings; each shop's `app_config` table for business rules (Settings → Business rules), purities and categories — all audited. |
| USB backup | Settings → Backup to USB: one step, AES-256-GCM encrypted, SHA-256 checksum file, read back and decrypted as a restore test, logged. Restore loads a backup as a new shop (never overwrites live data). |
| Security | Roles OWNER / MANAGER / SALES / ACCOUNTANT / STOCK with server-side permission checks, signed login tokens, BCrypt passwords, audit log of every important action. |

Money, weights and rates are stored as `NUMERIC(18,3)` and calculated with
3 decimals, rounding half-up.

## Settings decided by the owner (defaults)

| Setting | Value |
| --- | --- |
| Purity factors | 22K 0.92, 20K 0.84, 18K 0.76, 14K 0.60, 9K 0.40 |
| Rate source | Manual or live; live needs approval; rate holds all day |
| Precision | 3 decimals |
| Cash limit, PAN/KYC threshold | Blank = no limit (warning appears only if a value is set) |
| Offline | Local mode needs no internet; `offline.maxHours` = 24 |
| Backup | `backup.targetDir` = USB folder, e.g. `E:\SwarnOSBackup` |

## Configuration (environment variables)

| Variable | Default | Meaning |
| --- | --- | --- |
| `SWARN_DATA_DIR` | `./data` | Control DB, local shop DBs, default backup folder |
| `SWARN_PLATFORM_USER` / `SWARN_PLATFORM_PASSWORD` | `platform` / `platform@123` | Platform operator login |
| `SWARN_PG_HOST`, `SWARN_PG_PORT`, `SWARN_PG_USER`, `SWARN_PG_PASSWORD` | `localhost`, `5432`, `postgres`, `postgres` | PostgreSQL server for CLOUD shops |
| `SWARN_CONTROL_DB_URL` | H2 file | Put the shop registry on PostgreSQL instead |
| `SWARN_DEMO` / `SWARN_DEMO_STORAGE` | `true` / `LOCAL` | Create the demo shop and where |
| `SWARN_TOKEN_SECRET` | generated into `data/token.secret` | Signs login tokens |

Cloud server with PostgreSQL: `docker compose up` (see `docker-compose.yml`).

## Tests

```bash
mvn test                                                          # 55 tests: domain rules, a service with mocks, architecture rules, API end to end
mvn test -Dswarn.test.storage=CLOUD -Dtest=ApiIntegrationTest     # API suite with the demo shop on PostgreSQL
```

- **Domain unit tests** (no Spring, no database): pricing (BRD worked example), purity derivation, old-metal valuation,
  purchase payment legs and totals, Seen/Unseen rule, bill totals and discount limit, tally reconciliation, repair
  transitions, backup encryption, the voice interpreter (English, Hinglish, Devanagari).
- **Service test with mocks**: `RateServiceTest` checks approval rules with the repository mocked out.
- **Architecture test** (`ArchitectureTest`, ArchUnit): enforces the layering below on every build.
- **API integration test** (`ApiIntegrationTest`): rate derivation, double-sale blocking, role masking of Seen/Unseen
  and cost, purchase classification, shop isolation, encrypted USB backup and restore, tally, repairs, every report.

## Architecture

Each feature is a module (package) with the same four layers:

```
com.swarnos.<module>
  api/          REST controllers and request/response DTOs (JSON in snake_case). No SQL, no business rules.
  service/      Business rules, permission checks and transactions. Talks to repositories and other modules' services.
  domain/       Entities (records), enums and pure rules - no Spring, no SQL - e.g. PricingEngine, RateDerivation,
                PurchaseTotals, BillCalculator, TallyReconciliation, RepairStatus, BackupCodec.
  repository/   All SQL (Spring JdbcClient) and row mapping to domain records. No business logic.
  infrastructure/ (where needed) technical adapters: tenant connection routing, live metal-rate feeds.
```

Rules checked by `ArchitectureTest`:

| Layer | May use | Must not use |
| --- | --- | --- |
| `api` | service, domain | repository, SQL helpers |
| `service` | repository, domain, other modules' services | api |
| `repository` | domain, SQL helpers | service, api |
| `domain` | other domain types, `common.money`, `common.error` | Spring, JDBC, service, repository, api |

Repositories own their module's tables. A repository may join another module's table only to show a display name
(customer name on a bill); every write and every business decision goes through the owning module's service.
The `reports` module is the read side: report queries, the dashboard and a party's full history.

Errors: services throw `BusinessException` (validation, not found, conflict, forbidden) with no HTTP knowledge;
`GlobalExceptionHandler` in the API layer maps them to status codes and `{"error": "..."}`.

## Code map

```
src/main/java/com/swarnos/
  common/      errors, 3-decimal arithmetic, business clock, SQL helpers, audit trail, document numbering
  security/    roles, permissions, signed tokens, request authentication filter
  tenant/      shop registry (control DB), per-shop database routing, provisioning, platform API
  identity/    sign-in, sessions, staff users
  settings/    business settings, categories, purities, locations
  rates/       daily rate set, approval, purity derivation, live-rate feeds
  inventory/   items, stones, stock ledger, pricing engine
  parties/     customers, vendors, karigars
  accounting/  cash, bank, metal and party books; payments
  purchase/    purchase modes, Seen/Unseen, returns to vendor
  sales/       billing, exchange, split payments, returns
  repair/      repair and job work
  tally/       daily stock tally
  search/      voice / natural-language search
  reports/     reports, dashboard, party history (read side)
  backup/      encrypted USB backup, verify, restore
  demo/        demo shop, created through the services
src/main/resources/db/tenant/   per-shop schema (Flyway), runs on H2 and PostgreSQL
src/main/resources/static/      the web app (no build step)
```

## Not in this prototype yet

- RFID reader integration (CX1500N SDK) and EPC encoding — QR is used meanwhile.
- Device-level offline sync (phone billing with no shop server). In local mode the shop server needs no internet, which covers a shop that loses internet.
- The live-rate provider (BRD open item O-1): a simulated `DEMO` feed and a configurable `HTTP` JSON provider are included.
- GST e-invoicing, WhatsApp/SMS campaigns, photo/visual search, forecasting, and the AI daily summary.
- Native Android/iOS packaging of the web app (it installs as a PWA today).
