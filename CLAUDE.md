# CAPHanaDemoApp — CLAUDE.md

This file helps Claude Code understand the project structure, conventions, and development workflow.

---

## Project Overview

A **SAP Cloud Application Programming (CAP)** application built with Node.js that:
- Exposes an OData V4 service (`InvoiceService`) for Invoice management
- Persists data to **SAP HANA Cloud** (via HDI containers on BTP)
- Uses **SQLite in-memory** for local development (no HANA required by default)
- Supports **hybrid mode** — local Node.js server + local UI5 app connected to remote HANA Cloud
- Serves a **SAPUI5 Fiori Elements** List Report + Object Page UI (via `cds-plugin-ui5` in dev)
- Is deployable to **SAP BTP Cloud Foundry** via MTA

**GitHub:** https://github.com/harshadporwal47/CAPHanaDemoApp
**Deployed App:** https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com/com.caphanademo.invoices/index.html

---

## Project Structure

```
CAPHanaDemoApp/
├── db/
│   ├── schema.cds                        # CDS data model (Invoice, InvoiceToItem)
│   └── data/
│       ├── invoice-Invoice.csv           # Seed data for Invoice (5 records)
│       └── invoice-InvoiceToItem.csv     # Seed data for InvoiceToItem (8 records)
├── srv/
│   ├── invoice-service.cds              # OData service definition + UI annotations
│   └── invoice-service.js               # Custom event handlers (business logic)
├── app/
│   └── com.caphanademo.invoices/
│       ├── webapp/
│       │   ├── index.html               # SAPUI5 bootstrap (CDN 1.120.23, sap_horizon)
│       │   ├── manifest.json            # App descriptor (Fiori Elements, OData model)
│       │   ├── Component.js             # UI5 component root
│       │   ├── changes/
│       │   │   ├── flexibility-bundle.json   # sap.ui.fl bundle (must be valid JSON object)
│       │   │   └── changes-bundle.json
│       │   ├── controller/              # BaseController, App, Main
│       │   ├── view/                    # App.view.xml, Main.view.xml
│       │   ├── model/                   # formatter.js, models.js
│       │   └── i18n/                    # i18n.properties
│       ├── ui5.yaml                     # UI5 tooling config (local dev)
│       └── package.json
├── approuter/
│   ├── xs-app.json                      # Approuter routing + welcome file
│   └── package.json                     # @sap/approuter dependency
├── scripts/
│   └── copy-app.js                      # Copies webapp → gen/srv/app/ at MTA build time
├── gen/                                 # Build output (auto-generated, NOT in git)
├── mta.yaml                             # MTA deployment descriptor for BTP CF
├── xs-security.json                     # XSUAA roles and token config (no URLs — dynamic)
├── package.json                         # Root Node.js dependencies, scripts, dev auth config
├── .cdsrc.json                          # CDS db + auth profiles; copied to gen/srv at build
├── .cdsrc-private.json                  # HANA binding credentials — NOT in git (gitignored)
├── .env.example                         # Template for local environment variables
├── default-env.json.example             # Template for HANA Cloud credentials (hybrid mode)
├── .gitignore
└── CLAUDE.md                            # This file
```

---

## Data Model

### `invoice.Invoice` (Header)
| Field          | Type           | Notes                                  |
|----------------|----------------|----------------------------------------|
| ID             | UUID (PK)      | Auto-generated via `cuid`              |
| invoiceNumber  | String(20)     | Auto-generated: `INV-YYYY-NNNN`        |
| customerName   | String(100)    | `@mandatory`                           |
| customerEmail  | String(200)    |                                        |
| invoiceDate    | Date           | `@mandatory`                           |
| dueDate        | Date           |                                        |
| totalAmount    | Decimal(15,2)  | Kept in sync with sum of item amounts  |
| currency       | String(3)      | Default: USD                           |
| status         | InvoiceStatus  | OPEN / PENDING / PAID / CANCELLED; `@assert.range` |
| notes          | String(500)    |                                        |
| items          | Composition   | → many InvoiceToItem                   |

Both entities use `cuid` (UUID PK) and `managed` (createdAt, createdBy, modifiedAt, modifiedBy).

