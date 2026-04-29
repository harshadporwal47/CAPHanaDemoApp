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

**Author:** Harshad Porwal
**GitHub:** https://github.com/harshadporwal47/CAPHanaDemoApp
**Deployed App:** https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com/com.caphanademo.invoices/index.html

---

## Project Structure

```
CAPHanaDemoApp/
├── db/
│   ├── schema.cds                         # CDS data model (Invoice, InvoiceToItem)
│   └── data/
│       ├── invoice-Invoice.csv            # Seed data — 5 invoices (OPEN/PAID/PENDING/CANCELLED)
│       └── invoice-InvoiceToItem.csv      # Seed data — 8 line items across 5 invoices
├── srv/
│   ├── invoice-service.cds               # OData service definition + all UI annotations
│   └── invoice-service.js                # Custom event handlers (business logic)
├── app/
│   └── com.caphanademo.invoices/
│       ├── webapp/
│       │   ├── index.html                # SAPUI5 bootstrap (CDN 1.120.23, sap_horizon theme)
│       │   ├── manifest.json             # App descriptor: OData model, Fiori Elements routing
│       │   ├── Component.js              # Extends sap/fe/core/AppComponent (Fiori Elements)
│       │   ├── changes/
│       │   │   ├── flexibility-bundle.json  # sap.ui.fl bundle — all arrays must be present
│       │   │   └── changes-bundle.json
│       │   ├── controller/
│       │   │   ├── BaseController.js     # Helpers: getRouter, getModel, navTo, onNavBack
│       │   │   ├── App.controller.js     # Root app controller
│       │   │   └── Main.controller.js    # Main view controller
│       │   ├── view/
│       │   │   ├── App.view.xml          # Root shell — contains <App id="app"/>
│       │   │   └── Main.view.xml         # Main view (Fiori Elements takes over routing)
│       │   ├── model/
│       │   │   ├── models.js             # Creates sap.ui.model.json.JSONModel (DeviceModel)
│       │   │   └── formatter.js          # Value formatters for bindings
│       │   └── i18n/
│       │       └── i18n.properties       # appTitle, appDescription
│       ├── ui5.yaml                      # UI5 tooling config — SAPUI5 1.146.0 (local dev)
│       └── package.json                  # UI5 CLI + karma test tooling dependencies
├── approuter/
│   ├── xs-app.json                       # Route config: all traffic → srv-api, XSUAA auth
│   └── package.json                      # @sap/approuter ^16
├── scripts/
│   └── copy-app.js                       # Copies webapp/ → gen/srv/app/ at MTA build time
├── gen/                                  # Build output (auto-generated, NOT in git)
├── mta.yaml                              # MTA deployment descriptor for BTP CF
├── xs-security.json                      # XSUAA scopes, roles, role-collections (no URLs)
├── package.json                          # Root dependencies, npm scripts, cds auth config
│                                         #   repository: https://github.com/harshadporwal47/CAPHanaDemoApp
│                                         #   license: Harshad Porwal
├── .cdsrc.json                           # CDS db+auth profiles; copied into gen/srv at build
├── .cdsrc-private.json                   # HANA binding credentials — NOT in git (gitignored)
├── .env.example                          # Template for local environment variables
├── default-env.json.example              # Template for HANA credentials (hybrid mode reference)
├── .gitignore
└── CLAUDE.md                             # This file
```

---

## Data Model (`db/schema.cds`)

Namespace: `invoice`

### `invoice.Invoice` (Header entity)

| Field         | Type           | Constraint      | Notes                               |
|---------------|----------------|-----------------|-------------------------------------|
| ID            | UUID (PK)      | `cuid`          | Auto-generated                      |
| invoiceNumber | String(20)     | `@mandatory`    | Auto-generated: `INV-YYYY-NNNN`     |
| customerName  | String(100)    | `@mandatory`    |                                     |
| customerEmail | String(200)    |                 |                                     |
| invoiceDate   | Date           | `@mandatory`    |                                     |
| dueDate       | Date           |                 |                                     |
| totalAmount   | Decimal(15,2)  | default 0       | Kept in sync via `_syncInvoiceTotal`|
| currency      | String(3)      | default `'USD'` |                                     |
| status        | InvoiceStatus  | `@assert.range` | OPEN / PENDING / PAID / CANCELLED   |
| notes         | String(500)    |                 |                                     |
| items         | Composition → many InvoiceToItem | | Cascade-managed |

Both entities mix in `cuid` (UUID PK) and `managed` (createdAt, createdBy, modifiedAt, modifiedBy).

### `invoice.InvoiceToItem` (Line item entity)

