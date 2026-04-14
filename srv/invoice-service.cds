using invoice as inv from '../db/schema';

// ─────────────────────────────────────────────────────────────────────────────
// Invoice OData Service
// Exposed at: /odata/v4/invoice
// ─────────────────────────────────────────────────────────────────────────────
service InvoiceService @(path: '/invoice') {

  // ── Entities ────────────────────────────────────────────────────────────────

  @odata.draft.enabled
  entity Invoices as projection on inv.Invoice
    actions {
      // Bound action: mark a single invoice as paid
      action markAsPaid() returns { message : String };

      // Bound action: cancel an invoice
      action cancelInvoice(reason : String) returns { message : String };
    };

  entity InvoiceItems as projection on inv.InvoiceToItem;

  // ── Unbound Actions & Functions ─────────────────────────────────────────────

  // Returns a summary report for all invoices grouped by status
  function getInvoiceSummary() returns array of {
    status       : String;
    count        : Integer;
    totalAmount  : Decimal(15,2);
    currency     : String;
  };

  // Recalculates totals for a given invoice (summing up all line items)
  action recalculateInvoiceTotal(invoiceID : UUID) returns {
    invoiceID   : UUID;
    totalAmount : Decimal(15,2);
    itemCount   : Integer;
  };
}

// ── Annotations ─────────────────────────────────────────────────────────────

annotate InvoiceService.Invoices with @(

  // ── List Report: header card and table columns ───────────────────────────
  UI.HeaderInfo: {
    TypeName      : 'Invoice',
    TypeNamePlural: 'Invoices',
    Title         : { Value: invoiceNumber },
    Description   : { Value: customerName }
  },

  UI.LineItem: [
    { Value: invoiceNumber, Label: 'Invoice #'  },
    { Value: customerName,  Label: 'Customer'   },
    { Value: invoiceDate,   Label: 'Date'        },
    { Value: dueDate,       Label: 'Due Date'    },
    { Value: totalAmount,   Label: 'Total'       },
    { Value: currency,      Label: 'Currency'    },
    { Value: status,        Label: 'Status'      }
  ],

  // ── List Report: filter bar fields ──────────────────────────────────────
  UI.SelectionFields: [ status, customerName, invoiceDate ],

  // ── Object Page: field groups (sections of form fields) ─────────────────
  UI.FieldGroup#InvoiceDetails: {
    $Type: 'UI.FieldGroupType',
    Data : [
      { Value: invoiceNumber, Label: 'Invoice Number' },
      { Value: customerName,  Label: 'Customer Name'  },
      { Value: customerEmail, Label: 'Email'           },
      { Value: invoiceDate,   Label: 'Invoice Date'    },
      { Value: dueDate,       Label: 'Due Date'        },
      { Value: status,        Label: 'Status'          },
      { Value: notes,         Label: 'Notes'           }
    ]
  },

  UI.FieldGroup#Financial: {
    $Type: 'UI.FieldGroupType',
    Data : [
      { Value: totalAmount, Label: 'Total Amount' },
      { Value: currency,    Label: 'Currency'     }
    ]
  },

  // ── Object Page: section layout ──────────────────────────────────────────
  UI.Facets: [
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

annotate InvoiceService.InvoiceItems with @(
  UI.LineItem: [
    { Value: itemNumber,  Label: 'Item #'      },
    { Value: description, Label: 'Description' },
    { Value: quantity,    Label: 'Qty'         },
    { Value: unit,        Label: 'Unit'        },
    { Value: unitPrice,   Label: 'Unit Price'  },
    { Value: amount,      Label: 'Amount'      },
    { Value: taxRate,     Label: 'Tax %'       },
    { Value: netAmount,   Label: 'Net Amount'  }
  ]
);
