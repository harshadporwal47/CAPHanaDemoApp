sap.ui.define(
	["sap/ui/core/mvc/ControllerExtension"],
	function (ControllerExtension) {
		"use strict";

		// Stable Fiori Elements IDs for the Object Page header buttons
		const EDIT_BTN_ID = "fe::StandardAction::Edit";
		const DELETE_BTN_ID = "fe::StandardAction::Delete";

		return ControllerExtension.extend(
			"com.caphanademo.invoices.controller.ObjectPageExtension",
			{
				override: {
					/**
					 * onInit: attach two hooks
					 *  1. modelContextChange — fires when FE navigates to a different
					 *     entity (binding context path changes)
					 *  2. onAfterRendering delegate — fires after the page renders;
					 *     catches the initial load where the context is already set
					 */
					onInit: function () {
						const oView = this.base.getView();

						oView.attachModelContextChange(this._applyVisibility.bind(this));

						oView.addEventDelegate({
							onAfterRendering: this._applyVisibility.bind(this),
						});
					},
				},

				// ── Private ─────────────────────────────────────────────────────────────

				/**
				 * Reads the current binding context's status and hides/shows
				 * the Edit and Delete buttons accordingly.
				 * Called both on initial render and on navigation between entities.
				 */
				_applyVisibility: function () {
					const oView = this.base.getView();
					const oContext = oView.getBindingContext();
					if (!oContext) {
						return;
					}

					// Skip for brand-new unsaved entities (Create flow)
					if (
						typeof oContext.isTransient === "function" &&
						oContext.isTransient()
					) {
						return;
					}

					oContext
						.requestObject()
						.then(function (oObject) {
							if (!oObject) {
								return;
							}

							const bIsActive = oObject.IsActiveEntity !== false;
							if (!bIsActive) {
								return;
							}

							const bIsPaid = oObject.status === "PAID";

							setTimeout(function () {
								const oEditBtn = oView.byId(EDIT_BTN_ID);
								const oDeleteBtn = oView.byId(DELETE_BTN_ID);
								if (oEditBtn) {
									oEditBtn.setVisible(!bIsPaid);
								}
								if (oDeleteBtn) {
									oDeleteBtn.setVisible(!bIsPaid);
								}
							}, 0);
						})
						.catch(function () {
							// Silently ignore — context may be destroyed or entity not yet ready
						});
				},
			},
		);
	},
);
