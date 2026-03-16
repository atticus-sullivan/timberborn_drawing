--- Timberborn TikZ graph generator.
--
-- This module is used from LuaLaTeX to generate TikZ code describing
-- production graphs for the game *Timberborn*. The module reads a JSON
-- description of buildings ("huts"), their input/output resources, and
-- their production duration. From this it computes resource flow rates
-- and prints the corresponding TikZ nodes and edges.

-- The module is intended to be used through `\directlua` calls in LaTeX.

local function pr(...)
	tex.print(...)
	-- print(...)
end

-----------
-- UTILS --
-----------

--- Return the keys of a table.
-- @tparam table t table to extract keys from
-- @treturn table list of keys
local function getKeys(t)
	local keys={}
	for key,_ in pairs(t) do
		table.insert(keys, key)
	end
	return keys
end

--- Check whether any element satisfies a predicate.
--
-- @tparam table ls list
-- @tparam function pred predicate
-- @treturn boolean
local function any(ls, pred)
	for _, l in ipairs(ls) do
		if pred(l) then
			return true
		end
	end
	return false
end

--- Duration broken into components.
-- Produced by @{parseDur}.
--
-- @table Duration
-- @field days number days
-- @field hours number hours
-- @field mins number minutes
-- @field secs number seconds

--- Parse a duration string.
--
-- Supported format is a concatenation of
--
-- * `d` - days
-- * `h` - hours
-- * `m` - minutes
-- * `s` - seconds
--
-- Example: `"1d2h30m"`
--
-- @tparam string s duration string
-- @treturn Duration parsed duration
local function parseDur(s)
	local days  = s:gsub('d.*', '')
	local hours = s:gsub('.*%f[^d]', ''):gsub('%f[h].*', '')
	local mins  = s:gsub('.*%f[^h]', ''):gsub('%f[m].*', '')
	local secs  = s:gsub('.*%f[^m]', ''):gsub('%f[s].*', '')
	return {
		days  = tonumber(days) or 0,
		hours = tonumber(hours) or 0,
		mins  = tonumber(mins) or 0,
		secs  = tonumber(secs) or 0,
	}
end

local function durInMin(s)
	local x = parseDur(s)
	return
		x.days * 24*60 +
		x.hours * 60 +
		x.mins +
		x.secs / 60
end
-- local function dur_in_hour(s)
-- 	return dur_in_min(s) / 60
-- end


------------
-- MODULE --
------------

-- @module timberborndrawing
local _M = {}


--- Reference to a resource used by a hut.
--
-- @table ResourceRef
-- @field name string normalized resource name (internal node id)
-- @field cnt number amount of the resource used/produced


--- Representation of a production building.
--
-- Loaded from the JSON input file.
--
-- @table Hut
-- @field cnt number number of buildings
-- @field dur string production duration string (e.g. `"1h30m"`)
-- @field durMin number duration in minutes
-- @field durUnit string unit used for displaying rates
-- @field i ResourceRef[] input resources
-- @field o ResourceRef[] output resources
-- @field recipe string|nil optional recipe identifier

--- Loaded huts indexed by hut name.
-- @type table<string,Hut>
local huts = {}


--- Representation of a resource node in the graph.
--
-- A resource connects huts that produce and consume it.
--
-- @table Resource
-- @field name string display name of the resource
-- @field huts string[] list of huts using the resource
-- @field underline boolean whether the label should be underlined
-- @field node string additional TikZ node options
-- @field hide_empty_io boolean whether empty IO should be hidden

--- Loaded resources indexed by normalized resource name.
-- @type table<string,Resource>
local resources = {}

--- Reset internal state.
--
-- Clears all loaded huts and resources. This must be called before
-- loading a new JSON description.
--
-- @function reset
function _M.reset()
	huts = {}
	resources = {}
end

--- Register the usage of a resource.
--
-- Internal helper that connects a resource to a hut and records
-- the input/output count.
--
-- @tparam string res resource name
-- @tparam number cnt amount of resource
-- @tparam string h_name hut name
-- @tparam ResourceRef[] dict input/output list
-- @tparam[opt=false] boolean hide_empty_io mark resource as optional
local function addRes(res, cnt, h_name, dict, hide_empty_io)
	local norm_name = res.."-r"
	table.insert(dict, {name=norm_name, cnt=cnt})
	if not resources[norm_name] then
		resources[norm_name] = {name=res, huts={}, underline=false, node="", hide_empty_io=hide_empty_io}
	end
	table.insert(resources[norm_name].huts, h_name)
end

local json = require "json"

