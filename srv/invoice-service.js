"use strict";

const cds = require("@sap/cds");
const LOG = cds.log("invoice-service");

/**
 * Custom handler for InvoiceService.
 *
 * Implements:
 *  - Auto-generation of invoice numbers on CREATE
 *  - Amount / net-amount computation for line items
 *  - Invoice total recalculation after item changes
 *  - Bound actions: markAsPaid, cancelInvoice
 *  - Unbound action:  recalculateInvoiceTotal
 *  - Unbound function: getInvoiceSummary
 */
module.exports = class InvoiceService extends cds.ApplicationService {
  async init() {
    const { Invoices, InvoiceItems } = this.entities;

    // ── BEFORE handlers ───────────────────────────────────────────────────────

    /**
     * Before CREATE Invoice:
     *  - Auto-generate invoiceNumber if missing (INV-YYYY-NNNN)
     *  - Set default status to OPEN
     *  - Initialise totalAmount to 0
     */
    this.before("CREATE", Invoices, async (req) => {
      const data = req.data;

      if (!data.invoiceNumber) {
        const year = new Date().getFullYear();
        // Count existing invoices this year to generate the next sequence
        const rows = await SELECT.from(Invoices)
          .columns("count(*) as cnt")
          .where(`invoiceNumber like 'INV-${year}-%'`);

        const seq = String((rows[0]?.cnt ?? 0) + 1).padStart(4, "0");
        data.invoiceNumber = `INV-${year}-${seq}`;
        LOG.info(`Auto-generated invoiceNumber: ${data.invoiceNumber}`);
      }

      if (!data.status) data.status = "OPEN";
      if (data.totalAmount == null) data.totalAmount = 0;
    });

    /**
     * Before CREATE / UPDATE InvoiceToItem:
     *  - Compute amount = quantity × unitPrice (if not explicitly set)
     *  - Validate that amount matches quantity × unitPrice (tolerance 0.01)
     *  - Compute taxAmount = amount × taxRate / 100
     *  - Compute netAmount = amount + taxAmount
     */
    this.before(["CREATE", "UPDATE"], InvoiceItems, (req) => {
      const { quantity, unitPrice, amount, taxRate } = req.data;

      if (quantity != null && unitPrice != null) {
        const expectedAmount = Math.round(quantity * unitPrice * 100) / 100;

        if (amount != null && Math.abs(amount - expectedAmount) > 0.01) {
          return req.error(
            400,
            `Amount (${amount}) does not match quantity × unitPrice = ${expectedAmount}.`,
          );
        }
        req.data.amount = expectedAmount;

        const rate = taxRate ?? 0;
        const taxAmt = Math.round(expectedAmount * rate) / 100;
        req.data.taxAmount = taxAmt;
        req.data.netAmount = Math.round((expectedAmount + taxAmt) * 100) / 100;
      }
    });

    // ── AFTER handlers ────────────────────────────────────────────────────────

    /**
     * After CREATE / UPDATE / DELETE on InvoiceItems:
     * Recalculate the parent Invoice's totalAmount.
     */
    this.after(["CREATE", "UPDATE", "DELETE"], InvoiceItems, async (_, req) => {
      const invoiceID = req.data?.invoice_ID ?? req.data?.invoice?.ID;
      if (!invoiceID) return;

      await this._syncInvoiceTotal(invoiceID);
    });

    // ── BOUND ACTIONS on Invoices ─────────────────────────────────────────────

    /**
     * POST /invoice/Invoices(ID)/markAsPaid
     * Sets the invoice status to PAID.
     */
    this.on("markAsPaid", Invoices, async (req) => {
      const { ID } = req.params[0];

      const invoice = await SELECT.one.from(Invoices, ID);
      if (!invoice) return req.error(404, `Invoice '${ID}' not found.`);
      if (invoice.status === "PAID")
        return req.error(
          400,
          `Invoice '${invoice.invoiceNumber}' is already PAID.`,
        );
      if (invoice.status === "CANCELLED")
        return req.error(
          400,
          `Invoice '${invoice.invoiceNumber}' is CANCELLED and cannot be paid.`,
        );

      await UPDATE(Invoices, ID).set({ status: "PAID" });
      LOG.info(`Invoice ${invoice.invoiceNumber} marked as PAID`);

      return {
        message: `Invoice '${invoice.invoiceNumber}' successfully marked as PAID.`,
      };
    });

    /**
     * POST /invoice/Invoices(ID)/cancelInvoice
     * Cancels the invoice with an optional reason stored in notes.
     */
    this.on("cancelInvoice", Invoices, async (req) => {
      const { ID } = req.params[0];
      const { reason } = req.data;

      const invoice = await SELECT.one.from(Invoices, ID);
      if (!invoice) return req.error(404, `Invoice '${ID}' not found.`);
      if (invoice.status === "CANCELLED")
        return req.error(
          400,
          `Invoice '${invoice.invoiceNumber}' is already CANCELLED.`,
        );
      if (invoice.status === "PAID")
        return req.error(
          400,
          `Invoice '${invoice.invoiceNumber}' is PAID and cannot be cancelled.`,
        );

      const notes = reason ? `Cancelled: ${reason}` : "Cancelled by user.";

      await UPDATE(Invoices, ID).set({ status: "CANCELLED", notes });
      LOG.info(
        `Invoice ${invoice.invoiceNumber} cancelled. Reason: ${reason ?? "n/a"}`,
      );

      return {
        message: `Invoice '${invoice.invoiceNumber}' successfully CANCELLED.`,
      };
    });

    // ── UNBOUND ACTIONS & FUNCTIONS ───────────────────────────────────────────

    /**
     * GET /invoice/getInvoiceSummary()
     * Returns aggregated invoice counts and totals grouped by status.
     */
    this.on("getInvoiceSummary", async (req) => {
      const rows = await SELECT.from(Invoices)
        .columns(
          "status",
          "count(*) as count",
          "sum(totalAmount) as totalAmount",
          "currency",
        )
        .groupBy("status", "currency")
        .orderBy("status");

      LOG.info(
        `Invoice summary requested. ${rows.length} status groups returned.`,
      );
      return rows;
    });

    /**
     * POST /invoice/recalculateInvoiceTotal
     * Recalculates and persists the totalAmount for the given invoice.
     */
    this.on("recalculateInvoiceTotal", async (req) => {
      const { invoiceID } = req.data;

      const invoice = await SELECT.one.from(Invoices, invoiceID);
      if (!invoice) return req.error(404, `Invoice '${invoiceID}' not found.`);

      const { totalAmount, itemCount } =
        await this._syncInvoiceTotal(invoiceID);

      return { invoiceID, totalAmount, itemCount };
    });

    return super.init();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /**
   * Sums all item amounts for the given invoiceID, updates the Invoice record,
   * and returns { totalAmount, itemCount }.
   * @param {string} invoiceID
   */
  async _syncInvoiceTotal(invoiceID) {
    const { InvoiceItems, Invoices } = this.entities;

    const items = await SELECT.from(InvoiceItems)
      .columns("amount")
      .where({ invoice_ID: invoiceID });

    const itemCount = items.length;
    const totalAmount =
      Math.round(items.reduce((sum, i) => sum + (i.amount ?? 0), 0) * 100) /
      100;

    await UPDATE(Invoices, invoiceID).set({ totalAmount });
    LOG.debug(
      `Synced total for Invoice ${invoiceID}: ${totalAmount} (${itemCount} items)`,
    );

    return { totalAmount, itemCount };
  }
};