### `invoice.InvoiceToItem` (Line Items)
| Field       | Type           | Notes                                  |
|-------------|----------------|----------------------------------------|
| ID          | UUID (PK)      | Auto-generated via `cuid`              |
| invoice     | Association    | → Invoice (FK: invoice_ID); `@mandatory` |
| itemNumber  | Integer        | `@mandatory`                           |
| description | String(200)    | `@mandatory`                           |
| quantity    | Decimal(10,2)  | `@mandatory`                           |
| unit        | String(10)     | Default: EA                            |
| unitPrice   | Decimal(15,2)  | `@mandatory`                           |
| amount      | Decimal(15,2)  | Auto-computed: quantity × unitPrice    |
| taxRate     | Decimal(5,2)   | Default: 0                             |
| taxAmount   | Decimal(15,2)  | Auto-computed: amount × taxRate / 100  |
| netAmount   | Decimal(15,2)  | Auto-computed: amount + taxAmount      |

---

## Service Layer (`srv/invoice-service.cds`)

Service path: `/invoice` (OData V4). Exposed entities:

| Entity        | Draft enabled | Notes                                      |
|---------------|---------------|--------------------------------------------|
| `Invoices`    | ✅ Yes         | Projection on `invoice.Invoice`            |
| `InvoiceItems`| ❌ No          | Projection on `invoice.InvoiceToItem`      |

### Bound Actions (on `Invoices`)
| Action          | Parameters       | Returns              | Business Rule                            |
|-----------------|------------------|----------------------|------------------------------------------|
| `markAsPaid`    | —                | `{ message }`        | Validates not already PAID / CANCELLED   |
| `cancelInvoice` | `reason: String` | `{ message }`        | Validates not already CANCELLED / PAID   |

### Unbound Actions & Functions
| Name                      | Type     | Returns                              |
|---------------------------|----------|--------------------------------------|
| `getInvoiceSummary()`     | Function | Array of `{status, count, totalAmount, currency}` |
| `recalculateInvoiceTotal` | Action   | `{invoiceID, totalAmount, itemCount}` |

### UI Annotations (in `invoice-service.cds`)
- `UI.HeaderInfo` — title: invoiceNumber, description: customerName
- `UI.LineItem` — 7 columns: invoiceNumber, customerName, invoiceDate, dueDate, totalAmount, currency, status
- `UI.SelectionFields` — filter bar: status, customerName, invoiceDate
- `UI.Facets` — Object Page: "General Information" (InvoiceDetails + Financial) + "Invoice Items" sub-table

---

## Custom Handler Logic (`srv/invoice-service.js`)

| Hook                                     | What it does                                                      |
|------------------------------------------|-------------------------------------------------------------------|
| `before CREATE Invoices`                 | Auto-generates `invoiceNumber` (INV-YYYY-NNNN via DB count), sets status=OPEN, totalAmount=0 |
| `before CREATE/UPDATE InvoiceItems`      | Validates amount = qty × unitPrice (±0.01 tolerance), computes `taxAmount`, `netAmount` |
| `after CREATE/UPDATE/DELETE InvoiceItems`| Calls `_syncInvoiceTotal()` → sums items, updates Invoice.totalAmount |
| `on markAsPaid`                          | 404 if not found; 400 if already PAID or CANCELLED; sets status=PAID |
| `on cancelInvoice`                       | 404 if not found; 400 if already CANCELLED or PAID; sets status=CANCELLED + notes |
| `on getInvoiceSummary`                   | SELECT status, count(*), sum(totalAmount), currency GROUP BY status, currency |
| `on recalculateInvoiceTotal`             | 404 if not found; calls `_syncInvoiceTotal()`; returns result     |
| `_syncInvoiceTotal(invoiceID)` (private) | SELECTs all item.amount, sums them, UPDATEs Invoice.totalAmount   |

Logging: `cds.log('invoice-service')` → `LOG.info / LOG.debug`

---

## Configuration Architecture

### Three config sources (in priority order — highest wins)