--- Load a JSON description of huts.
--
-- The JSON file must contain an array of hut objects.
--
-- Example structure:
--
-- ```json
-- [
--   {
--     "name": "Lumber Mill",
--     "cnt": 2,
--     "dur": "1h",
--     "inputs": {"log": 1},
--     "outputs": {"plank": 1}
--   }
-- ]
-- ```
--
-- @tparam string path path to the JSON file
-- @function loadJSON
function _M.loadJSON(path)
	local f = assert(io.open(path, "r"))
	local content = f:read("*a")
	f:close()
	local data = json.decode(content)

	for _, h in ipairs(data) do
		local h_name = string.gsub(h.name or "", "%.", "-")
		-- build hut entry
		local x = {
			cnt = h.cnt or 0,
			dur = h.dur or "0s",
			durMin = durInMin(h.dur or "0s"),
			durUnit = "1h",
			i = {},
			o = {},
			recipe = h.recipe
		}

		-- add inputs
		for res, cnt in pairs(h.inputs or {}) do
			if res == "anyOf" then
				for res, cnt in pairs(cnt) do
					addRes(res, cnt, h_name, x.i, true)
				end
			else
				addRes(res, cnt, h_name, x.i)
			end
		end

		-- add outputs
		for res, cnt in pairs(h.outputs or {}) do
			if res == "anyOf" then
				for res, cnt in pairs(cnt) do
					addRes(res, cnt, h_name, x.o, true)
				end
			else
				addRes(res, cnt, h_name, x.o)
			end
		end

		-- insert to huts
		huts[h_name] = x
	end
end

--- Resource flow rates.
--
-- Returned by @{getResRate}.
--
-- @table Rate
-- @field i number production rate
-- @field o number consumption rate
-- @field left number net production (`i - o`)


--- Compute the production/consumption rate of a resource.
--
-- @tparam string self resource identifier
-- @tparam string[] hs huts using the resource
-- @tparam string durUnit target duration unit
-- @treturn Rate
local function getResRate(self, hs, durUnit)
	local res = {i=0, o=0}
	for _, h in pairs(hs) do
		-- collect producer rate
		for _, r in ipairs(huts[h].o) do
			if r.name == self then
				res.i = res.i + (r.cnt * huts[h].cnt / (huts[h].durMin / durInMin(durUnit or "1h")))
			end
		end
		-- collect consumer rate
		for _, r in ipairs(huts[h].i) do
			if r.name == self then
				res.o = res.o + (r.cnt * huts[h].cnt / (huts[h].durMin / durInMin(durUnit or "1h")))
			end
		end
	end
	res.left = res.i - res.o
	return res
end

--- Draw resource nodes.
--
-- Internal helper used by @{drawAll}.
--
-- @tparam table<string,boolean> nodes set of already drawn nodes (mostly output argument)
local function drawResourceNodes(nodes)
	local rs = getKeys(resources)
	table.sort(rs)
	for _,name in ipairs(rs) do
		local r = resources[name]
		if r.huts and any(r.huts, function(x) return huts[x].cnt > 0 end) then
			local rates = getResRate(name, r.huts, "1h")
			if not (rates.i == 0 and rates.o == 0) then
				local stateKey
				if rates.left < 0 then
					stateKey = "/timberborndrawing/resource/neg"
				else
					stateKey = "/timberborndrawing/resource/pos"
				end
				pr(
					([[\node[/timberborndrawing/resource/node,%s,%s] (%s) {%s (in $\frac{%.2f}{\text{%s}}$ / out $\frac{%.2f}{\text{%s}}$ $\to$ left $\frac{%.2f}{\text{%s}}$)};]]):format(
						stateKey,
						r.node,
						name,
						r.underline and ([[\underline{%s}]]):format(r.name) or r.name,
						rates.i, "1h",
						rates.o, "1h",
						rates.left, "1h"
				))
				nodes[name] = true
			end
		end
	end
end


--- Draw the complete production graph.
--
-- Generates TikZ nodes and edges for all loaded huts and resources.
--
-- @tparam boolean showCnt if true, show building multiplicity in rate formulas
-- @function drawAll
function _M.drawAll(showCnt)
	local nodes = {}
	drawResourceNodes(nodes)

	local hs = getKeys(huts)
	table.sort(hs)
	for _,name in ipairs(hs) do
		local h = huts[name]
		if h.recipe then
			name = name.."-"..h.recipe
		end
		if h.cnt <= 0 and showCnt then
			goto continue_huts
		end
		pr(
			([[\node [/timberborndrawing/hut/node] (%s) {%s};]]):format(
				name,
				name
		))
		nodes[name] = true
		for _,r in ipairs(h.i) do
			if nodes[r.name] and nodes[name] then
				pr(
					([[\path (%s) edge[/timberborndrawing/every edge, /timberborndrawing/edgeIn] node[align=left,] {$\frac{%s}{\text{%s}} =$\\[.75ex]$\frac{%.2f}{\text{%s}}$} (%s);]]):format(
						r.name,
						showCnt and ([[%.2f \times %.2f]]):format(r.cnt, h.cnt) or ([[%d]]):format(r.cnt), h.dur,
						(showCnt and h.cnt or 1) * r.cnt / (h.durMin / durInMin(h.durUnit)) ,
						h.durUnit,
						name
					)
				)
			end
		end
		for _,r in ipairs(h.o) do
			if nodes[r.name] and nodes[name] then
				pr(
					([[\path (%s) edge[/timberborndrawing/every edge, /timberborndrawing/edgeOut] node[align=left,] {$\frac{%s}{\text{%s}} =$\\[.75ex]$\frac{%.2f}{\text{%s}}$} (%s);]]):format(
						name,
						showCnt and ([[%.2f \times %.2f]]):format(r.cnt, h.cnt) or ([[%d]]):format(r.cnt), h.dur,
						(showCnt and h.cnt or 1) * r.cnt / (h.durMin / durInMin(h.durUnit)) ,
						h.durUnit,
						r.name
					)
				)
			end
		end
		::continue_huts::
	end
end

return _M
