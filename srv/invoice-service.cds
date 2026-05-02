using invoice as inv from '../db/schema';
using {
  invoice.CustomerInvoiceSummary,
  invoice.OverdueInvoiceView,
  invoice.InvoiceItemDetailView
} from '../db/views';

// ─────────────────────────────────────────────────────────────────────────────
// Invoice OData Service
// Exposed at: /odata/v4/invoice
// ─────────────────────────────────────────────────────────────────────────────
service InvoiceService @(path: '/invoice') {

  // ── Entities ────────────────────────────────────────────────────────────────

  // @cds.redirection.target: true  — tells CDS that when multiple entities in
  // this service project onto invoice.Invoice, THIS is the canonical one that
  // associations (e.g. InvoiceItems:invoice) should resolve/navigate to.
  @odata.draft.enabled
  @cds.redirection.target: true
  entity Invoices          as projection on inv.Invoice
    actions {
      // Bound action: mark a single invoice as paid
      action markAsPaid()                  returns {
        message : String
      };

      // Bound action: cancel an invoice
      action cancelInvoice(reason: String) returns {
        message : String
      };
    };

  entity InvoiceItems      as projection on inv.InvoiceToItem;

  // ── CDS View Entities (read-only) ───────────────────────────────────────────

  // VIEW 3 — Aggregation: one row per customer+currency with invoice totals
  // OData: GET /invoice/CustomerSummary
  //        GET /invoice/CustomerSummary(customerName='Acme Corp',currency='USD')
  @readonly
  entity CustomerSummary   as projection on CustomerInvoiceSummary;

  // VIEW 2 — Filter + Computed column: only OPEN/PENDING + daysOverdue field
  // OData: GET /invoice/OverdueInvoices
  //        GET /invoice/OverdueInvoices?$orderby=daysOverdue desc
  @readonly
  entity OverdueInvoices   as projection on OverdueInvoiceView;

  // VIEW 4 — JOIN: flat view of line items enriched with parent invoice fields
  // OData: GET /invoice/ItemDetails
  //        GET /invoice/ItemDetails?$filter=invoiceStatus eq 'OPEN'
  @readonly
  entity ItemDetails       as projection on InvoiceItemDetailView;

  @readonly
  entity CustomerValueHelp as
    projection on inv.Invoice {
      key ID,
          customerName,
          customerEmail
    };

  // ── Unbound Actions & Functions ─────────────────────────────────────────────

  // Returns a summary report for all invoices grouped by status
  function getInvoiceSummary()                      returns array of {
    status      : String;
    count       : Integer;
    totalAmount : Decimal(15, 2);
    currency    : String;
  };

  // Recalculates totals for a given invoice (summing up all line items)
  action   recalculateInvoiceTotal(invoiceID: UUID) returns {
    invoiceID   : UUID;
    totalAmount : Decimal(15, 2);
    itemCount   : Integer;
  };
}

// ── Annotations ─────────────────────────────────────────────────────────────

