module("luci.controller.online", package.seeall)

function index()
    entry({"admin", "services", "online"}, template("online"), "Online", 99)
end