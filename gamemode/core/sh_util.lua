
--- Various useful helper functions.
-- @module ix.util

-- Includes a file from the prefix.
function ix.util.Include(fileName, state)
	if (!fileName) then
		error("[Helix] No file name specified for including.")
	end

	-- Only include server-side if we're on the server.
	if ((state == "server" or fileName:find("sv_")) and SERVER) then
		include(fileName)
	-- Shared is included by both server and client.
	elseif (state == "shared" or fileName:find("shared.lua") or fileName:find("sh_")) then
		if (SERVER) then
			-- Send the file to the client if shared so they can run it.
			AddCSLuaFile(fileName)
		end

		include(fileName)
	-- File is sent to client, included on client.
	elseif (state == "client" or fileName:find("cl_")) then
		if (SERVER) then
			AddCSLuaFile(fileName)
		else
			include(fileName)
		end
	end
end

-- Include files based off the prefix within a directory.
function ix.util.IncludeDir(directory, fromLua)
	-- By default, we include relatively to Helix.
	local baseDir = "helix"

	-- If we're in a schema, include relative to the schema.
	if (Schema and Schema.folder and Schema.loading) then
		baseDir = Schema.folder.."/schema/"
	else
		baseDir = baseDir.."/gamemode/"
	end

	-- Find all of the files within the directory.
	for _, v in ipairs(file.Find((fromLua and "" or baseDir)..directory.."/*.lua", "LUA")) do
		-- Include the file from the prefix.
		ix.util.Include(directory.."/"..v)
	end
end

--- Removes the realm prefix from a file name. The returned string will be unchanged if there is no prefix found.
-- @shared
-- @string name String to strip prefix from
-- @treturn string String stripped of prefix
-- @usage print(ix.util.StripRealmPrefix("sv_init.lua"))
-- > init.lua
function ix.util.StripRealmPrefix(name)
	local prefix = name:sub(1, 3)

	return (prefix == "sh_" or prefix == "sv_" or prefix == "cl_") and name:sub(4) or name
end

--- Sanitizes an input value with the given type. This function ensures that a valid type is always returned. If a valid value
-- could not be found, it will return the default value for the type. This only works for simple types - e.g it does not work
-- for player, character, or Steam ID types.
-- @shared
-- @ixtype type Type to check for
-- @param input Value to sanitize
-- @return Sanitized value
-- @see ix.type
-- @usage print(ix.util.SanitizeType(ix.type.number, "123"))
-- > 123
-- print(ix.util.SanitizeType(ix.type.bool, 1))
-- > true
function ix.util.SanitizeType(type, input)
	if (type == ix.type.string) then
		return tostring(input)
	elseif (type == ix.type.text) then
		return tostring(input)
	elseif (type == ix.type.number) then
		return tonumber(input or 0) or 0
	elseif (type == ix.type.bool) then
		return tobool(input)
	elseif (type == ix.type.color) then
		-- avoid creating another color table if possible
		return (istable(input) and isnumber(input.a) and isnumber(input.g) and isnumber(input.b)) and input or (
			istable(input) and
			Color(tonumber(input.a) or 255, tonumber(input.g) or 255, tonumber(input.b) or 255, tonumber(input.a) or 255) or
			color_white
		)
	elseif (type == ix.type.vector) then
		return isvector(input) and input or vector_origin
	else
		error("attempted to sanitize " .. (ix.type[type] and ("invalid type " .. ix.type[type]) or "unknown type " .. type))
	end
end

-- Returns the address:port of the server.
function ix.util.GetAddress()
	local address = tonumber(GetConVarString("hostip"))

	if (!address) then
		return "127.0.0.1"..":"..GetConVarString("hostport")
	end

	local ip = {}
		ip[1] = bit.rshift(bit.band(address, 0xFF000000), 24)
		ip[2] = bit.rshift(bit.band(address, 0x00FF0000), 16)
		ip[3] = bit.rshift(bit.band(address, 0x0000FF00), 8)
		ip[4] = bit.band(address, 0x000000FF)
	return table.concat(ip, ".")..":"..GetConVarString("hostport")
end

-- Returns a table of admin players
function ix.util.GetAdmins(isSuper)
	local admins = {}

	for _, v in ipairs(player.GetAll()) do
		if (isSuper) then
			if (v:IsSuperAdmin()) then
				table.insert(admins, v)
			end
		else
			if (v:IsAdmin()) then
				table.insert(admins, v)
			end
		end
	end

	return admins
end

-- Returns a single cached copy of a material or creates it if it doesn't exist.
function ix.util.GetMaterial(materialPath)
	-- Cache the material.
	ix.util.cachedMaterials = ix.util.cachedMaterials or {}
	ix.util.cachedMaterials[materialPath] = ix.util.cachedMaterials[materialPath] or Material(materialPath)

	return ix.util.cachedMaterials[materialPath]
end

--- Attempts to find a player by matching their name or Steam ID.
-- @shared
-- @string identifier Search query
-- @bool[opt=false] bAllowPatterns Whether or not to accept Lua patterns in `identifier`
-- @treturn player Player that matches the given search query - this will be `nil` if a player could not be found
function ix.util.FindPlayer(identifier, bAllowPatterns)
	if (string.find(identifier, "STEAM_(%d+):(%d+):(%d+)")) then
		return player.GetBySteamID(identifier)
	end

	if (!bAllowPatterns) then
		identifier = string.PatternSafe(identifier)
	end

	for _, v in ipairs(player.GetAll()) do
		if (ix.util.StringMatches(v:Name(), identifier)) then
			return v
		end
	end
end

