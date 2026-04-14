sap.ui.define(["sap/ui/test/Opa5"], function (Opa5) {
	"use strict";

	Opa5.createPageObjects({
		onTheMainPage: {
			actions: {
				iSelectFirstTableRow: function () {
					return this.waitFor({
						controlType: "sap.ui.table.Table",
						viewName: "com.caphanademo.invoices.view.Main",
						actions: function (oTable) {
							// Select the first row if available
							if (oTable.getRows().length > 0) {
								oTable.setSelectedIndex(0);
								oTable.fireRowSelectionChange({
									rowIndex: 0,
									rowContext: oTable.getRows()[0].getBindingContext(),
									userInteraction: true
								});
							}
						},
						errorMessage: "Did not find the data table"
					});
				}
			},

			assertions: {
				iShouldSeeTheDataTable: function () {
					return this.waitFor({
						controlType: "sap.ui.table.Table",
						viewName: "com.caphanademo.invoices.view.Main",
						success: function (aTables) {
							Opa5.assert.ok(aTables.length > 0, "The data table is displayed");
						},
						errorMessage: "Did not find the data table"
					});
				},

				iShouldSeeTheDetailForm: function () {
					return this.waitFor({
						id: "detailForm",
						viewName: "com.caphanademo.invoices.view.Main",
						success: function (oForm) {
							Opa5.assert.ok(oForm, "The detail form is displayed");
						},
						errorMessage: "Did not find the detail form"
					});
				},

				iShouldSeeTableWithCorrectColumns: function () {
					return this.waitFor({
						controlType: "sap.ui.table.Table",
						viewName: "com.caphanademo.invoices.view.Main",
						success: function (aTables) {
							const oTable = aTables[0];
							const aColumns = oTable.getColumns();
							const expectedColumns = [];
							
							Opa5.assert.equal(aColumns.length, expectedColumns.length, "Table has the correct number of columns");
							
							for (let i = 0; i < expectedColumns.length; i++) {
								const sColumnText = aColumns[i].getLabel().getText();
								Opa5.assert.equal(sColumnText, expectedColumns[i], "Column " + i + " has correct label: " + expectedColumns[i]);
							}
						},
						errorMessage: "Table columns do not match expected properties"
					});
				}
			}
		}
	});
});
