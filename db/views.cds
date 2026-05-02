namespace invoice;

using { invoice.Invoice, invoice.InvoiceToItem } from './schema';

// ═════════════════════════════════════════════════════════════════════════════
// CDS VIEW EXAMPLES
//
// A CDS view is defined with:   entity Foo as SELECT from Bar { ... }
//   → In HANA   : compiled to an hdbview artifact (real SQL VIEW in the DB)
//   → In SQLite : compiled to a SQL VIEW inside the SQLite file
//   → Read-only : no INSERT/UPDATE/DELETE — views have no table of their own
//
// All four examples below build on the existing Invoice / InvoiceToItem tables.
// ═════════════════════════════════════════════════════════════════════════════


// ─────────────────────────────────────────────────────────────────────────────
// VIEW 1 — Simple Projection
//
// Concept : SELECT a SUBSET of columns from a table.
//           Use this to hide internal/managed fields and expose only what
//           consumers need. Same idea as a SQL view trimming a wide table.
//
// SQL equivalent (HANA):
//   CREATE VIEW INVOICEOVERVIEW AS
//   SELECT ID, INVOICENUMBER, CUSTOMERNAME, INVOICEDATE,
//          DUEDATE, TOTALAMOUNT, CURRENCY, STATUS
//   FROM INVOICE_INVOICE
//
// Notice: createdAt, createdBy, modifiedAt, modifiedBy, notes — all hidden.
// ─────────────────────────────────────────────────────────────────────────────
entity InvoiceOverview as SELECT from Invoice {
    key ID,
        invoiceNumber,
        customerName,
        invoiceDate,
        dueDate,
        totalAmount,
        currency,
        status
};


// ─────────────────────────────────────────────────────────────────────────────
// VIEW 2 — Computed Column + WHERE Filter
//
// Concept : Add a DERIVED/COMPUTED column using a SQL expression.
//           Also apply a WHERE clause so the view pre-filters rows.
//
// New column : daysOverdue — how many days ago was the due date?
//              Positive  → invoice is overdue (due date already passed)
//              Negative  → due date is still in the future
//              Zero      → due today
//
// SQL equivalent (HANA):
//   CREATE VIEW OVERDUEINVOICEVIEW AS
//   SELECT ID, INVOICENUMBER, CUSTOMERNAME, DUEDATE, TOTALAMOUNT,
//          CURRENCY, STATUS,
//          DAYS_BETWEEN(DUEDATE, CURRENT_DATE) AS DAYSOVERDUE
//   FROM INVOICE_INVOICE
//   WHERE STATUS IN ('OPEN', 'PENDING')
//
// Note: days_between() is a HANA built-in function.
//       It is NOT available in SQLite (development mode). This view
//       will only work in hybrid or production profile (HANA).
// ─────────────────────────────────────────────────────────────────────────────
entity OverdueInvoiceView as SELECT from Invoice {
    key ID,
        invoiceNumber,
        customerName,
        dueDate,
        totalAmount,
        currency,
        status,
        days_between(dueDate, current_date) as daysOverdue : Integer
} where status in ('OPEN', 'PENDING');


// ─────────────────────────────────────────────────────────────────────────────
// VIEW 3 — Aggregation (GROUP BY)
//
// Concept : Collapse many rows into grouped summary rows using aggregate
//           functions: COUNT(), SUM(), AVG(), etc.
//           Like a pivot table in Excel — one row per customer + currency.
//
// Key design : There is no single-column primary key in this view.
//              We use a COMPOSITE KEY: (customerName + currency).
//              OData access looks like:
//              GET /invoice/CustomerSummary(customerName='Acme',currency='USD')
//
// SQL equivalent (HANA):
//   CREATE VIEW CUSTOMERINVOICESUMMARY AS
//   SELECT
//     CUSTOMERNAME,  CURRENCY,
//     COUNT(ID)                                             AS INVOICECOUNT,
//     SUM(TOTALAMOUNT)                                      AS TOTALBILLED,
//     SUM(CASE WHEN STATUS='OPEN'    THEN TOTALAMOUNT END)  AS OPENAMOUNT,
//     SUM(CASE WHEN STATUS='PAID'    THEN TOTALAMOUNT END)  AS PAIDAMOUNT,
//     COUNT(CASE WHEN STATUS='OPEN'    THEN 1 END)          AS OPENCOUNT,
//     COUNT(CASE WHEN STATUS='PENDING' THEN 1 END)          AS PENDINGCOUNT,
//     COUNT(CASE WHEN STATUS='PAID'    THEN 1 END)          AS PAIDCOUNT
//   FROM INVOICE_INVOICE
//   GROUP BY CUSTOMERNAME, CURRENCY
// ─────────────────────────────────────────────────────────────────────────────
entity CustomerInvoiceSummary as SELECT from Invoice {
    key customerName,
    key currency,
        count(ID)                                                as invoiceCount : Integer,
        sum(totalAmount)                                         as totalBilled  : Decimal(15,2),
        sum(case when status = 'OPEN'    then totalAmount end)   as openAmount   : Decimal(15,2),
        sum(case when status = 'PAID'    then totalAmount end)   as paidAmount   : Decimal(15,2),
        count(case when status = 'OPEN'    then 1 end)           as openCount    : Integer,
        count(case when status = 'PENDING' then 1 end)           as pendingCount : Integer,
        count(case when status = 'PAID'    then 1 end)           as paidCount    : Integer
} group by customerName, currency;


// ─────────────────────────────────────────────────────────────────────────────
// VIEW 4 — JOIN View
//
// Concept : COMBINE data from TWO tables into one flat row.
//           InvoiceToItem only stores the invoice_ID (FK), not the header
//           fields. This view joins them so every item row also carries
//           the parent invoice's number, customer name, and status.
//
// Useful for : flat reports, exports, analytical queries where you need
//              both line-item detail and invoice header in one shot.
//
// SQL equivalent (HANA):
//   CREATE VIEW INVOICEITEMDETAILVIEW AS
//   SELECT
//     item.ID, inv.INVOICENUMBER, inv.CUSTOMERNAME, inv.STATUS AS INVOICESTATUS,
//     item.ITEMNUMBER, item.DESCRIPTION, item.QUANTITY, item.UNIT,
//     item.UNITPRICE, item.AMOUNT, item.TAXRATE, item.TAXAMOUNT, item.NETAMOUNT
//   FROM INVOICE_INVOICETOITEM AS item
//   JOIN INVOICE_INVOICE AS inv ON inv.ID = item.INVOICE_ID   ← SQL column name
//   (In CDS we write: item.invoice.ID  — navigating through the association)
// ─────────────────────────────────────────────────────────────────────────────
entity InvoiceItemDetailView as SELECT from InvoiceToItem as item
    join Invoice as inv on inv.ID = item.invoice.ID {
    key item.ID,
        inv.invoiceNumber,
        inv.customerName,
        inv.status       as invoiceStatus : String(20),
        item.itemNumber,
        item.description,
        item.quantity,
        item.unit,
        item.unitPrice,
        item.amount,
        item.taxRate,
        item.taxAmount,
        item.netAmount
};
