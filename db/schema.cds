namespace invoice;

using {
  cuid,
  managed
} from '@sap/cds/common';

// Enum type for invoice status — used for validation via @assert.range
type InvoiceStatus : String(20) enum {
  OPEN = 'OPEN';
  PENDING = 'PENDING';
  PAID = 'PAID';
  CANCELLED = 'CANCELLED';
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice Header Entity
// ─────────────────────────────────────────────────────────────────────────────
entity Invoice : cuid, managed {
  invoiceNumber       : String(20)  @mandatory;
  customerName        : String(100) @mandatory;
  customerEmail       : String(200);
  invoiceDate         : Date        @mandatory;
  dueDate             : Date;
  totalAmount         : Decimal(15, 2) default 0;
  currency            : String(3) default 'USD';

  @assert.range
  status              : InvoiceStatus default 'OPEN';
  notes               : String(500);
  // Composition: one Invoice has many InvoiceToItems
  items               : Composition of many InvoiceToItem
                          on items.invoice = $self;
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice Line Item Entity
// ─────────────────────────────────────────────────────────────────────────────
entity InvoiceToItem : cuid, managed {
  // Association back to Invoice header
  invoice     : Association to Invoice @mandatory;
  itemNumber  : Integer                @mandatory;
  description : String(200)            @mandatory;
  quantity    : Decimal(10, 2)         @mandatory;
  unit        : String(10) default 'EA';
  unitPrice   : Decimal(15, 2)         @mandatory;
  amount      : Decimal(15, 2); // Computed: quantity × unitPrice
  taxRate     : Decimal(5, 2) default 0;
  taxAmount   : Decimal(15, 2) default 0;
  netAmount   : Decimal(15, 2); // Computed: amount + taxAmount
}
