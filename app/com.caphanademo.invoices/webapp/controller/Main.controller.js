sap.ui.define(["./BaseController"], function (BaseController) {
	"use strict";

	return BaseController.extend("com.caphanademo.invoices.controller.Main", {

		onRowSelectionChange: function(oEvent) {
			const selectedContext = oEvent.getParameter("rowContext");
			this.byId("detailForm").setBindingContext(selectedContext);
		}
	});
});