| Field       | Type           | Constraint   | Notes                                |
|-------------|----------------|--------------|--------------------------------------|
| ID          | UUID (PK)      | `cuid`       | Auto-generated                       |
| invoice     | Assoc → Invoice| `@mandatory` | FK: `invoice_ID`                     |
| itemNumber  | Integer        | `@mandatory` |                                      |
| description | String(200)    | `@mandatory` |                                      |
| quantity    | Decimal(10,2)  | `@mandatory` |                                      |
| unit        | String(10)     | default `'EA'`|                                     |
| unitPrice   | Decimal(15,2)  | `@mandatory` |                                      |
| amount      | Decimal(15,2)  |              | Computed: `quantity × unitPrice`     |
| taxRate     | Decimal(5,2)   | default 0    |                                      |
| taxAmount   | Decimal(15,2)  | default 0    | Computed: `amount × taxRate / 100`   |
| netAmount   | Decimal(15,2)  |              | Computed: `amount + taxAmount`       |

### Enum type
```cds
type InvoiceStatus : String(20) enum {
  OPEN; PENDING; PAID; CANCELLED;
}
```

---

## Service Layer (`srv/invoice-service.cds`)

Service path: `/invoice` (OData V4)

### Exposed entities

| Entity        | Draft | Notes                                          |
|---------------|-------|------------------------------------------------|
| `Invoices`    | ✅    | Projection on `invoice.Invoice`; has actions   |
| `InvoiceItems`| ❌    | Projection on `invoice.InvoiceToItem`          |

### Bound actions (on `Invoices`)

| Action          | Params           | Returns          | Business rule                               |
|-----------------|------------------|------------------|---------------------------------------------|
| `markAsPaid`    | —                | `{ message }`    | 400 if already PAID/CANCELLED               |
| `cancelInvoice` | `reason: String` | `{ message }`    | 400 if already CANCELLED/PAID; stores reason|

### Unbound actions & functions

| Name                      | Type     | Returns                                         |
|---------------------------|----------|-------------------------------------------------|
| `getInvoiceSummary()`     | Function | `[{ status, count, totalAmount, currency }]`    |
| `recalculateInvoiceTotal` | Action   | `{ invoiceID, totalAmount, itemCount }`         |

### UI annotations (all in `invoice-service.cds`)

| Annotation              | What it controls                                                   |
|-------------------------|--------------------------------------------------------------------|
| `UI.HeaderInfo`         | Object page header: title=invoiceNumber, subtitle=customerName     |
| `UI.LineItem`           | List Report columns: invoiceNumber, customerName, invoiceDate, dueDate, totalAmount, currency, status |
| `UI.SelectionFields`    | Filter bar: status, customerName, invoiceDate                      |
| `UI.FieldGroup#InvoiceDetails` | Object page fields: invoiceNumber through notes             |
| `UI.FieldGroup#Financial`      | Object page fields: totalAmount, currency                   |
| `UI.Facets`             | Object page sections: "General Information" (Details + Financial) + "Invoice Items" sub-table |
| `InvoiceItems UI.LineItem` | Sub-table: itemNumber, description, quantity, unit, unitPrice, amount, taxRate, netAmount |

---

## Custom Handler Logic (`srv/invoice-service.js`)

Class: `InvoiceService extends cds.ApplicationService`
Logger: `const LOG = cds.log('invoice-service')`

| Hook | Trigger | Logic |
|------|---------|-------|
| `before CREATE` | `Invoices` | Auto-generates `invoiceNumber` (`INV-YYYY-NNNN` via DB count of existing numbers that year). Sets `status='OPEN'`, `totalAmount=0` if not provided |
| `before CREATE/UPDATE` | `InvoiceItems` | Validates `amount ≈ quantity × unitPrice` (±0.01 tolerance). Computes `taxAmount = amount × taxRate / 100`. Computes `netAmount = amount + taxAmount` |
| `after CREATE/UPDATE/DELETE` | `InvoiceItems` | Calls `_syncInvoiceTotal(invoiceID)` to recalculate parent Invoice.totalAmount |
| `on markAsPaid` | `Invoices` (bound) | 404 if not found. 400 if PAID or CANCELLED. Sets `status='PAID'` |
| `on cancelInvoice` | `Invoices` (bound) | 404 if not found. 400 if CANCELLED or PAID. Sets `status='CANCELLED'`, appends reason to `notes` |
| `on getInvoiceSummary` | unbound function | `SELECT status, count(*), sum(totalAmount), currency … GROUP BY status, currency ORDER BY status` |
| `on recalculateInvoiceTotal` | unbound action | 404 if not found. Calls `_syncInvoiceTotal`. Returns `{ invoiceID, totalAmount, itemCount }` |