-- Returns whether or a not a string matches.
function ix.util.StringMatches(a, b)
	if (a and b) then
		local a2, b2 = a:lower(), b:lower()

		-- Check if the actual letters match.
		if (a == b) then return true end
		if (a2 == b2) then return true end

		-- Be less strict and search.
		if (a:find(b)) then return true end
		if (a2:find(b2)) then return true end
	end

	return false
end

-- Returns a string that has the items in the format string replaced with the input.
-- You can also pass in a table with regular indices to replace them in order
-- Example: ix.util.FormatStringNamed("Hello, my name is {name}.", {name = "Bobby"})
function ix.util.FormatStringNamed(format, ...)
	local arguments = {...}
	local bArray = false -- Whether or not the input has numerical indices or named ones
	local input

	-- If the first argument is a table, we can assumed it's going to specify which
	-- keys to fill out. Otherwise we'll fill in specified arguments in order.
	if (type(arguments[1]) == "table") then
		input = arguments[1]
	else
		input = arguments
		bArray = true
	end

	local i = 0
	local result = format:gsub("{(%w-)}", function(word)
		i = i + 1
		return tostring((bArray and input[i] or input[word]) or word)
	end)

	return result
end

--- Returns a string that is the given input with spaces in between each CamelCase word. This function will ignore any words
-- that do not begin with a capital letter.
-- @shared
-- @string input String to expand
-- @bool[opt=false] bNoUpperFirst Whether or not to avoid capitalizing the first character. This is useful for lowerCamelCase
-- @treturn string Expanded CamelCase string
-- @usage print(ix.util.ExpandCamelCase("HelloWorld"))
-- > Hello World
function ix.util.ExpandCamelCase(input, bNoUpperFirst)
	input = bNoUpperFirst and input or input:sub(1, 1):upper() .. input:sub(2)

	-- extra parentheses to select first return value of gsub
	return string.TrimRight((input:gsub("%u%l+", "%1 ")))
end

function ix.util.GridVector(vec, gridSize)
	if (gridSize <= 0) then
		gridSize = 1
	end

	for i = 1, 3 do
		vec[i] = vec[i] / gridSize
		vec[i] = math.Round(vec[i])
		vec[i] = vec[i] * gridSize
	end

	return vec
end

do
	local i
	local value
	local character

	local function iterator(table)
		repeat
			i = i + 1
			value = table[i]
			character = value and value:GetCharacter()
		until character or value == nil

		return value, character
	end

	--- Returns an iterator for characters. The resulting key/values will be a player and their corresponding characters. This
	-- iterator skips over any players that do not have a valid character loaded.
	-- @shared
	-- @treturn Iterator
	-- @usage for client, character in ix.util.GetCharacters() do
	-- 		print(client, character)
	-- end
	-- > Player [1][Bot01]    character[1]
	-- > Player [2][Bot02]    character[2]
	-- -- etc.
	function ix.util.GetCharacters()
		i = 0
		return iterator, player.GetAll()
	end
end

function ix.util.GetAllChar()
	local charTable = {}

	for _, v in ipairs(player.GetAll()) do
		if (v:GetChar()) then
			table.insert(charTable, v:GetChar():GetID())
		end
	end

	return charTable
end

