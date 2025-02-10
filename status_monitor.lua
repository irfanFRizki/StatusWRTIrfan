module("luci.controller.status_monitor", package.seeall)

function index()
    entry({"admin", "services", "status_monitor"}, template("status_monitor"), _("Status Monitor"), 100).dependent=false
end