### Private helper
```js
async _syncInvoiceTotal(invoiceID)
  → SELECT amount FROM InvoiceItems WHERE invoice_ID = invoiceID
  → sum all amounts (rounding to 2dp)
  → UPDATE Invoices SET totalAmount = sum
  → returns { totalAmount, itemCount }
```

---

## SAPUI5 App (`app/com.caphanademo.invoices/`)

### Key design decisions

| Aspect | Value | Reason |
|--------|-------|--------|
| UI5 version (CDN/production) | 1.120.23 | Stable LTS; used in `index.html` bootstrap |
| UI5 version (local dev tooling) | 1.146.0 | Declared in `ui5.yaml`; used by `cds-plugin-ui5` |
| Theme | `sap_horizon` | SAP's current design system |
| App component base | `sap/fe/core/AppComponent` | Required for Fiori Elements templates |
| OData model key | `""` (default) | Standard Fiori Elements pattern |
| `operationMode` | `Server` | Sorting/filtering on server, not client |
| `variantManagement` | `None` | No personalisation variants |
| Draft enabled | `Invoices` only | `InvoiceItems` are managed via composition |

### `manifest.json` routing

| Route pattern | Target | Template |
|---|---|---|
| `:?query:` | `InvoicesList` | `sap.fe.templates.ListReport` |
| `Invoices({key}):?query:` | `InvoicesObjectPage` | `sap.fe.templates.ObjectPage` |

### `flexibility-bundle.json` — required structure
```json
{
  "changes": [], "compVariants": [], "variants": [],
  "variantChanges": [], "variantDependentControlChanges": [],
  "variantManagementChanges": [], "ui2personalization": {}
}
```
All keys must be present or `sap.ui.fl` will throw `concat() on undefined` at runtime.

---

## Configuration Architecture

### Priority chain (highest → lowest)

```
.cdsrc-private.json       ← HANA binding credentials (git-ignored, created by cds bind)
      ↑ overrides
.cdsrc.json               ← DB + auth per profile; copied to gen/srv/ at build time
      ↑ overrides
package.json  (cds: {})   ← Mocked auth users for development + hybrid
```

