--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local lpeg = require("lpeg")

local util = require("json.decode.util")
local merge = require("json.util").merge

local tonumber = tonumber
local unpack = unpack
local print = print
local tostring = tostring

local rawset = rawset

module("json.decode.object")

-- BEGIN LPEG < 0.9 SUPPORT
local initObject, applyObjectKey
if not (lpeg.Cg and lpeg.Cf and lpeg.Ct) then
	function initObject()
		return {}
	end
	function applyObjectKey(tab, key, val)
		tab[key] = val
		return tab
	end
end
-- END LPEG < 0.9 SUPPORT

local defaultOptions = {
	number = true,
	identifier = true,
	trailingComma = true
}

default = nil -- Let the buildCapture optimization take place

strict = {
	number = false,
	identifier = false,
	trailingComma = false
}

local function buildItemSequence(objectItem, ignored)
	return (objectItem * (ignored * lpeg.P(",") * ignored * objectItem)^0) + 0
end

local function buildCapture(options, global_options)
	local ignored = global_options.ignored
	local string_type = lpeg.V(util.types.STRING)
	local integer_type = lpeg.V(util.types.INTEGER)
	local value_type = lpeg.V(util.types.VALUE)
	options = options and merge({}, defaultOptions, options) or defaultOptions
	local key = string_type
	if options.identifier then
		key = key + lpeg.C(util.identifier)
	else
		key = key + #lpeg.C(util.identifier) * util.denied("identifier key", "object.identifier")
	end
	if options.number then
		key = key + integer_type
	else
		key = key + #integer_type * util.denied("numeric key", "object.number")
	end
	local objectItems
	local objectItem = key * ignored * (lpeg.P(":") + util.expected(":")) * ignored * (value_type + util.expected("value"))
	-- BEGIN LPEG < 0.9 SUPPORT
	if not (lpeg.Cg and lpeg.Cf and lpeg.Ct) then
		local set_key = applyObjectKey
		if options.setObjectKey then
			local setObjectKey = options.setObjectKey
			set_key = function(tab, key, val)
				setObjectKey(tab, key, val)
				return tab
			end
		end

		objectItems = buildItemSequence(objectItem / set_key, ignored)
		objectItems = lpeg.Ca(lpeg.Cc(false) / initObject * objectItems)
	-- END LPEG < 0.9 SUPPORT
	else
		objectItems = buildItemSequence(lpeg.Cg(objectItem), ignored)
		objectItems = lpeg.Cf(lpeg.Ct(0) * objectItems, options.setObjectKey or rawset)
	end


	local capture = lpeg.P("{") * ignored
	capture = capture * objectItems * ignored
	if options.trailingComma then
		capture = capture * (lpeg.P(",") + 0) * ignored
	else
		capture = capture * ((#(lpeg.P(",") * ignored * lpeg.P("}"))) * util.denied("Trailing comma", "object.trailingComma") + 0) * ignored
	end
	-- Detect completion
	local completion = lpeg.P("}")
	-- Detect early termination
	completion = completion + -1 * util.expected("}")
	-- Detect unexpected ':' or ';' at end
	completion = completion + #lpeg.S(':;') * util.unexpected()
	-- Detect other invalid character
	completion = completion + util.expected("}", "value")
	capture = capture * completion
	return capture
end

function register_types()
	util.register_type("OBJECT")
end

function load_types(options, global_options, grammar)
	local capture = buildCapture(options, global_options)
	local object_id = util.types.OBJECT
	grammar[object_id] = capture
	util.append_grammar_item(grammar, "VALUE", lpeg.V(object_id))
end
