# Invoice Management — SAPUI5 Fiori Elements App

SAPUI5 Fiori Elements frontend for the CAPHanaDemoApp Invoice Management service.

Implements a **List Report + Object Page** pattern using `sap.fe.templates`, connected to the CAP OData V4 `InvoiceService`.

---

## Tech Stack

- **SAPUI5 1.120.23** (loaded from CDN: `sapui5.hana.ondemand.com`)
- **sap.fe.templates** — Fiori Elements List Report + Object Page
- **OData V4** model bound to `/invoice` service
- **sap_horizon** theme

---

## Local Development

Run the CAP server first (from repo root):

```bash
npm run watch
```

The Fiori app is then served by the CAP server at:

```
http://localhost:4004/com.caphanademo.invoices/index.html
```

No separate UI5 tooling server is needed for development — CAP serves the static files directly.

---

## App Structure

```
webapp/
├── index.html              # SAPUI5 bootstrap (CDN, sap_horizon theme)
├── manifest.json           # App descriptor — OData model, Fiori Elements routes
├── Component.js            # UI5 root component
├── changes/
│   ├── flexibility-bundle.json   # sap.ui.fl flexibility bundle
│   └── changes-bundle.json
├── controller/
│   ├── BaseController.js
│   ├── App.controller.js
│   └── Main.controller.js
├── view/
│   ├── App.view.xml
│   └── Main.view.xml
├── model/
│   ├── formatter.js
│   └── models.js
└── i18n/
    └── i18n.properties
```

---

## OData Service

| Entity          | Endpoint                         |
|-----------------|----------------------------------|
| Invoices        | `/invoice/Invoices`              |
| Invoice Items   | `/invoice/InvoiceItems`          |

Bound actions available on Invoices:
- `markAsPaid` — sets status to PAID
- `cancelInvoice` — sets status to CANCELLED (requires reason)

---

## BTP Deployment

The webapp is **not** deployed as a standalone HTML5 Repository app. Instead, at MTA build time, `scripts/copy-app.js` copies this `webapp/` directory into `gen/srv/app/com.caphanademo.invoices/`, and the CAP server serves it as static files in production.

The SAP Approuter (`approuter/xs-app.json`) is configured with:
- `welcomeFile: /com.caphanademo.invoices/index.html`
- All traffic proxied to the CAP server destination with XSUAA auth

---

## License

Apache 2.0
