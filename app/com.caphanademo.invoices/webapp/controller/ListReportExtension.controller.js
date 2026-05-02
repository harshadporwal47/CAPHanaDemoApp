sap.ui.define([
    "sap/ui/core/mvc/ControllerExtension"
], function (ControllerExtension) {
    "use strict";

    // ─── Stable Fiori Elements IDs ──────────────────────────────────────────────
    const TABLE_ID      = "fe::table::Invoices::LineItem";
    const DELETE_BTN_ID = "com.caphanademo.invoices::InvoicesList--fe::table::Invoices::LineItem::StandardAction::Delete";

    return ControllerExtension.extend(
        "com.caphanademo.invoices.controller.ListReportExtension", {

        override: {
            /**
             * Called after the List Report view is rendered.
             * We attach our selection-change listener here because the table
             * control only exists in the DOM after rendering.
             * detach + attach prevents duplicate listeners on re-renders.
             */
            onAfterRendering: function () {
                const oTable = this.base.getView().byId(TABLE_ID);
                if (!oTable) { return; }

                oTable.detachSelectionChange(this._onSelectionChange, this);
                oTable.attachSelectionChange(this._onSelectionChange, this);
            }
        },

        // ── Private ─────────────────────────────────────────────────────────────

        /**
         * Fired whenever the table selection changes.
         * Hides the Delete button if ANY selected invoice is PAID;
         * shows it again once no PAID invoices remain in the selection.
         */
        _onSelectionChange: function () {
            const oView      = this.base.getView();
            const oTable     = oView.byId(TABLE_ID);
            const oDeleteBtn = oView.byId(DELETE_BTN_ID);

            if (!oTable || !oDeleteBtn) { return; }

            const aContexts = oTable.getSelectedContexts();

            // If nothing is selected, restore the button to visible
            // (FE handles the enabled/disabled state for empty selection itself)
            const bHasPaid = aContexts.some(
                ctx => ctx.getObject()?.status === "PAID"
            );

            oDeleteBtn.setVisible(!bHasPaid);
        }
    });
});