# CAPHanaDemoApp — CLAUDE.md

This file helps Claude Code understand the project structure, conventions, and development workflow.

---

## Project Overview

A **SAP Cloud Application Programming (CAP)** application built with Node.js that:
- Exposes an OData V4 service (`InvoiceService`) for Invoice management
- Persists data to **SAP HANA Cloud** (via HDI containers on BTP)
- Uses **SQLite in-memory** for local development (no HANA required by default)
- Supports **hybrid mode** — local Node.js server connected to a remote HANA instance
- Serves a **SAPUI5 Fiori Elements** List Report + Object Page UI
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
│       ├── invoice-Invoice.csv           # Seed data for Invoice
│       └── invoice-InvoiceToItem.csv     # Seed data for InvoiceToItem
├── srv/
│   ├── invoice-service.cds              # OData service definition + annotations
│   └── invoice-service.js               # Custom event handlers (business logic)
├── app/
│   └── com.caphanademo.invoices/
│       ├── webapp/
│       │   ├── index.html               # SAPUI5 bootstrap (CDN 1.120.23, sap_horizon)
│       │   ├── manifest.json            # App descriptor (Fiori Elements, OData model)
│       │   ├── Component.js             # UI5 component root
│       │   ├── changes/
│       │   │   ├── flexibility-bundle.json   # sap.ui.fl bundle (must be valid JSON array structure)
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
│   └── copy-app.js                      # Copies webapp → gen/srv/app/ at build time
├── gen/                                 # Build output (auto-generated, NOT in git)
├── mta.yaml                             # MTA deployment descriptor for BTP CF
├── xs-security.json                     # XSUAA security + redirect-uris config
├── package.json                         # Root Node.js dependencies and scripts
├── .cdsrc.json                          # CDS profiles + build config (no hardcoded profile)
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
| customerName   | String(100)    |                                        |
| customerEmail  | String(200)    |                                        |
| invoiceDate    | Date           |                                        |
| dueDate        | Date           |                                        |
| totalAmount    | Decimal(15,2)  | Kept in sync with sum of item amounts  |
| currency       | String(3)      | Default: USD                           |
| status         | String(20)     | OPEN / PENDING / PAID / CANCELLED      |
| notes          | String(500)    |                                        |
| items          | Composition   | → many InvoiceToItem                   |

### `invoice.InvoiceToItem` (Line Items)
| Field       | Type           | Notes                                  |
|-------------|----------------|----------------------------------------|
| ID          | UUID (PK)      | Auto-generated via `cuid`              |
| invoice     | Association    | → Invoice (FK: invoice_ID)             |
| itemNumber  | Integer        |                                        |
| description | String(200)    |                                        |
| quantity    | Decimal(10,2)  |                                        |
| unit        | String(10)     | Default: EA                            |
| unitPrice   | Decimal(15,2)  |                                        |
| amount      | Decimal(15,2)  | Auto-computed: quantity × unitPrice    |
| taxRate     | Decimal(5,2)   | Default: 0                             |
| taxAmount   | Decimal(15,2)  | Auto-computed: amount × taxRate / 100  |
| netAmount   | Decimal(15,2)  | Auto-computed: amount + taxAmount      |

---

## Service API

Base URL (local): `http://localhost:4004/invoice`

### Entities
| Endpoint                         | Methods                    |
|----------------------------------|----------------------------|
| `/invoice/Invoices`              | GET, POST                  |
| `/invoice/Invoices(ID)`          | GET, PUT, PATCH, DELETE    |
| `/invoice/Invoices(ID)/items`    | GET (via $expand)          |
| `/invoice/InvoiceItems`          | GET, POST                  |
| `/invoice/InvoiceItems(ID)`      | GET, PUT, PATCH, DELETE    |

### Actions & Functions
| Endpoint                                       | Method | Description                        |
|------------------------------------------------|--------|------------------------------------|
| `/invoice/Invoices(ID)/markAsPaid`             | POST   | Mark invoice as PAID               |
| `/invoice/Invoices(ID)/cancelInvoice`          | POST   | Cancel invoice (body: `{reason}`)  |
| `/invoice/getInvoiceSummary()`                 | GET    | Aggregated totals by status        |
| `/invoice/recalculateInvoiceTotal`             | POST   | Sync invoice total from items      |

---

## Custom Handler Logic (`srv/invoice-service.js`)

| Hook                                     | What it does                                       |
|------------------------------------------|----------------------------------------------------|
| `before CREATE Invoices`                 | Auto-generates `invoiceNumber`, sets status=OPEN   |
| `before CREATE/UPDATE InvoiceItems`      | Computes `amount`, `taxAmount`, `netAmount`        |
| `after CREATE/UPDATE/DELETE InvoiceItems`| Recalculates parent Invoice `totalAmount`          |
| `on markAsPaid`                          | Validates + sets status=PAID                       |
| `on cancelInvoice`                       | Validates + sets status=CANCELLED with notes       |
| `on getInvoiceSummary`                   | GROUP BY status aggregate query                    |
| `on recalculateInvoiceTotal`             | Re-sums items and updates Invoice total            |

---

## Local Development

### Option 1 — SQLite in-memory (no HANA needed)

```bash
npm install
npm run watch        # starts cds watch on http://localhost:4004
```

Seed data from `db/data/*.csv` is loaded automatically.

### Option 2 — Hybrid mode (local server + remote HANA Cloud)

1. **Log in to BTP CF trial:**
   ```bash
   cf login -a https://api.cf.us10.hana.ondemand.com
   ```