annotate InvoiceService.Invoices with @(

  // ── List Report: header card and table columns ───────────────────────────
  UI.HeaderInfo                : {
    TypeName      : 'Invoice',
    TypeNamePlural: 'Invoices',
    Title         : {Value: invoiceNumber},
    Description   : {Value: customerName}
  },

  UI.LineItem                  : [
    {
      Value: invoiceNumber,
      Label: 'Invoice #'
    },
    {
      Value: customerName,
      Label: 'Customer'
    },
    {
      Value: customerEmail,
      Label: 'Email'
    },
    {
      Value: invoiceDate,
      Label: 'Creation Date'
    },
    {
      Value: dueDate,
      Label: 'Due Date'
    },
    {
      Value: totalAmount,
      Label: 'Total'
    },
    {
      Value: currency,
      Label: 'Currency'
    },
    {
      Value: status,
      Label: 'Status'
    }
  ],

  // ── List Report: filter bar fields ──────────────────────────────────────
  UI.SelectionFields           : [
    status,
    customerName,
    invoiceDate
  ],

  // ── Object Page: field groups (sections of form fields) ─────────────────
  UI.FieldGroup #InvoiceDetails: {
    $Type: 'UI.FieldGroupType',
    Data : [
      {
        Value: invoiceNumber,
        Label: 'Invoice Number'
      },
      {
        Value: customerName,
        Label: 'Customer Name'
      },
      {
        Value: customerEmail,
        Label: 'Email'
      },
      {
        Value: invoiceDate,
        Label: 'Invoice Date'
      },
      {
        Value: dueDate,
        Label: 'Due Date'
      },
      {
        Value: status,
        Label: 'Status'
      },
      {
        Value: notes,
        Label: 'Notes'
      }
    ]
  },

  UI.FieldGroup #Financial     : {
    $Type: 'UI.FieldGroupType',
    Data : [
      {
        Value: totalAmount,
        Label: 'Total Amount'
      },
      {
        Value: currency,
        Label: 'Currency'
      }
    ]
  },

  // ── Object Page: section layout ──────────────────────────────────────────
  UI.Facets                    : [
    {
      $Type : 'UI.CollectionFacet',
      Label : 'General Information',
      ID    : 'GeneralSection',
      Facets: [
        {
          $Type : 'UI.ReferenceFacet',
          Label : 'Invoice Details',
          ID    : 'InvoiceDetails',
          Target: '@UI.FieldGroup#InvoiceDetails'
        },
        {
          $Type : 'UI.ReferenceFacet',
          Label : 'Financial',
          ID    : 'Financial',
          Target: '@UI.FieldGroup#Financial'
        }
      ]
    },
    {
      $Type : 'UI.ReferenceFacet',
      Label : 'Invoice Items',
      ID    : 'ItemsSection',
      Target: 'items/@UI.LineItem'
    }
  ]
);

annotate InvoiceService.InvoiceItems with @(UI.LineItem: [
  {
    Value: itemNumber,
    Label: 'Item #'
  },
  {
    Value: description,
    Label: 'Description'
  },
  {
    Value: quantity,
    Label: 'Qty'
  },
  {
    Value: unit,
    Label: 'Unit'
  },
  {
    Value: unitPrice,
    Label: 'Unit Price'
  },
  {
    Value: amount,
    Label: 'Amount'
  },
  {
    Value: taxRate,
    Label: 'Tax %'
  },
  {
    Value: netAmount,
    Label: 'Net Amount'
  }
]);

annotate InvoiceService.Invoices with {
  status @(
    title                          : 'Status',
    Common.ValueListWithFixedValues: true,
    Common.ValueList               : {
      CollectionPath: 'Invoices',
      Parameters    : [{
        $Type            : 'Common.ValueListParameterOut',
        LocalDataProperty: status,
        ValueListProperty: 'status'
      }]
    }
  );
}

annotate InvoiceService.Invoices with {
  customerName @(
    title           : 'Customer',
    Common.ValueList: {
      CollectionPath: 'CustomerValueHelp',
      Parameters    : [
        {
          $Type            : 'Common.ValueListParameterOut',
          LocalDataProperty: customerName,
          ValueListProperty: 'customerName'
        },
        {
          $Type            : 'Common.ValueListParameterDisplayOnly',
          ValueListProperty: 'customerEmail'
        }
      ]
    }
  );
}

annotate InvoiceService.CustomerValueHelp with {
  customerName  @title: 'Customer';
  customerEmail @title: 'Email';
}

annotate InvoiceService.CustomerValueHelp with @(UI.SelectionFields: []);

annotate InvoiceService.Invoices with @(Capabilities.FilterRestrictions: {FilterExpressionRestrictions: [{
  Property          : invoiceDate,
  AllowedExpressions: 'SingleRange'
}]});

annotate InvoiceService.Invoices with {
  invoiceDate @title: 'Invoice Date';
}
