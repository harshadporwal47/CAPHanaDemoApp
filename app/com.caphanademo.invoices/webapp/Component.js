sap.ui.define(["sap/fe/core/AppComponent"], function (AppComponent) {
	"use strict";

	return AppComponent.extend("com.caphanademo.invoices.Component", {
		metadata: {
			manifest: "json",
			interfaces: ["sap.ui.core.IAsyncContentCreation"]
		}
	});
});
