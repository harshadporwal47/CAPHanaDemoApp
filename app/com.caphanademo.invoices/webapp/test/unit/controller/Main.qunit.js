/* global QUnit */
sap.ui.define(["com/caphanademo/invoices/controller/Main.controller"], function (MainController) {
	"use strict";

	QUnit.module("Sample Main controller test");

	QUnit.test("The MainController class has a onRowSelectionChange method", function (assert) {
		// as a very basic test example just check the presence of the "onRowSelectionChange" method
		assert.strictEqual(typeof MainController.prototype.onRowSelectionChange, "function");
	});
});