```
.cdsrc-private.json   ← HANA binding credentials (git-ignored, created by cds bind)
       ↑ overrides
.cdsrc.json           ← DB + auth per profile; also copied to gen/srv at build time
       ↑ overrides
package.json (cds{})  ← Dev auth config (mocked users for development + hybrid)
```

### `.cdsrc.json` — profiles
```json
{
  "requires": {
    "db": {
      "[production]": { "kind": "hana" },
      "[hybrid]":     { "kind": "hana" },
      "[development]":{ "kind": "sqlite", "credentials": { "url": ":memory:" } }
    },
    "auth": {
      "[production]": { "kind": "xsuaa" },
      "[hybrid]":     { "kind": "mocked" }   ← mocked locally even with HANA
    }
  }
}
```

### `package.json` cds section — dev auth with mocked users
```json
{
  "cds": {
    "requires": {
      "auth": {
        "[production]":  { "kind": "xsuaa" },
        "[development]": { "kind": "mocked" },
        "[hybrid]":      { "kind": "mocked" }
      }
    }
  }
}
```

> **Critical rule:** `.cdsrc.json` must NOT have `"profiles": ["development"]` at the top level.
> That hardcoding forces SQLite + mocked auth even on BTP CF where `NODE_ENV=production`.

---

## Local Development

### Option 1 — SQLite in-memory (fastest, no BTP needed)

```bash
npm install
npm run watch
```

- URL: http://localhost:4004
- UI: http://localhost:4004/com.caphanademo.invoices/index.html
- Auth: mocked (no login prompt; `*: true` allows all users)
- DB: SQLite in-memory, seeded from `db/data/*.csv`
- UI5 served by: `cds-plugin-ui5` (mounts `app/` automatically)

### Option 2 — Hybrid mode (local server + HANA Cloud)

**One-time setup** (only needed if `.cdsrc-private.json` is missing or stale):
```bash
cf login -a https://api.cf.us10.hana.ondemand.com
npx cds bind --to CAPHanaDemoApp-db
```
This creates `.cdsrc-private.json` with the HDI container credentials.

**Start:**
```bash
npm run watch:hybrid       # = cds watch --profile hybrid
```

- URL: http://localhost:4004
- UI: http://localhost:4004/com.caphanademo.invoices/index.html
- Auth: mocked (no login prompt)
- DB: **HANA Cloud** (reads credentials from `.cdsrc-private.json`)
- UI5: served live by `cds-plugin-ui5` (uses SAPUI5 1.146.x from local tooling)
- Requires: HANA Cloud instance must be **started** in BTP Cockpit

**Startup log confirms correct config:**
```
bound db to cf managed service CAPHanaDemoApp-db:CAPHanaDemoApp-db-key
connect to db > hana { host: '...hanacloud.ondemand.com', ... }
using auth strategy { kind: 'mocked' }
server listening on { url: 'http://localhost:4004' }
```

---

## BTP Deployment

### Prerequisites
- SAP BTP trial account with Cloud Foundry environment enabled
- SAP HANA Cloud instance provisioned and **started** in BTP trial
- Tools: `cf` CLI, `mbt` (`npm install -g mbt`), MultiApps CF plugin

### Deploy Steps

```bash
# 1. Log in
cf login -a https://api.cf.us10.hana.ondemand.com

# 2. Build MTA archive (runs npm install + cds build + copy-app.js)
mbt build

# 3. Deploy
cf deploy mta_archives/CAPHanaDemoApp_1.0.0.mtar
```

The MTA build step runs (via `mta.yaml` before-all):
1. `npm install --production=false`
2. `npx cds build --production` → generates `gen/srv/` and `gen/db/`
3. `node scripts/copy-app.js` → copies `app/...webapp/` into `gen/srv/app/`

### Post-Deployment — Assign Role Collection
BTP Cockpit → Subaccount → Security → Users → your user → Assign Role Collection → **InvoiceAdmin**

### Deployed URLs (trial account)
| Component    | URL                                                                                                  |
|--------------|------------------------------------------------------------------------------------------------------|
| Approuter    | `https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com`              |
| CAP Server   | `https://5b4c46e4trial-dev-caphanademoapp-srv.cfapps.us10-001.hana.ondemand.com`                    |
| App (direct) | `https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com/com.caphanademo.invoices/index.html` |

