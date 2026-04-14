# CAPHanaDemoApp — Invoice Management

A full-stack **SAP CAP + SAPUI5 Fiori Elements** application for Invoice Management, deployed on **SAP BTP Cloud Foundry** with **SAP HANA Cloud** as the database.

---

## Features

- **Invoice lifecycle management** — create, view, edit, and delete invoices with line items
- **Automatic calculations** — item amounts, tax, and invoice totals computed server-side
- **Status actions** — mark invoices as Paid or Cancelled via OData bound actions
- **Fiori Elements UI** — List Report + Object Page with draft support, search, and filters
- **BTP-native security** — XSUAA OAuth2 authentication via SAP Approuter
- **HANA Cloud persistence** — HDI container with hdbtable/hdbview artefacts

---

## Architecture

```
Browser
  │
  ▼
SAP Approuter               (OAuth2 login, request proxy)
  │
  ▼
CAP Node.js Server          (OData V4 /invoice, static UI files)
  │
  ▼
SAP HANA Cloud HDI          (invoice.Invoice, invoice.InvoiceToItem)
```

**BTP Services used:**
| Service         | Plan          | Purpose                     |
|-----------------|---------------|-----------------------------|
| `hana`          | `hdi-shared`  | HDI container for DB schema |
| `xsuaa`         | `application` | OAuth2 authentication       |

---

## Project Structure

```
CAPHanaDemoApp/
├── db/                          # CDS data model + CSV seed data
├── srv/                         # OData service definition + handlers
├── app/com.caphanademo.invoices/ # SAPUI5 Fiori Elements webapp
├── approuter/                   # SAP Approuter config (xs-app.json)
├── scripts/copy-app.js          # Build helper: copies UI into gen/srv/app/
├── mta.yaml                     # MTA deployment descriptor
├── xs-security.json             # XSUAA roles and redirect URIs
├── .cdsrc.json                  # CDS profiles (development/hybrid/production)
└── package.json
```

---

## Local Development

### Prerequisites

- Node.js >= 18
- `npm install -g @sap/cds-dk`

### Run locally (SQLite in-memory — no HANA needed)

```bash
npm install
npm run watch
```

App runs at: http://localhost:4004

The Fiori Elements UI is available at: http://localhost:4004/com.caphanademo.invoices/index.html

### OData endpoint

```
http://localhost:4004/invoice
```

Example requests:

```bash
# List invoices
GET http://localhost:4004/invoice/Invoices

# Get invoice with items
GET http://localhost:4004/invoice/Invoices('<ID>')?$expand=items

# Invoice summary by status
GET http://localhost:4004/invoice/getInvoiceSummary()
```

### Hybrid mode (local server + remote HANA Cloud)

```bash
cf login -a https://api.cf.us10.hana.ondemand.com
npx cds bind --to CAPHanaDemoApp-db
npm run watch:hybrid
```

---

## BTP Deployment

### Prerequisites

- SAP BTP trial account with Cloud Foundry enabled
- SAP HANA Cloud instance **started** (Running) in HANA Cloud Central
- Tools installed:
  - [CF CLI](https://docs.cloudfoundry.org/cf-cli/)
  - MTA Build Tool: `npm install -g mbt`
  - MultiApps CF plugin: `cf install-plugin multiapps`

### Deploy

```bash
# Login
cf login -a https://api.cf.us10.hana.ondemand.com

# Build MTA archive
mbt build

# Deploy (creates/updates all services and apps)
cf deploy mta_archives/CAPHanaDemoApp_1.0.0.mtar
```

### After deployment — assign role

Before accessing the app, assign the `InvoiceAdmin` role collection to your BTP user:

**BTP Cockpit → Subaccount → Security → Users → [your user] → Assign Role Collection → InvoiceAdmin**

### Access the app

```
https://<org>-<space>-caphanademoapp-approuter.cfapps.<region>.hana.ondemand.com/com.caphanademo.invoices/index.html
```

---

## Data Model

### Invoice (Header)

| Field         | Type          | Description                         |
|---------------|---------------|-------------------------------------|
| invoiceNumber | String(20)    | Auto-generated: `INV-YYYY-NNNN`     |
| customerName  | String(100)   |                                     |
| customerEmail | String(200)   |                                     |
| invoiceDate   | Date          |                                     |
| dueDate       | Date          |                                     |
| totalAmount   | Decimal(15,2) | Sum of all item net amounts         |
| currency      | String(3)     | Default: USD                        |
| status        | String(20)    | OPEN / PENDING / PAID / CANCELLED   |

### Invoice Item (Line Item)

| Field       | Type          | Description                          |
|-------------|---------------|--------------------------------------|
| description | String(200)   |                                      |
| quantity    | Decimal(10,2) |                                      |
| unitPrice   | Decimal(15,2) |                                      |
| amount      | Decimal(15,2) | quantity × unitPrice (auto-computed) |
| taxRate     | Decimal(5,2)  | Default: 0                           |
| taxAmount   | Decimal(15,2) | amount × taxRate / 100 (auto)        |
| netAmount   | Decimal(15,2) | amount + taxAmount (auto)            |

---

## Security

Roles defined in `xs-security.json`:

| Role Collection | Scope              | Access          |
|-----------------|--------------------|-----------------|
| `InvoiceAdmin`  | `$XSAPPNAME.admin` | Full CRUD       |
| `InvoiceViewer` | `$XSAPPNAME.viewer`| Read-only       |

---

## Key Dependencies

| Package           | Purpose                                   |
|-------------------|-------------------------------------------|
| `@sap/cds`        | CAP runtime — OData, CQL, event framework |
| `@cap-js/hana`    | HANA Cloud database adapter               |
| `@cap-js/sqlite`  | SQLite adapter for local development      |
| `@sap/approuter`  | OAuth2 login + request proxy for BTP      |
| `@sap/xssec`      | JWT validation for XSUAA                  |

---

## License

Apache 2.0