### `.cdsrc.json`

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
      "[hybrid]":     { "kind": "mocked" }
    }
  },
  "build": {
    "target": "gen",
    "tasks": [
      { "for": "hana",   "src": "db",  "options": { "model": ["db","srv"] } },
      { "for": "nodejs", "src": "srv" }
    ]
  },
  "hana": { "deploy-format": "hdbtable" }
}
```

> ⚠️ **Critical:** never add `"profiles": ["development"]` at the top level.
> It hardcodes SQLite even on BTP where `NODE_ENV=production`.

### `package.json` cds section

```json
"cds": {
  "requires": {
    "auth": {
      "[production]":  { "kind": "xsuaa" },
      "[development]": { "kind": "mocked" },
      "[hybrid]":      { "kind": "mocked" }
    }
  }
}
```

Note: `.cdsrc.json` takes priority over `package.json`. Both agree that `hybrid` auth = `mocked`.

---

## Local Development

### Option 1 — SQLite in-memory (no BTP needed)

```bash
npm install
npm run watch
```

| | |
|---|---|
| URL | http://localhost:4004 |
| UI | http://localhost:4004/com.caphanademo.invoices/index.html |
| DB | SQLite in-memory, auto-seeded from `db/data/*.csv` |
| Auth | Mocked — no login; all users allowed (`"*": true`) |
| UI5 | 1.146.0 via `cds-plugin-ui5` (local tooling) |

### Option 2 — Hybrid mode (local server + HANA Cloud)

**One-time setup** (only if `.cdsrc-private.json` is missing or credentials are stale):
```bash
cf login -a https://api.cf.us10.hana.ondemand.com
npx cds bind --to CAPHanaDemoApp-db
```
Creates `.cdsrc-private.json` with the HDI container credentials under `[hybrid]` profile key.

**Start:**
```bash
npm run watch:hybrid    # = cds watch --profile hybrid
```

| | |
|---|---|
| URL | http://localhost:4004 |
| UI | http://localhost:4004/com.caphanademo.invoices/index.html |
| DB | **SAP HANA Cloud** (prod data, persisted) |
| Auth | Mocked — no login prompt locally |
| UI5 | 1.146.0 via `cds-plugin-ui5` (local tooling) |
| Requires | HANA Cloud instance must be **Running** in BTP Cockpit |

**Startup log that confirms correct config:**
```
bound db to cf managed service CAPHanaDemoApp-db:CAPHanaDemoApp-db-key
connect to db > hana { host: '....hanacloud.ondemand.com', port: '443', ... }
using auth strategy { kind: 'mocked' }
server listening on { url: 'http://localhost:4004' }
```

---

## BTP Deployment

### Prerequisites
- SAP BTP trial account with Cloud Foundry enabled
- SAP HANA Cloud instance **started** in BTP Cockpit
- `cf` CLI, `mbt` (`npm install -g mbt`), MultiApps CF plugin

### Deploy steps

```bash
cf login -a https://api.cf.us10.hana.ondemand.com
mbt build
cf deploy mta_archives/CAPHanaDemoApp_1.0.0.mtar
```

MTA `before-all` steps (in order):
1. `npm install --production=false`
2. `npx cds build --production` → produces `gen/srv/` and `gen/db/`
3. `node scripts/copy-app.js` → copies `app/.../webapp/` → `gen/srv/app/`

### Assign role (post-deploy, one time)
BTP Cockpit → Security → Users → [your user] → Assign Role Collection → **InvoiceAdmin**

### Deployed URLs (trial)

| Component | URL |
|---|---|
| Approuter | `https://5b4c46e4trial-dev-caphanademoapp-approuter.cfapps.us10-001.hana.ondemand.com` |
| CAP Server | `https://5b4c46e4trial-dev-caphanademoapp-srv.cfapps.us10-001.hana.ondemand.com` |
| Fiori App | `…approuter…/com.caphanademo.invoices/index.html` |

---

## Architecture (BTP CF)

```
Browser
  │
  ▼
Approuter  (xs-app.json: all routes → srv-api destination, XSUAA enforced)
  │        (welcomeFile: /com.caphanademo.invoices/index.html)
  │
  ▼
CAP Server (gen/srv)
  │  Static UI: gen/srv/app/com.caphanademo.invoices/
  │  OData V4:  /invoice
  │  Auth:      JWT validation via @sap/xssec + passport
  │
  ▼
HANA Cloud HDI Container (CAPHanaDemoApp-db)
  Tables: invoice.Invoice, invoice.InvoiceToItem
  Views:  InvoiceService.Invoices, InvoiceService.InvoiceItems
  Drafts: InvoiceService.Invoices_drafts, InvoiceService.InvoiceItems_drafts
```

---

## XSUAA Configuration

`xs-security.json` is environment-agnostic (no hardcoded URLs). Dynamic values injected by MTA at deploy time via `mta.yaml` `config:` block:

```yaml
config:
  xsappname: CAPHanaDemoApp-${org}-${space}
  tenant-mode: dedicated
  oauth2-configuration:
    redirect-uris:
      - "https://${org}-${space}-caphanademoapp-approuter.${default-domain}/**"
```

MTA variables used:

| Variable | Example value |
|---|---|
| `${org}` | `5b4c46e4trial` |
| `${space}` | `dev` |
| `${default-domain}` | `cfapps.us10-001.hana.ondemand.com` |

This means deploying to a different space/org/region requires **no file changes**.

---

## Key Dependencies

| Package | Where | Purpose |
|---|---|---|
| `@sap/cds` | production | CAP runtime — OData, CQL, event framework |
| `@cap-js/hana` | production | HANA Cloud database adapter |
| `@sap/xssec` | production | XSUAA JWT validation |
| `passport` | production | HTTP auth middleware (used by xssec) |
| `express` | production | HTTP server (CAP uses it internally) |
| `@cap-js/sqlite` | dev | SQLite adapter for local dev |
| `@sap/cds-dk` | dev | CDS CLI — `cds watch`, `cds build`, `cds bind` |
| `cds-plugin-ui5` | dev | Serves `app/` via CAP dev server with live reload |
| `@sap/approuter` | approuter | OAuth2 login + reverse proxy (BTP only) |
| `@ui5/cli` | app/dev | UI5 tooling for standalone build/test |

---

## CDS Profiles Summary

| Profile | DB | Auth | Activated by |
|---|---|---|---|
| `development` | SQLite `:memory:` | mocked | `npm run watch` (NODE_ENV unset) |
| `hybrid` | HANA Cloud | mocked | `npm run watch:hybrid` |
| `production` | HANA Cloud | xsuaa | BTP CF (`NODE_ENV=production`) |

---

## Conventions

- **Namespace**: `invoice` — prefix for all DB tables/views/artefacts
- **CSV seed files**: `db/data/<namespace>-<EntityName>.csv`
- **Service path**: `/invoice` (OData V4)
- **Handler file**: matches service CDS name — `invoice-service.js`
- **Logging**: always use `LOG.info/debug/warn/error` from `cds.log('invoice-service')`; never `console.log` in production code
- **Error codes**: `400` for business rule violations, `404` for missing records
- **Draft**: enabled on `Invoices` only; `InvoiceItems` managed through composition
- **UI5 CDN version** (production): `1.120.23` in `index.html`
- **UI5 tooling version** (local): `1.146.0` in `ui5.yaml` / used by `cds-plugin-ui5`