---

## Key Dependencies

| Package             | Purpose                                                      |
|---------------------|--------------------------------------------------------------|
| `@sap/cds`          | CAP runtime (OData, CQL, event framework)                    |
| `@cap-js/hana`      | HANA Cloud adapter for CAP                                   |
| `@cap-js/sqlite`    | SQLite adapter for local development (devDependency)         |
| `@sap/xssec`        | JWT token validation for XSUAA (BTP auth)                    |
| `passport`          | HTTP auth middleware used by `@sap/xssec`                    |
| `@sap/approuter`    | Application Router — OAuth2 login + request proxy (BTP only) |
| `@sap/cds-dk`       | CAP Developer Kit (cds CLI, codegen) — devDependency         |
| `cds-plugin-ui5`    | Serves `app/` UI5 apps via CAP dev server — devDependency    |

---

## CDS Profiles

| Profile       | DB          | Auth     | When used                               |
|---------------|-------------|----------|-----------------------------------------|
| `development` | SQLite mem  | mocked   | `npm run watch` (default, NODE_ENV unset) |
| `hybrid`      | HANA Cloud  | mocked   | `npm run watch:hybrid` (local + HANA)   |
| `production`  | HANA Cloud  | xsuaa    | BTP CF deployment (NODE_ENV=production) |

---

## Architecture (BTP)

```
Browser
  │
  ▼
Approuter (CAPHanaDemoApp-approuter)
  │  xs-app.json → all traffic proxied to srv-api destination
  │  XSUAA OAuth2 login/callback handled here
  │  redirect-uri built dynamically via MTA: ${org}-${space}-...-approuter.${default-domain}/**
  │
  ▼
CAP Server (CAPHanaDemoApp-srv)
  │  Serves Fiori Elements UI from gen/srv/app/com.caphanademo.invoices/
  │  Serves OData V4 at /invoice
  │  Validates JWT from XSUAA
  │
  ▼
HANA Cloud HDI Container (CAPHanaDemoApp-db)
  │  Tables: invoice.Invoice, invoice.InvoiceToItem
  │  Views:  InvoiceService.Invoices, InvoiceService.InvoiceItems
```

---

## XSUAA Configuration (`xs-security.json` + `mta.yaml`)

- `xsappname` in `xs-security.json` is the base name `CAPHanaDemoApp`.
  MTA substitutes it to `CAPHanaDemoApp-${org}-${space}` at deploy time via the `config:` block.
- `redirect-uris` are **not** in `xs-security.json` (it is environment-agnostic).
  They are set dynamically in `mta.yaml`:
  ```yaml
  config:
    xsappname: CAPHanaDemoApp-${org}-${space}
    oauth2-configuration:
      redirect-uris:
        - "https://${org}-${space}-caphanademoapp-approuter.${default-domain}/**"
  ```
- If the Approuter URL changes (new space/org), **no file edits needed** — MTA variables handle it.
- To update a running service manually:
  ```bash
  cf update-service CAPHanaDemoApp-auth -c '{"xsappname":"CAPHanaDemoApp-<org>-<space>","oauth2-configuration":{"redirect-uris":["https://.../**"]}}'
  cf restage CAPHanaDemoApp-approuter CAPHanaDemoApp-srv
  ```

---

## Conventions

- **Entity namespace**: `invoice` (prefix for all DB artefacts)
- **CSV seed files**: named `<namespace>-<EntityName>.csv` in `db/data/`
- **Service path**: `/invoice` (OData V4)
- **Handler file**: same name as the service CDS file (`invoice-service.js`)
- **Logging**: `cds.log('invoice-service')` — use `LOG.info/debug/warn/error`; never `console.log` in production
- **Error codes**: 400 for validation failures, 404 for not-found
- **UI static files**: in local dev served live from `app/` by `cds-plugin-ui5`; in BTP copied to `gen/srv/app/` by `scripts/copy-app.js`
- **Draft**: enabled on `Invoices` (`@odata.draft.enabled`); NOT on `InvoiceItems`