if (CLIENT) then
	local blur = ix.util.GetMaterial("pp/blurscreen")
	local surface = surface

	-- Draws a blurred material over the screen, to blur things.
	function ix.util.DrawBlur(panel, amount, passes)
		-- Intensity of the blur.
		amount = amount or 5

		if (ix.option.Get("cheapBlur", false)) then
			surface.SetDrawColor(50, 50, 50, amount * 20)
			surface.DrawRect(0, 0, panel:GetWide(), panel:GetTall())
		else
			surface.SetMaterial(blur)
			surface.SetDrawColor(255, 255, 255)

			local x, y = panel:LocalToScreen(0, 0)

			for i = -(passes or 0.2), 1, 0.2 do
				-- Do things to the blur material to make it blurry.
				blur:SetFloat("$blur", i * amount)
				blur:Recompute()

				-- Draw the blur material over the screen.
				render.UpdateScreenEffectTexture()
				surface.DrawTexturedRect(x * -1, y * -1, ScrW(), ScrH())
			end
		end
	end

	function ix.util.DrawBlurAt(x, y, w, h, amount, passes)
		-- Intensity of the blur.
		amount = amount or 5

		if (ix.option.Get("cheapBlur", false)) then
			surface.SetDrawColor(30, 30, 30, amount * 20)
			surface.DrawRect(x, y, w, h)
		else
			surface.SetMaterial(blur)
			surface.SetDrawColor(255, 255, 255)

			local scrW, scrH = ScrW(), ScrH()
			local x2, y2 = x / scrW, y / scrH
			local w2, h2 = (x + w) / scrW, (y + h) / scrH

			for i = -(passes or 0.2), 1, 0.2 do
				blur:SetFloat("$blur", i * amount)
				blur:Recompute()

				render.UpdateScreenEffectTexture()
				surface.DrawTexturedRectUV(x, y, w, h, x2, y2, w2, h2)
			end
		end
	end

	-- Draw a text with a shadow.
	function ix.util.DrawText(text, x, y, color, alignX, alignY, font, alpha)
		color = color or color_white

		return draw.TextShadow({
			text = text,
			font = font or "ixGenericFont",
			pos = {x, y},
			color = color,
			xalign = alignX or 0,
			yalign = alignY or 0
		}, 1, alpha or (color.a * 0.575))
	end

	-- Wraps text so it does not pass a certain width.
	function ix.util.WrapText(text, width, font)
		font = font or "ixChatFont"
		surface.SetFont(font)

		local exploded = string.Explode("%s", text, true)
		local line = ""
		local lines = {}
		local w = surface.GetTextSize(text)
		local maxW = 0

		if (w <= width) then
			return {(text:gsub("%s", " "))}, w
		end

		for i = 1, #exploded do
			local word = exploded[i]
			local wordWidth = surface.GetTextSize(word)

			if (wordWidth > width) then
				if (#lines ~= 0 and line ~= "") then
					lines[#lines + 1] = line
					line = ""
				end

				for i2 = 1, string.len(word) do
					local currentCharacter = string.sub(word, i2, i2)
					local newWidth = surface.GetTextSize(line..currentCharacter)

					if (newWidth > width) then
						lines[#lines + 1] = line
						line = ""
					end

					line = line..currentCharacter
				end
			end

			line = line.." "..word
			w = surface.GetTextSize(line)

			if (w > width) then
				lines[#lines + 1] = line
				line = ""

				if (w > maxW) then
					maxW = w
				end
			end
		end

		if (line ~= "") then
			lines[#lines + 1] = line
		end

		return lines, maxW
	end

	local cos, sin, abs, rad1, log, pow = math.cos, math.sin, math.abs, math.rad, math.log, math.pow

	-- arc drawing functions
	-- by bobbleheadbob
	-- https://facepunch.com/showthread.php?t=1558060
	function ix.util.DrawArc(cx, cy, radius, thickness, startang, endang, roughness, color)
		surface.SetDrawColor(color)
		ix.util.DrawPrecachedArc(ix.util.PrecacheArc(cx, cy, radius, thickness, startang, endang, roughness))
	end

	function ix.util.DrawPrecachedArc(arc) -- Draw a premade arc.
		for _, v in ipairs(arc) do
			surface.DrawPoly(v)
		end
	end

	function ix.util.PrecacheArc(cx, cy, radius, thickness, startang, endang, roughness)
		local quadarc = {}

		-- Correct start/end ang
		startang = startang or 0
		endang = endang or 0

		-- Define step
		-- roughness = roughness or 1
		local diff = abs(startang - endang)
		local smoothness = log(diff, 2) / 2
		local step = diff / (pow(2, smoothness))

		if startang > endang then
			step = abs(step) * -1
		end

		-- Create the inner circle's points.
		local inner = {}
		local outer = {}
		local ct = 1
		local r = radius - thickness

		for deg = startang, endang, step do
			local rad = rad1(deg)
			local cosrad, sinrad = cos(rad), sin(rad) --calculate sin, cos

			local ox, oy = cx + (cosrad * r), cy + (-sinrad * r) --apply to inner distance
			inner[ct] = {
				x = ox,
				y = oy,
				u = (ox - cx) / radius + .5,
				v = (oy - cy) / radius + .5
			}

			local ox2, oy2 = cx + (cosrad * radius), cy + (-sinrad * radius) --apply to outer distance
			outer[ct] = {
				x = ox2,
				y = oy2,
				u = (ox2 - cx) / radius + .5,
				v = (oy2 - cy) / radius + .5
			}

			ct = ct + 1
		end

		-- QUAD the points.
		for tri = 1, ct do
			local p1, p2, p3, p4
			local t = tri + 1
			p1 = outer[tri]
			p2 = outer[t]
			p3 = inner[t]
			p4 = inner[tri]

			quadarc[tri] = {p1, p2, p3, p4}
		end

		-- Return a table of triangles to draw.
		return quadarc
	end

	local LAST_WIDTH = ScrW()
	local LAST_HEIGHT = ScrH()

	timer.Create("ixResolutionMonitor", 1, 0, function()
		local scrW, scrH = ScrW(), ScrH()

		if (scrW != LAST_WIDTH or scrH != LAST_HEIGHT) then
			hook.Run("ScreenResolutionChanged", LAST_WIDTH, LAST_HEIGHT)

			LAST_WIDTH = scrW
			LAST_HEIGHT = scrH
		end
	end)
end

-- Vector extension, courtesy of code_gs
do
	local R = debug.getregistry()
	local VECTOR = R.Vector
	local CrossProduct = VECTOR.Cross

	function VECTOR:Right(vUp)
		if (self[1] == 0 and self[2] == 0) then return Vector(0, -1, 0) end

		if (vUp == nil) then
			vUp = vector_up
		end

		local vRet = CrossProduct(self, vUp)
		vRet:Normalize()

		return vRet
	end

	function VECTOR:Up(vUp)
		if (self[1] == 0 and self[2] == 0) then return Vector(-self[3], 0, 0) end

		if (vUp == nil) then
			vUp = vector_up
		end

		local vRet = CrossProduct(self, vUp)
		vRet = CrossProduct(vRet, self)
		vRet:Normalize()

		return vRet
	end
end

-- Utility entity extensions.
do
	local entityMeta = FindMetaTable("Entity")

	-- Checks if an entity is a door by comparing its class.
	function entityMeta:IsDoor()
		local class = self:GetClass()

		return (class and class:find("door") or false)
	end

	-- Make a cache of chairs on start.
	local CHAIR_CACHE = {}

	-- Add chair models to the cache by checking if its vehicle category is a class.
	for _, v in pairs(list.Get("Vehicles")) do
		if (v.Category == "Chairs") then
			CHAIR_CACHE[v.Model] = true
		end
	end

	-- Whether or not a vehicle is a chair by checking its model with the chair list.
	function entityMeta:IsChair()
		-- Micro-optimization in-case this gets used a lot.
		return CHAIR_CACHE[self.GetModel(self)]
	end

	if (SERVER) then
		-- Returns the door's slave entity.
		function entityMeta:GetDoorPartner()
			return self.ixPartner
		end

		-- Returns whether door/button is locked or not.
		function entityMeta:IsLocked()
			if (self:IsVehicle()) then
				local datatable = self:GetSaveTable()

				if (datatable) then
					return (datatable.VehicleLocked)
				end
			else
				local datatable = self:GetSaveTable()

				if (datatable) then
					return (datatable.m_bLocked)
				end
			end

			return
		end

		-- Returns the entity that blocking door's sequence.
		function entityMeta:GetBlocker()
			local datatable = self:GetSaveTable()

			return (datatable.pBlocker)
		end
	else
		-- Returns the door's slave entity.
		function entityMeta:GetDoorPartner()
			local owner = self:GetOwner() or self.ixDoorOwner

			if (IsValid(owner) and owner:IsDoor()) then
				return owner
			end

			for _, v in ipairs(ents.FindByClass("prop_door_rotating")) do
				if (v:GetOwner() == self) then
					self.ixDoorOwner = v

					return v
				end
			end
		end
	end

	-- Makes a fake door to replace it.
	function entityMeta:BlastDoor(velocity, lifeTime, ignorePartner)
		if (!self:IsDoor()) then
			return
		end

		if (IsValid(self.ixDummy)) then
			self.ixDummy:Remove()
		end

		velocity = velocity or VectorRand()*100
		lifeTime = lifeTime or 120

		local partner = self:GetDoorPartner()

		if (IsValid(partner) and !ignorePartner) then
			partner:BlastDoor(velocity, lifeTime, true)
		end

		local color = self:GetColor()

		local dummy = ents.Create("prop_physics")
		dummy:SetModel(self:GetModel())
		dummy:SetPos(self:GetPos())
		dummy:SetAngles(self:GetAngles())
		dummy:Spawn()
		dummy:SetColor(color)
		dummy:SetMaterial(self:GetMaterial())
		dummy:SetSkin(self:GetSkin() or 0)
		dummy:SetRenderMode(RENDERMODE_TRANSALPHA)
		dummy:CallOnRemove("restoreDoor", function()
			if (IsValid(self)) then
				self:SetNotSolid(false)
				self:SetNoDraw(false)
				self:DrawShadow(true)
				self.ignoreUse = false
				self.ixIsMuted = false

				for _, v in ipairs(ents.GetAll()) do
					if (v:GetParent() == self) then
						v:SetNotSolid(false)
						v:SetNoDraw(false)

						if (v.OnDoorRestored) then
							v:OnDoorRestored(self)
						end
					end
				end
			end
		end)
		dummy:SetOwner(self)
		dummy:SetCollisionGroup(COLLISION_GROUP_WEAPON)

		self:Fire("unlock")
		self:Fire("open")
		self:SetNotSolid(true)
		self:SetNoDraw(true)
		self:DrawShadow(false)
		self.ignoreUse = true
		self.ixDummy = dummy
		self.ixIsMuted = true
		self:DeleteOnRemove(dummy)

		for _, v in ipairs(self:GetBodyGroups() or {}) do
			dummy:SetBodygroup(v.id, self:GetBodygroup(v.id))
		end

		for _, v in ipairs(ents.GetAll()) do
			if (v:GetParent() == self) then
				v:SetNotSolid(true)
				v:SetNoDraw(true)

				if (v.OnDoorBlasted) then
					v:OnDoorBlasted(self)
				end
			end
		end

		dummy:GetPhysicsObject():SetVelocity(velocity)

		local uniqueID = "doorRestore"..self:EntIndex()
		local uniqueID2 = "doorOpener"..self:EntIndex()

		timer.Create(uniqueID2, 1, 0, function()
			if (IsValid(self) and IsValid(self.ixDummy)) then
				self:Fire("open")
			else
				timer.Remove(uniqueID2)
			end
		end)

		timer.Create(uniqueID, lifeTime, 1, function()
			if (IsValid(self) and IsValid(dummy)) then
				uniqueID = "dummyFade"..dummy:EntIndex()
				local alpha = 255

				timer.Create(uniqueID, 0.1, 255, function()
					if (IsValid(dummy)) then
						alpha = alpha - 1
						dummy:SetColor(ColorAlpha(color, alpha))

						if (alpha <= 0) then
							dummy:Remove()
						end
					else
						timer.Remove(uniqueID)
					end
				end)
			end
		end)

		return dummy
	end

	--[[
		luacheck: globals
		FCAP_IMPULSE_USE FCAP_CONTINUOUS_USE FCAP_ONOFF_USE FCAP_DIRECTIONAL_USE FCAP_USE_ONGROUND FCAP_USE_IN_RADIUS
	]]
	FCAP_IMPULSE_USE = 0x00000010
	FCAP_CONTINUOUS_USE = 0x00000020
	FCAP_ONOFF_USE = 0x00000040
	FCAP_DIRECTIONAL_USE = 0x00000080
	FCAP_USE_ONGROUND = 0x00000100
	FCAP_USE_IN_RADIUS = 0x00000200

	function ix.util.IsUseableEntity(pEntity, requiredCaps)
		if (IsValid(pEntity)) then
			local caps = pEntity:ObjectCaps()

			if (bit.band(caps, bit.bor(FCAP_IMPULSE_USE, FCAP_CONTINUOUS_USE, FCAP_ONOFF_USE, FCAP_DIRECTIONAL_USE))) then
				if (bit.band(caps, requiredCaps) == requiredCaps) then
					return true
				end
			end
		end
	end

	do
		local function IntervalDistance(x, x0, x1)
			-- swap so x0 < x1
			if (x0 > x1) then
				local tmp = x0

				x0 = x1
				x1 = tmp
			end

			if (x < x0) then
				return x0-x
			elseif (x > x1) then
				return x - x1
			end

			return 0
		end

		local NUM_TANGENTS = 8
		local tangents = {0, 1, 0.57735026919, 0.3639702342, 0.267949192431, 0.1763269807, -0.1763269807, -0.267949192431}

		function ix.util.FindUseEntity(player, origin, forward)
			local tr
			local up = forward:Up()
			-- Search for objects in a sphere (tests for entities that are not solid, yet still useable)
			local searchCenter = origin

			-- NOTE: Some debris objects are useable too, so hit those as well
			-- A button, etc. can be made out of clip brushes, make sure it's +useable via a traceline, too.
			local useableContents = bit.bor(MASK_SOLID, CONTENTS_DEBRIS, CONTENTS_PLAYERCLIP)

			-- UNDONE: Might be faster to just fold this range into the sphere query
			local pObject

			local nearestDist = 1e37
			-- try the hit entity if there is one, or the ground entity if there isn't.
			local pNearest = NULL

			for i = 1, NUM_TANGENTS do
				if (i == 0) then
					tr = util.TraceLine({
						start = searchCenter,
						endpos = searchCenter + forward * 1024,
						mask = useableContents,
						filter = player
					})

					tr.EndPos = searchCenter + forward * 1024
				else
					local down = forward - tangents[i] * up
					down:Normalize()

					tr = util.TraceHull({
						start = searchCenter,
						endpos = searchCenter + down * 72,
						mins = -Vector(16,16,16),
						maxs = Vector(16,16,16),
						mask = useableContents,
						filter = player
					})

					tr.EndPos = searchCenter + down * 72
				end

				pObject = tr.Entity

				local bUsable = ix.util.IsUseableEntity(pObject, 0)

				while (IsValid(pObject) and !bUsable and pObject:GetMoveParent()) do
					pObject = pObject:GetMoveParent()
					bUsable = ix.util.IsUseableEntity(pObject, 0)
				end

				if (bUsable) then
					local delta = tr.EndPos - tr.StartPos
					local centerZ = origin.z - player:WorldSpaceCenter().z
					delta.z = IntervalDistance(tr.EndPos.z, centerZ - player:OBBMins().z, centerZ + player:OBBMaxs().z)
					local dist = delta:Length()

					if (dist < 80) then
						pNearest = pObject

						-- if this is directly under the cursor just return it now
						if (i == 0) then
							return pObject
						end
					end
				end
			end

			-- check ground entity first
			-- if you've got a useable ground entity, then shrink the cone of this search to 45 degrees
			-- otherwise, search out in a 90 degree cone (hemisphere)
			if (IsValid(player:GetGroundEntity()) and ix.util.IsUseableEntity(player:GetGroundEntity(), FCAP_USE_ONGROUND)) then
				pNearest = player:GetGroundEntity()
			end

			if (IsValid(pNearest)) then
				-- estimate nearest object by distance from the view vector
				local point = pNearest:NearestPoint(searchCenter)
				nearestDist = util.DistanceToLine(searchCenter, forward, point)
			end

			for _, v in pairs(ents.FindInSphere(searchCenter, 80)) do
				if (!ix.util.IsUseableEntity(v, FCAP_USE_IN_RADIUS)) then
					continue
				end

				-- see if it's more roughly in front of the player than previous guess
				local point = v:NearestPoint(searchCenter)

				local dir = point - searchCenter
				dir:Normalize()
				local dot = dir:Dot(forward)

				-- Need to be looking at the object more or less
				if (dot < 0.8) then
					continue
				end

				local dist = util.DistanceToLine(searchCenter, forward, point)

				if (dist < nearestDist) then
					-- Since this has purely been a radius search to this point, we now
					-- make sure the object isn't behind glass or a grate.
					local trCheckOccluded = {}

					util.TraceLine({
						start = searchCenter,
						endpos = point,
						mask = useableContents,
						filter = player,
						output = trCheckOccluded
					})

					if (trCheckOccluded.fraction == 1.0 or trCheckOccluded.Entity == v) then
						pNearest = v
						nearestDist = dist
					end
				end
			end

			return pNearest
		end
	end
end

-- Misc. player stuff.
do
	local playerMeta = FindMetaTable("Player")
	ALWAYS_RAISED = {}
	ALWAYS_RAISED["weapon_physgun"] = true
	ALWAYS_RAISED["gmod_tool"] = true
	ALWAYS_RAISED["ix_poshelper"] = true

	-- Returns how many seconds the player has played on the server in total.
	if (SERVER) then
		function playerMeta:GetPlayTime()
			return self.ixPlayTime + (RealTime() - (self.ixJoinTime or RealTime()))
		end
	else
		ix.playTime = ix.playTime or 0

		function playerMeta:GetPlayTime()
			return ix.playTime + (RealTime() - ix.joinTime or 0)
		end
	end

	-- Returns whether or not the player has their weapon raised.
	function playerMeta:IsWepRaised()
		local weapon = self.GetActiveWeapon(self)
		local override = hook.Run("ShouldWeaponBeRaised", self, weapon)

		-- Allow the hook to check first.
		if (override != nil) then
			return override, weapon
		end

		-- Some weapons may have their own properties.
		if (IsValid(weapon)) then
			-- If their weapon is always raised, return true.
			if (weapon.IsAlwaysRaised or ALWAYS_RAISED[weapon.GetClass(weapon)]) then
				return true, weapon
			-- Return false if always lowered.
			elseif (weapon.IsAlwaysLowered or weapon.NeverRaised) then
				return false, weapon
			end
		end

		-- If the player has been forced to have their weapon lowered.
		if (self.GetNetVar(self, "restricted")) then
			return false, weapon
		end

		-- Let the config decide before actual results.
		if (ix.config.Get("wepAlwaysRaised")) then
			return true, weapon
		end

		-- Returns what the gamemode decides.
		return self.GetNetVar(self, "raised", false), weapon
	end

	local vectorLength2D = FindMetaTable("Vector").Length2D

	-- Checks if the player is running by seeing if the speed is faster than walking.
	function playerMeta:IsRunning()
		return vectorLength2D(self.GetVelocity(self)) > (self.GetWalkSpeed(self) + 10)
	end

	-- Checks if the player has a female model.
	function playerMeta:IsFemale()
		local model = self:GetModel():lower()

		return model:find("female") or model:find("alyx") or model:find("mossman") or ix.anim.GetModelClass(model) == "citizen_female"
	end

	-- Returns a good position in front of the player for an entity.
	function playerMeta:GetItemDropPos(entity)
		local data = {}
		local trace

		data.start = self:GetShootPos()
		data.endpos = self:GetShootPos() + self:GetAimVector() * 86
		data.filter = self

		if (IsValid(entity)) then
			-- use a hull trace if there's a valid entity to avoid collisions
			local mins, maxs = entity:GetRotatedAABB(entity:OBBMins(), entity:OBBMaxs())

			data.mins = mins
			data.maxs = maxs
			data.filter = {entity, self}
			trace = util.TraceHull(data)
		else
			-- trace along the normal for a few units so we can attempt to avoid a collision
			trace = util.TraceLine(data)

			data.start = trace.HitPos
			data.endpos = data.start + trace.HitNormal * 48
			trace = util.TraceLine(data)
		end

		return trace.HitPos
	end

	-- Do an action that requires the player to stare at something.
	function playerMeta:DoStaredAction(entity, callback, time, onCancel, distance)
		local uniqueID = "ixStare"..self:UniqueID()
		local data = {}
		data.filter = self

		timer.Create(uniqueID, 0.1, time / 0.1, function()
			if (IsValid(self) and IsValid(entity)) then
				data.start = self:GetShootPos()
				data.endpos = data.start + self:GetAimVector()*(distance or 96)

				if (util.TraceLine(data).Entity != entity) then
					timer.Remove(uniqueID)

					if (onCancel) then
						onCancel()
					end
				elseif (callback and timer.RepsLeft(uniqueID) == 0) then
					callback()
				end
			else
				timer.Remove(uniqueID)

				if (onCancel) then
					onCancel()
				end
			end
		end)
	end

	if (SERVER) then
		-- Sets whether or not the weapon is raised.
		function playerMeta:SetWepRaised(state)
			-- Sets the networked variable for being raised.
			self:SetNetVar("raised", state)

			-- Delays any weapon shooting.
			local weapon = self:GetActiveWeapon()

			if (IsValid(weapon)) then
				weapon:SetNextPrimaryFire(CurTime() + 1)
				weapon:SetNextSecondaryFire(CurTime() + 1)
			end
		end

		-- Inverts whether or not the weapon is raised.
		function playerMeta:ToggleWepRaised()
			self:SetWepRaised(!self:IsWepRaised())

			local weapon = self:GetActiveWeapon()

			if (IsValid(weapon)) then
				if (self:IsWepRaised() and weapon.OnRaised) then
					weapon:OnRaised()
				elseif (!self:IsWepRaised() and weapon.OnLowered) then
					weapon:OnLowered()
				end
			end
		end

		-- Performs a delayed action that requires the user to hold use on an entity.
		-- The callback will be ran right away if the time is zero.
		function playerMeta:PerformInteraction(time, entity, callback)
			if (time > 0) then
				self.ixInteractionTarget = entity
				self.ixInteractionCharacter = self:GetCharacter():GetID()

				timer.Create("ixCharacterInteraction" .. self:SteamID(), time, 1, function()
					if (IsValid(self) and IsValid(entity) and IsValid(self.ixInteractionTarget) and
						self.ixInteractionCharacter == self:GetCharacter():GetID()) then
						local data = {}
							data.start = self:GetShootPos()
							data.endpos = data.start + self:GetAimVector() * 96
							data.filter = self
						local traceEntity = util.TraceLine(data).Entity

						if (IsValid(traceEntity) and traceEntity == self.ixInteractionTarget) then
							callback(self)
						end
					end
				end)
			else
				callback(self)
			end
		end

		-- Performs a delayed action on a player.
		function playerMeta:SetAction(text, time, callback, startTime, finishTime)
			if (time and time <= 0) then
				if (callback) then
					callback(self)
				end

				return
			end

			-- Default the time to five seconds.
			time = time or 5
			startTime = startTime or CurTime()
			finishTime = finishTime or (startTime + time)

			if (text == false) then
				timer.Remove("ixAct"..self:UniqueID())
				netstream.Start(self, "actBar")

				return
			end

			-- Tell the player to draw a bar for the action.
			netstream.Start(self, "actBar", startTime, finishTime, text)

			-- If we have provided a callback, run it delayed.
			if (callback) then
				-- Create a timer that runs once with a delay.
				timer.Create("ixAct"..self:UniqueID(), time, 1, function()
					-- Call the callback if the player is still valid.
					if (IsValid(self)) then
						callback(self)
					end
				end)
			end
		end

		-- Sends a Derma string request to the client.
		function playerMeta:RequestString(title, subTitle, callback, default)
			local time = math.floor(os.time())

			self.ixStrReqs = self.ixStrReqs or {}
			self.ixStrReqs[time] = callback

			netstream.Start(self, "strReq", time, title, subTitle, default)
		end

		-- Removes a player's weapon and restricts interactivity.
		function playerMeta:SetRestricted(state, noMessage)
			if (state) then
				self:SetNetVar("restricted", true)

				if (noMessage) then
					self:SetLocalVar("restrictNoMsg", true)
				end

				self.ixRestrictWeps = self.ixRestrictWeps or {}

				for _, v in pairs(self:GetWeapons()) do
					self.ixRestrictWeps[#self.ixRestrictWeps + 1] = v:GetClass()
					v:Remove()
				end

				hook.Run("OnPlayerRestricted", self)
			else
				self:SetNetVar("restricted")

				if (self:GetLocalVar("restrictNoMsg")) then
					self:SetLocalVar("restrictNoMsg")
				end

				if (self.ixRestrictWeps) then
					for _, v in ipairs(self.ixRestrictWeps) do
						self:Give(v)
					end

					self.ixRestrictWeps = nil
				end

				hook.Run("OnPlayerUnRestricted", self)
			end
		end
	end

	-- Player ragdoll utility stuff.
	do
		function ix.util.FindEmptySpace(entity, filter, spacing, size, height, tolerance)
			spacing = spacing or 32
			size = size or 3
			height = height or 36
			tolerance = tolerance or 5

			local position = entity:GetPos()
			local mins, maxs = Vector(-spacing * 0.5, -spacing * 0.5, 0), Vector(spacing * 0.5, spacing * 0.5, height)
			local output = {}

			for x = -size, size do
				for y = -size, size do
					local origin = position + Vector(x * spacing, y * spacing, 0)

					local data = {}
						data.start = origin + mins + Vector(0, 0, tolerance)
						data.endpos = origin + maxs
						data.filter = filter or entity
					local trace = util.TraceLine(data)

					data.start = origin + Vector(-maxs.x, -maxs.y, tolerance)
					data.endpos = origin + Vector(mins.x, mins.y, height)

					local trace2 = util.TraceLine(data)

					if (trace.StartSolid or trace.Hit or trace2.StartSolid or trace2.Hit or !util.IsInWorld(origin)) then
						continue
					end

					output[#output + 1] = origin
				end
			end

			table.sort(output, function(a, b)
				return a:Distance(position) < b:Distance(position)
			end)

			return output
		end

		function playerMeta:IsStuck()
			return util.TraceEntity({
				start = self:GetPos(),
				endpos = self:GetPos(),
				filter = self
			}, self).StartSolid
		end

		-- Creates a ragdoll entity of the given player that will be synced with clients
		function playerMeta:CreateServerRagdoll(bDontSetPlayer)
			local entity = ents.Create("prop_ragdoll")
			entity:SetPos(self:GetPos())
			entity:SetAngles(self:EyeAngles())
			entity:SetModel(self:GetModel())
			entity:SetSkin(self:GetSkin())
			entity:Spawn()

			if (!bDontSetPlayer) then
				entity:SetNetVar("player", self)
			end

			entity:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			entity:Activate()

			local velocity = self:GetVelocity()

			for i = 0, entity:GetPhysicsObjectCount() - 1 do
				local physObj = entity:GetPhysicsObjectNum(i)

				if (IsValid(physObj)) then
					physObj:SetVelocity(velocity)

					local index = entity:TranslatePhysBoneToBone(i)

					if (index) then
						local position, angles = self:GetBonePosition(index)

						physObj:SetPos(position)
						physObj:SetAngles(angles)
					end
				end
			end

			return entity
		end

		function playerMeta:SetRagdolled(state, time, getUpGrace)
			getUpGrace = getUpGrace or time or 5

			if (state) then
				if (IsValid(self.ixRagdoll)) then
					self.ixRagdoll:Remove()
				end

				local entity = self:CreateServerRagdoll()

				entity:CallOnRemove("fixer", function()
					if (IsValid(self)) then
						self:SetLocalVar("blur", nil)
						self:SetLocalVar("ragdoll", nil)

						if (!entity.ixNoReset) then
							self:SetPos(entity:GetPos())
						end

						self:SetNoDraw(false)
						self:SetNotSolid(false)
						self:Freeze(false)
						self:SetMoveType(MOVETYPE_WALK)
						self:SetLocalVelocity(IsValid(entity) and entity.ixLastVelocity or vector_origin)
					end

					if (IsValid(self) and !entity.ixIgnoreDelete) then
						if (entity.ixWeapons) then
							for _, v in ipairs(entity.ixWeapons) do
								self:Give(v)

								if (entity.ixAmmo) then
									for k2, v2 in ipairs(entity.ixAmmo) do
										if v == v2[1] then
											self:SetAmmo(v2[2], tostring(k2))
										end
									end
								end
							end

							for _, v in pairs(self:GetWeapons()) do
								v:SetClip1(0)
							end
						end

						if (self:IsStuck()) then
							entity:DropToFloor()
							self:SetPos(entity:GetPos() + Vector(0, 0, 16))

							local positions = ix.util.FindEmptySpace(self, {entity, self})

							for _, v in ipairs(positions) do
								self:SetPos(v)

								if (!self:IsStuck()) then
									return
								end
							end
						end
					end
				end)

				self:SetLocalVar("blur", 25)
				self.ixRagdoll = entity

				entity.ixWeapons = {}
				entity.ixAmmo = {}
				entity.ixPlayer = self

				if (getUpGrace) then
					entity.ixGrace = CurTime() + getUpGrace
				end

				if (time and time > 0) then
					entity.ixStart = CurTime()
					entity.ixFinish = entity.ixStart + time

					self:SetAction("@wakingUp", nil, nil, entity.ixStart, entity.ixFinish)
				end

				for _, v in pairs(self:GetWeapons()) do
					entity.ixWeapons[#entity.ixWeapons + 1] = v:GetClass()

					local clip = v:Clip1()
					local reserve = self:GetAmmoCount(v:GetPrimaryAmmoType())
					local ammo = clip + reserve

					entity.ixAmmo[v:GetPrimaryAmmoType()] = {v:GetClass(), ammo}
				end

				self:GodDisable()
				self:StripWeapons()
				self:Freeze(true)
				self:SetNoDraw(true)
				self:SetNotSolid(true)

				if (time) then
					local uniqueID = "ixUnRagdoll"..self:SteamID()

					timer.Create(uniqueID, 0.33, 0, function()
						if (IsValid(entity) and IsValid(self)) then
							local velocity = entity:GetVelocity()
							entity.ixLastVelocity = velocity

							self:SetPos(entity:GetPos())

							if (velocity:Length2D() >= 8) then
								if (!entity.ixPausing) then
									self:SetAction()
									entity.ixPausing = true
								end

								return
							elseif (entity.ixPausing) then
								self:SetAction("@wakingUp", time)
								entity.ixPausing = false
							end

							time = time - 0.33

							if (time <= 0) then
								entity:Remove()
							end
						else
							timer.Remove(uniqueID)
						end
					end)
				end

				self:SetLocalVar("ragdoll", entity:EntIndex())
				hook.Run("OnCharFallover", self, entity, true)
			elseif (IsValid(self.ixRagdoll)) then
				self.ixRagdoll:Remove()

				hook.Run("OnCharFallover", self, nil, false)
			end
		end
	end
end

-- Time related stuff.
do
	-- Gets the current time in the UTC time-zone.
	function ix.util.GetUTCTime()
		local date = os.date("!*t")
		local localDate = os.date("*t")
		localDate.isdst = false

		return os.difftime(os.time(date), os.time(localDate))
	end

	-- Setup for time strings.
	local TIME_UNITS = {}
	TIME_UNITS["s"] = 1						-- Seconds
	TIME_UNITS["m"] = 60					-- Minutes
	TIME_UNITS["h"] = 3600					-- Hours
	TIME_UNITS["d"] = TIME_UNITS["h"] * 24	-- Days
	TIME_UNITS["w"] = TIME_UNITS["d"] * 7	-- Weeks
	TIME_UNITS["mo"] = TIME_UNITS["d"] * 30	-- Months
	TIME_UNITS["y"] = TIME_UNITS["d"] * 365	-- Years

	-- Gets the amount of seconds from a given formatted string.
	-- Example: 5y2d7w = 5 years, 2 days, and 7 weeks.
	-- If just given a minute, it is assumed minutes.
	function ix.util.GetStringTime(text)
		local minutes = tonumber(text)

		if (minutes) then
			return math.abs(minutes * 60)
		end

		local time = 0

		for amount, unit in text:lower():gmatch("(%d+)(%a+)") do
			amount = tonumber(amount)

			if (amount and TIME_UNITS[unit]) then
				time = time + math.abs(amount * TIME_UNITS[unit])
			end
		end

		return time
	end
end

--[[
	Credit to TFA for figuring this mess out.
	Original: https://steamcommunity.com/sharedfiles/filedetails/?id=903541818
]]

if (system.IsLinux()) then
	local cache = {}

	-- Helper Functions
	local function GetSoundPath(path, gamedir)
		if (!gamedir) then
			path = "sound/" .. path
			gamedir = "GAME"
		end

		return path, gamedir
	end

	local function f_IsWAV(f)
		f:Seek(8)

		return f:Read(4) == "WAVE"
	end

	-- WAV functions
	local function f_SampleDepth(f)
		f:Seek(34)
		local bytes = {}

		for i = 1, 2 do
			bytes[i] = f:ReadByte(1)
		end

		local num = bit.lshift(bytes[2], 8) + bit.lshift(bytes[1], 0)

		return num
	end

	local function f_SampleRate(f)
		f:Seek(24)
		local bytes = {}

		for i = 1, 4 do
			bytes[i] = f:ReadByte(1)
		end

		local num = bit.lshift(bytes[4], 24) + bit.lshift(bytes[3], 16) + bit.lshift(bytes[2], 8) + bit.lshift(bytes[1], 0)

		return num
	end

	local function f_Channels(f)
		f:Seek(22)
		local bytes = {}

		for i = 1, 2 do
			bytes[i] = f:ReadByte(1)
		end

		local num = bit.lshift(bytes[2], 8) + bit.lshift(bytes[1], 0)

		return num
	end

	local function f_Duration(f)
		return (f:Size() - 44) / (f_SampleDepth(f) / 8 * f_SampleRate(f) * f_Channels(f))
	end

	ixSoundDuration = ixSoundDuration or SoundDuration -- luacheck: globals ixSoundDuration

	function SoundDuration(str) -- luacheck: globals SoundDuration
		local path, gamedir = GetSoundPath(str)
		local f = file.Open(path, "rb", gamedir)

		if (!f) then return 0 end --Return nil on invalid files

		local ret

		if (cache[str]) then
			ret = cache[str]
		elseif (f_IsWAV(f)) then
			ret = f_Duration(f)
		else
			ret = ixSoundDuration(str)
		end

		f:Close()

		return ret
	end
end

local ADJUST_SOUND = SoundDuration("npc/metropolice/pain1.wav") > 0 and "" or "../../hl2/sound/"

-- Emits sounds one after the other from an entity.
function ix.util.EmitQueuedSounds(entity, sounds, delay, spacing, volume, pitch)
	-- Let there be a delay before any sound is played.
	delay = delay or 0
	spacing = spacing or 0.1

	-- Loop through all of the sounds.
	for _, v in ipairs(sounds) do
		local postSet, preSet = 0, 0

		-- Determine if this sound has special time offsets.
		if (type(v) == "table") then
			postSet, preSet = v[2] or 0, v[3] or 0
			v = v[1]
		end

		-- Get the length of the sound.
		local length = SoundDuration(ADJUST_SOUND..v)
		-- If the sound has a pause before it is played, add it here.
		delay = delay + preSet

		-- Have the sound play in the future.
		timer.Simple(delay, function()
			-- Check if the entity still exists and play the sound.
			if (IsValid(entity)) then
				entity:EmitSound(v, volume, pitch)
			end
		end)

		-- Add the delay for the next sound.
		delay = delay + length + postSet + spacing
	end

	-- Return how long it took for the whole thing.
	return delay
end
