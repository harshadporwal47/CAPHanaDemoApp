/* global QUnit */
sap.ui.define(["sap/ui/test/opaQunit", "./pages/Main"], function (opaTest) {
	"use strict";

	QUnit.module("Sample Data Journey");

	opaTest("Should display the data table", function (Given, When, Then) {
		// Arrangements
		Given.iStartMyUIComponent({
			componentConfig: {
				name: "com.caphanademo.invoices"
			}
		});

		// Assertions
		Then.onTheMainPage.iShouldSeeTheDataTable();
		Then.onTheMainPage.iShouldSeeTheDetailForm();
		Then.onTheMainPage.iShouldSeeTableWithCorrectColumns();

		// Cleanup
		Then.iTeardownMyApp();
	});

	opaTest("Should select table row and populate detail form", function (Given, When, Then) {
		// Arrangements
		Given.iStartMyUIComponent({
			componentConfig: {
				name: "com.caphanademo.invoices"
			}
		});

		// Actions
		When.onTheMainPage.iSelectFirstTableRow();

		// Assertions
		Then.onTheMainPage.iShouldSeeTheDetailForm();

		// Cleanup
		Then.iTeardownMyApp();
	});
});
