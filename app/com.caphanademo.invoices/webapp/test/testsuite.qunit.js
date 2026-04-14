sap.ui.define(function () {
	"use strict";

	return {
		name: "QUnit test suite for the UI5 Application: com.caphanademo.invoices",
		defaults: {
			page: "ui5://test-resources/com/caphanademo/invoices/Test.qunit.html?testsuite={suite}&test={name}",
			qunit: {
				version: 2
			},
			sinon: {
				version: 1
			},
			ui5: {
				language: "EN",
				theme: "sap_horizon"
			},
			coverage: {
				only: "com/caphanademo/invoices/",
				never: "test-resources/com/caphanademo/invoices/"
			},
			loader: {
				paths: {
					"com/caphanademo/invoices": "../"
				}
			}
		},
		tests: {
			"unit/unitTests": {
				title: "Unit tests for com.caphanademo.invoices"
			},
			"integration/opaTests": {
				title: "Integration tests for com.caphanademo.invoices"
			}
		}
	};
});