2. **Create the HDI container (first time only):**
   ```bash
   cf create-service hana hdi-shared CAPHanaDemoApp-db
   cf create-service-key CAPHanaDemoApp-db CAPHanaDemoApp-db-key
   ```

3. **Bind the service for local use:**
   ```bash
   npx cds bind --to CAPHanaDemoApp-db
   ```
   This creates `.cdsrc-private.json` with the service binding credentials.

4. **Deploy DB artefacts to HANA:**
   ```bash
   npm run build
   npx cds deploy --to hana --profile hybrid
   ```

5. **Start in hybrid mode:**
   ```bash
   npm run watch:hybrid
   ```

---

## BTP Deployment

### Prerequisites
- SAP BTP trial account with Cloud Foundry environment enabled
- SAP HANA Cloud instance provisioned and **started** in BTP trial
- Installed tools:
  - `cf` CLI: [docs.cloudfoundry.org](https://docs.cloudfoundry.org/cf-cli/)
  - `mbt` (MTA Build Tool): `npm install -g mbt`
  - `MultiApps CF plugin`: `cf install-plugin multiapps`

### Deploy Steps

```bash
# 1. Log in to CF
cf login -a https://api.cf.us10.hana.ondemand.com

# 2. Build the MTA archive
mbt build

# 3. Deploy to CF
cf deploy mta_archives/CAPHanaDemoApp_1.0.0.mtar
```

### Post-Deployment — Assign Role Collection
The XSUAA service requires users to be granted the `InvoiceAdmin` role collection before they can access data:

1. BTP Cockpit → your subaccount → **Security** → **Users**
2. Click your user → **Assign Role Collection** → select **InvoiceAdmin** → Save

### Deployed URLs (trial account)
| Component    | URL                                                                                                  |
|--------------|------------------------------------------------------------------------------------------------------|
| Approuter    | `https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com`              |
| CAP Server   | `https://5b4c46e4trial-dev-caphanademoapp-srv.cfapps.us10-001.hana.ondemand.com`                    |
| App (direct) | `https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com/com.caphanademo.invoices/index.html` |

---

## Key Dependencies

| Package             | Purpose                                              |
|---------------------|------------------------------------------------------|
| `@sap/cds`          | CAP runtime (OData, CQL, event framework)            |
| `@cap-js/hana`      | HANA Cloud adapter for CAP                           |
| `@cap-js/sqlite`    | SQLite adapter for local development                 |
| `@sap/xssec`        | JWT token validation for XSUAA (BTP auth)            |
| `passport`          | HTTP auth middleware used by `@sap/xssec`            |
| `@sap/approuter`    | Application Router — OAuth2 login + request proxy    |
| `@sap/cds-dk`       | CAP Developer Kit (cds CLI, codegen) — dev only      |

---

## CDS Profiles

| Profile       | DB          | Auth     | When used                        |
|---------------|-------------|----------|----------------------------------|
| `development` | SQLite mem  | mocked   | `npm run watch` (default)        |
| `hybrid`      | HANA Cloud  | xsuaa    | `npm run watch:hybrid`           |
| `production`  | HANA Cloud  | xsuaa    | BTP deployment                   |

> **Important:** `.cdsrc.json` must NOT contain a top-level `"profiles"` key. The active profile is
> determined by `NODE_ENV` at runtime (CF buildpack sets `NODE_ENV=production` automatically).
> Hardcoding `"profiles": ["development"]` would force SQLite + mocked auth even on BTP.

---

## Architecture (BTP)

```
Browser
  │
  ▼
Approuter (CAPHanaDemoApp-approuter)
  │  xs-app.json → all traffic proxied to srv-api destination
  │  XSUAA OAuth2 login/callback handled here
  │
  ▼
CAP Server (CAPHanaDemoApp-srv)
  │  Serves Fiori Elements UI from app/com.caphanademo.invoices/
  │  Serves OData V4 at /invoice
  │  Validates JWT from XSUAA
  │
  ▼
HANA Cloud HDI Container (CAPHanaDemoApp-db)
  │  Tables: invoice.Invoice, invoice.InvoiceToItem
  │  Views: InvoiceService.Invoices, InvoiceService.InvoiceItems
```

---

## XSUAA Configuration Notes (`xs-security.json`)

- `xsappname` in `xs-security.json` is `CAPHanaDemoApp` (base name).
  The MTA substitutes it to `CAPHanaDemoApp-${org}-${space}` at deploy time.
- `oauth2-configuration.redirect-uris` must include the Approuter URL pattern.
  Currently set to `https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com/**`.
- If the Approuter URL changes (new space/org), update `redirect-uris` and run:
  ```bash
  cf update-service CAPHanaDemoApp-auth -c '{"xsappname":"CAPHanaDemoApp-<org>-<space>","oauth2-configuration":{...}}'
  cf restage CAPHanaDemoApp-approuter
  cf restage CAPHanaDemoApp-srv
  ```

---

## Conventions

- **Entity namespace**: `invoice` (prefix for all DB artefacts)
- **CSV seed files**: named `<namespace>-<EntityName>.csv` in `db/data/`
- **Service path**: `/invoice` (OData V4)
- **Handler file**: same name as the service CDS file (`invoice-service.js`)
- **Logging**: use `cds.log('invoice-service')` — never `console.log` in production code
- **Error codes**: 400 for validation, 404 for not-found
- **UI static files**: copied to `gen/srv/app/` by `scripts/copy-app.js` at MTA build time
