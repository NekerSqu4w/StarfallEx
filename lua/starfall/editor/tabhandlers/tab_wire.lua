--[[
Modified version of Wire Editor, you can find original code and it's licence on link below.
https://github.com/wiremod/wire
File in use: https://github.com/wiremod/wire/blob/3cf67a781006886fb76619c23ea55fa1c661ae90/lua/wire/client/text_editor/texteditor.lua
]]

--
-- Expression 2 Text Editor for Garry's Mod
-- Andreas "Syranide" Svensson, me@syranide.com
--

local string_Explode = string.Explode
local table_concat = table.concat
local string_sub = string.sub
local table_remove = table.remove
local math_floor = math.floor
local math_Clamp = math.Clamp
local math_ceil = math.ceil
local string_match = string.match
local string_gmatch = string.gmatch
local string_gsub = string.gsub
local string_rep = string.rep
local string_byte = string.byte
local string_format = string.format
local string_Trim = string.Trim
local string_reverse = string.reverse
local math_min = math.min
local table_insert = table.insert
local table_sort = table.sort
local surface_SetDrawColor = surface.SetDrawColor
local surface_DrawRect = surface.DrawRect
local surface_SetFont = surface.SetFont
local surface_GetTextSize = surface.GetTextSize
local surface_PlaySound = surface.PlaySound
local surface_SetTextPos = surface.SetTextPos
local surface_SetTextColor = surface.SetTextColor
local surface_DrawText = surface.DrawText
local draw_SimpleText = draw.SimpleText
local draw_WordBox = draw.WordBox
local draw_RoundedBox = draw.RoundedBox

local TabHandler = {
	Modes = {},
	ControlName = "TabHandler_wire",
	IsEditor = true,
	Description = "Wire-based editor"
}
TabHandler.Modes.Text = { SyntaxColorLine = function(self, row) return { { self.Rows[row], { Color(255, 255, 255, 255), false } } } end }
---------------------
-- Fonts
---------------------
TabHandler.Fonts = {} --Font descriptions for settings
TabHandler.Fonts["Courier New"] = "Font used in expression2 editor"
TabHandler.Fonts["DejaVu Sans Mono"] = "Default SF Editor font"
TabHandler.Fonts["Consolas"] = ""
TabHandler.Fonts["Fixedsys"] = ""
TabHandler.Fonts["Lucida Console"] = ""
TabHandler.Fonts["Monaco"] = "Mac standard font"
TabHandler.Fonts["Roboto Mono"] = "Custom Font shipped with starfall"
TabHandler.Tabs = {}
local defaultFont = "DejaVu Sans Mono" -- We ship that with starfall, linux has it by default

TabHandler.FontConVar = CreateClientConVar("sf_editor_wire_fontname", defaultFont, true, false)
TabHandler.FontSizeConVar = CreateClientConVar("sf_editor_wire_fontsize", 16, true, false)
TabHandler.BlockCommentStyleConVar = CreateClientConVar("sf_editor_wire_block_comment_style", 1, true, false)
TabHandler.PigmentsConVar = CreateClientConVar("sf_editor_wire_pigments", 1, true, false)
TabHandler.EnlightenColorsConVar = CreateClientConVar("sf_editor_wire_enlightencolors", 0, true, false) --off by default
---------------------
-- Colors
---------------------

local colors = { }

function TabHandler:LoadSyntaxColors()
	colors = {}
	for k,v in pairs(SF.Editor.Themes.CurrentTheme) do
		if type(v) != "table" then continue end
		if not v["r"] then
			local mult = TabHandler.EnlightenColorsConVar:GetBool() and 1 or 1.2 -- For some reason gmod seems to render text darker than html
			colors[k] = {
				Color(v[1].r*mult,v[1].g*mult,v[1].b*mult,v[1]["a"] or 255),
				v[2] and Color(v[2].r*mult,v[2].g*mult,v[2].b*mult,v[2]["a"] or 255) or nil,
				v[3]
			}
		else
			colors[k] = Color(v.r,v.g,v.b,v["a"])
		end

	end
end

function TabHandler:GetSyntaxColor(name)
	return colors[name]
end

---------------------

local function createWireLibraryMap () -- Hashtable

	local libMap = {}
	libMap["Methods"] = {}
	for lib, tbl in pairs(SF.Docs.classes) do
		if not isstring(lib) then continue end -- We gotta skip numberics
		for name, val in pairs(tbl.methods) do
			if not isstring(name) then continue end -- We gotta skip numberics
			libMap["Methods"][name] = true
		end
	end

	libMap["Environment"] = {}
	for name, val in pairs(SF.DefaultEnvironment) do
		if istable(val) then
			libMap["Environment"][name] = {}
			for n, v in pairs(val) do
				libMap["Environment"][name][n] = type(v)
			end
			continue
		end
		libMap["Environment"][name] = type(val)
	end

	for lib, tbl in pairs(SF.Libraries.libraries) do --Constants/enums aren't present in docs ATM
		libMap[lib] = {}
		for name, val in pairs(tbl) do
			libMap[lib][name] = type(val)
		end
	end
	--Gathering data from docs
	for lib, tbl in pairs(SF.Docs.libraries) do
		if not isstring(lib) then continue end -- We gotta skip numberics
		libMap[lib] = {}
		for name, val in pairs(tbl.functions) do
			if not isstring(name) then continue end -- We gotta skip numberics
			libMap[lib][name] = val.class
		end
	end

	return libMap
end

function TabHandler:Init()
	TabHandler.LibMap = createWireLibraryMap ()

	TabHandler.Modes.Starfall = include("starfall/editor/syntaxmodes/starfall.lua")
	colors = SF.Editor.Themes.CurrentTheme
	self.PaintRows = {}
	self:LoadSyntaxColors()
end

function TabHandler:RegisterTabMenu(menu, content)
	local coloring = menu:AddSubMenu("Coloring")
	for k,v in pairs(TabHandler.Modes) do
		local mode = v
		coloring:AddOption(k, function()
			content.CurrentMode = mode
			content.PaintRows = {}
		end)
	end
end

function TabHandler:RegisterSettings()
	local label
	local dlist = vgui.Create("DPanelList")
	dlist.Paint = function() end
	dlist:EnableVerticalScrollbar(true)
	dlist:Dock(FILL)
	--- - FONTS

	local FontLabel = vgui.Create("DLabel")
	dlist:AddItem(FontLabel)
	FontLabel:SetText("Font:                                   Font Size:")
	FontLabel:SizeToContents()
	FontLabel:SetPos(10, 0)

	local temp = vgui.Create("Panel")
	temp:SetTall(25)
	dlist:AddItem(temp)

	local FontSelect = vgui.Create("DComboBox", temp)
	-- dlist:AddItem( FontSelect )
	FontSelect.OnSelect = function(panel, index, value)
		if value == "Custom..." then
			Derma_StringRequestNoBlur("Enter custom font:", "", "", function(value)
				RunConsoleCommand("sf_editor_wire_fontname", value)
				RunConsoleCommand("sf_editor_restart")
			end)
		else
			value = value:gsub(" %b()", "") -- Remove description
			RunConsoleCommand("sf_editor_wire_fontname", value)
			RunConsoleCommand("sf_editor_restart")
		end
	end
	for k, v in pairs(self.Fonts) do
		FontSelect:AddChoice(k .. (v ~= "" and " (" .. v .. ")" or ""))
	end
	FontSelect:AddChoice("Custom...")
	FontSelect:SetSize(240 - 50 - 4, 20)
	FontSelect:SetValue(TabHandler.FontConVar:GetString())
	FontSelect:SetFontInternal(SF.Editor.editor:GetFont(TabHandler.FontConVar:GetString(), 16))


	local FontSizeSelect = vgui.Create("DComboBox", temp)
	FontSizeSelect.OnSelect = function(panel, index, value)
		value = value:gsub(" %b()", "")
		RunConsoleCommand("sf_editor_wire_fontsize", value)
		RunConsoleCommand("sf_editor_restart")
	end
	for i = 11, 26 do
		FontSizeSelect:AddChoice(i .. (i == 16 and " (Default)" or ""))
	end
	FontSizeSelect:SetPos(FontSelect:GetWide() + 4, 0)
	FontSizeSelect:SetSize(50, 20)
	FontSizeSelect:SetValue(TabHandler.FontSizeConVar:GetString())

	if system.IsLinux() then
		label = vgui.Create("DLabel")
		dlist:AddItem(label)
		label:SetWrap(true)
		label:SetText("Warning: You are running linux, you should make sure font is installed in your system or you wont be able to see it!")
		label:SetSize(50, 40)
		label:SetPos(10, 0)
	end

	label = vgui.Create("DLabel")
	dlist:AddItem(label)
	label:SetText("Pigments:")
	label:SizeToContents()
	label:SetPos(10, 0)

	local usePigments = vgui.Create("DComboBox")
	dlist:AddItem(usePigments)
	usePigments:SetSortItems(false)
	usePigments:AddChoice("Disabled")
	usePigments:AddChoice("Stripe under Color()")
	usePigments:AddChoice("Background of Color()")
	usePigments:ChooseOptionID(TabHandler.PigmentsConVar:GetInt() + 1)
	usePigments:SetTooltip("Enable/disable custom coloring of Color(r,g,b)")
	usePigments.OnSelect = function(_, val)
		RunConsoleCommand("sf_editor_wire_pigments", val-1)
		timer.Simple(0, function()
			SF.Editor.editor:GetCurrentTabContent().PaintRows = {} -- Re-color syntax
		end)
	end
	return dlist, "Wire", "icon16/pencil.png", "Options for wire tabs."
end

local wire_expression2_autocomplete_controlstyle = CreateClientConVar("wire_expression2_autocomplete_controlstyle", "0", true, false)

local PANEL = {}
function PANEL:OnValidate(s, r, m, goto)
	if s or not goto then return end
	self:SetCaret({ r, 0 })
end
function PANEL:Init()
	self:SetCursor("beam")

	self.TabHandler = TabHandler

	self.Rows = { "" }
	self.Caret = { 1, 1 }
	self.Start = { 1, 1 }
	self.Scroll = { 1, 1 }
	self.Size = { 1, 1 }
	self.Undo = {}
	self.Redo = {}
	self.PaintRows = {}
	self.HiddenRows = {}
	self.RowOffset = {}
	self.RealLine = {}

	self.CurrentMode = assert(TabHandler.Modes.Text)

	self.LineNumberWidth = 2

	self.Blink = RealTime()

	self.ScrollBar = vgui.Create("DVScrollBar", self)
	self.ScrollBar:SetUp(1, 1)
	self.ScrollBar.Paint = function(_, w, h)
		surface_SetDrawColor(colors.gutter_background)
		surface_DrawRect(0, 0, w, h)
	end
	self.ScrollBar.btnGrip.Paint = function(_, w, h)
		surface_SetDrawColor(colors.gutter_foreground)
		draw.RoundedBox(4, 0, 0, w, h, Color(234, 234, 234))
	end
	self.ScrollBar:SetHideButtons( true )

	self.TextEntry = vgui.Create("TextEntry", self)
	self.TextEntry:SetMultiline(true)
	self.TextEntry:SetSize(0, 0)

	self.TextEntry.OnLoseFocus = function (self) self.Parent:_OnLoseFocus() end
	self.TextEntry.OnTextChanged = function (self) self.Parent:_OnTextChanged() end
	self.TextEntry.OnKeyCodeTyped = function (self, code) return self.Parent:_OnKeyCodeTyped(code) end

	self.TextEntry.Parent = self

	self.LastClick = 0

	self.e2fs_functions = {}

	self:SetMode("Starfall")
	self.CurrentMode:LoadSyntaxColors()

	self.CurrentFont, self.FontWidth, self.FontHeight = SF.Editor.editor:GetFont(TabHandler.FontConVar:GetString(), TabHandler.FontSizeConVar:GetInt())
	table.insert(TabHandler.Tabs, self)

end

function PANEL:HideRow(row)
	self.HiddenRows[row] = true
	local off = 0
	for I = row, #self.Rows do
		if self.HiddenRows[I] then
			off = off + 1
		end
		self.RowOffset[I] = off
	end
end

function PANEL:ShowRow(row)
	self.HiddenRows[row] = false
end

function PANEL:GetRowOffset(row)
	return self.RowOffset[row] or 0
end

function PANEL:OnThemeChange()
	colors = SF.Editor.Themes.CurrentTheme
	self.CurrentMode:LoadSyntaxColors()
end

function PANEL:OnRemove()
	table.RemoveByValue(TabHandler.Tabs, self)
end

function PANEL:SetMode(mode_name)
	self.CurrentMode = TabHandler.Modes[mode_name or "Text"]
	if not self.CurrentMode then
		Msg("Couldn't find text editor mode '".. tostring(mode_name) .. "'")
		self.CurrentMode = assert(TabHandler.Modes.Text, "Couldn't find default text editor mode")
	end
end

function PANEL:DoAction(name, ...)
	if not self.CurrentMode then return end
	local f = assert(self.CurrentMode, "No current mode set")[name]
	if not f then f = TabHandler.Modes.Text[name] end
	if f then return f(self, ...) end
end

function PANEL:GetParent()
	return self.parentpanel
end

function PANEL:RequestFocus()
	self.TextEntry:RequestFocus()
end

function PANEL:OnGetFocus()
	self.TextEntry:RequestFocus()
end

function PANEL:CursorToCaret()
	local x, y = self:CursorPos()

	x = x - (self.LineNumberWidth + 6)
	if x < 0 then x = 0 end
	if y < 0 then y = 0 end

	local line = math_floor(y / self.FontHeight)
	local char = math_floor(x / self.FontWidth + 0.5)

	line = self.RealLine[line]

	char = char + self.Scroll[2]
	if line > #self.Rows then line = #self.Rows end
	local length = #self.Rows[line]
	if char > length + 1 then char = length + 1 end

	return { line, char }
end

local wire_expression2_editor_highlight_on_double_click = CreateClientConVar("wire_expression2_editor_highlight_on_double_click", "1", true, false)

function PANEL:OpenContextMenu()
	local menu = DermaMenu()

	if self:CanUndo() then
		menu:AddOption("Undo", function()
				self:DoUndo()
			end)
	end
	if self:CanRedo() then
		menu:AddOption("Redo", function()
				self:DoRedo()
			end)
	end

	if self:CanUndo() or self:CanRedo() then
		menu:AddSpacer()
	end
	--[[
		menu:AddOption("",function()
			local y = self.Caret[1]
			self:HideRow(y)
		end)

	]]
	if self:HasSelection() then
		menu:AddOption("Cut", function()
				if self:HasSelection() then
					self.clipboard = self:GetSelection()
					self.clipboard = string_gsub(self.clipboard, "\n", "\r\n")
					SetClipboardText(self.clipboard)
					self:SetSelection()
				end
			end)
		menu:AddOption("Copy", function()
				if self:HasSelection() then
					self.clipboard = self:GetSelection()
					self.clipboard = string_gsub(self.clipboard, "\n", "\r\n")
					SetClipboardText(self.clipboard)
				end
			end)
	end

	menu:AddOption("Paste", function()
			if self.clipboard then
				self:SetSelection(self.clipboard)
			else
				self:SetSelection()
			end
		end)

	if self:HasSelection() then
		menu:AddOption("Delete", function()
				self:SetSelection()
			end)
	end

	menu:AddSpacer()

	menu:AddOption("Select all", function()
			self:SelectAll()
		end)

	menu:AddSpacer()

	menu:AddOption("Indent", function()
			self:Indent(false)
		end)
	menu:AddOption("Outdent", function()
			self:Indent(true)
		end)

	if self:HasSelection() then
		menu:AddSpacer()

		menu:AddOption("Comment Block", function()
				self:CommentSelection(false)
			end)
		menu:AddOption("Uncomment Block", function()
				self:CommentSelection(true)
			end)

		menu:AddOption("Comment Selection", function()
				self:BlockCommentSelection(false)
			end)
		menu:AddOption("Uncomment Selection", function()
				self:BlockCommentSelection(true)
			end)
	end

	self:DoAction("PopulateMenu", menu)

	menu:AddSpacer()

	menu:AddOption("Copy with BBCode colors", function()
			local str = string_format("[code][font=%s]", TabHandler.FontConVar)

			local prev_colors
			local first_loop = true

			for i = 1, #self.Rows do
				local colors = self:SyntaxColorLine(i)

				for k, v in pairs(colors) do
					local color = v[2][1]

					if (prev_colors and prev_colors == color) or string_Trim(v[1]) == "" then
						str = str .. v[1]
					else
						prev_colors = color

						if first_loop then
							str = str .. string_format('[color="#%x%x%x"]', color.r - 50, color.g - 50, color.b - 50) .. v[1]
							first_loop = false
						else
							str = str .. string_format('[/color][color="#%x%x%x"]', color.r - 50, color.g - 50, color.b - 50) .. v[1]
						end
					end
				end

				str = str .. "\r\n"

			end

			str = str .. "[/color][/font][/code]"

			self.clipboard = str
			SetClipboardText(str)
		end)

	menu:Open()
	return menu
end

function PANEL:OnMousePressed(code)
	if code == MOUSE_LEFT then
		local cursor = self:CursorToCaret()
		if (CurTime() - self.LastClick) < 1 and self.tmp and cursor[1] == self.Caret[1] and cursor[2] == self.Caret[2] then
			self.Start = self:getWordStart(self.Caret)
			self.Caret = self:getWordEnd(self.Caret)
			self.tmp = false

			if wire_expression2_editor_highlight_on_double_click:GetBool() then
				self.HighlightedAreasByDoubleClick = {}
				local all_finds = self:FindAllWords(self:GetSelection())
				if all_finds then
					all_finds[0] = { 1, 1 } -- Set [0] so the [i-1]'s don't fail on the first iteration
					self.HighlightedAreasByDoubleClick[0] = { { 1, 1 }, { 1, 1 } }
					for i = 1, #all_finds do
						-- Instead of finding the caret by searching from the beginning every time, start searching from the previous caret
						local start = all_finds[i][1] - all_finds[i-1][1]
						local stop = all_finds[i][2] - all_finds[i-1][2]
						local caretstart = self:MovePosition(self.HighlightedAreasByDoubleClick[i-1][1], start)
						local caretstop = self:MovePosition(self.HighlightedAreasByDoubleClick[i-1][2], stop)
						self.HighlightedAreasByDoubleClick[i] = { caretstart, caretstop }

						-- This checks if it's NOT the word the user just highlighted
						if caretstart[1] ~= self.Start[1] or caretstart[2] ~= self.Start[2] or
						caretstop[1] ~= self.Caret[1] or caretstop[2] ~= self.Caret[2] then
							local c = colors.word_highlight
							self:HighlightArea({ caretstart, caretstop }, c.r, c.g, c.b, 100)
						end
					end
				end
			end
			return
		elseif self.HighlightedAreasByDoubleClick then
			for i = 1, #self.HighlightedAreasByDoubleClick do
				self:HighlightArea(self.HighlightedAreasByDoubleClick[i])
			end
			self.HighlightedAreasByDoubleClick = nil
		end

		self.tmp = true

		self.LastClick = CurTime()
		self:RequestFocus()
		self.Blink = RealTime()
		self.MouseDown = true

		self.Caret = self:CopyPosition(cursor)
		if not input.IsKeyDown(KEY_LSHIFT) and not input.IsKeyDown(KEY_RSHIFT) then
			self.Start = self:CopyPosition(cursor)
		end
	elseif code == MOUSE_RIGHT then
		self:OpenContextMenu()
	end
end

function PANEL:OnMouseReleased(code)
	if not self.MouseDown then return end

	if code == MOUSE_LEFT then
		self.MouseDown = nil
		if not self.tmp then return end
		self.Caret = self:CursorToCaret()
	end
end

function PANEL:SetCode(text)
	self.Rows = string_Explode("\n", text)
	if self.Rows[#self.Rows] ~= "" then
		self.Rows[#self.Rows + 1] = ""
	end

	self.Caret = { 1, 1 }
	self.Start = { 1, 1 }
	self.Scroll = { 1, 1 }
	self.Undo = {}
	self.Redo = {}
	self.PaintRows = {}

	self.ScrollBar:SetUp(self.Size[1], #self.Rows - 1)
end

function PANEL:GetCode()
	return string_gsub(table_concat(self.Rows, "\n"), "\r", "")
end

function PANEL:HighlightLine(line, r, g, b, a)
	if not self.HighlightedLines then self.HighlightedLines = {} end
	if not r and self.HighlightedLines[line] then
		self.HighlightedLines[line] = nil
		return true
	elseif r and g and b and a then
		self.HighlightedLines[line] = { r, g, b, a }
		return true
	end
	return false
end
function PANEL:ClearHighlightedLines() self.HighlightedLines = nil end

function PANEL:PaintLine(row, drawpos)
	local lines = #self.Rows
	local usePigments = TabHandler.PigmentsConVar:GetInt()
	if row > lines then return end
	local width, height = self.FontWidth, self.FontHeight
	local startX, startY = self.LineNumberWidth + 5, drawpos*height

	if not self.PaintRows[row] then
		local colored = self:SyntaxColorLine(row, self.PaintRows[row-1] or {})
		self.PaintRows[row] = colored

		local newrow = row+1
		--Let's find end of string/comment
		while colored.unfinished do
			if newrow - row < 50 then
				colored = self:SyntaxColorLine(newrow, self.PaintRows[newrow-1] or {})
				self.PaintRows[newrow] = colored
			else -- If string/comment is above 50 lines long invalidate rest of cache so it gets rebuilt later instead of doing it now
				self.PaintRows[newrow] = false
			end
			newrow = newrow + 1
			if newrow > lines then break end -- End of file
		end
		--[[surface_SetDrawColor(Color(255,0,0))
		surface_DrawRect(startX, startY, self:GetWide() - (self.LineNumberWidth + 5), height)]]
	end


	if row == self.Caret[1] and self.TextEntry:HasFocus() then
		surface_SetDrawColor(colors.line_highlight)
		surface_DrawRect(startX, startY, self:GetWide() - (self.LineNumberWidth + 5), height)
	end

	if self.HighlightedLines and self.HighlightedLines[row] then
		local color = self.HighlightedLines[row]
		surface_SetDrawColor(color[1], color[2], color[3], color[4])
		surface_DrawRect(startX, startY, self:GetWide() - (self.LineNumberWidth + 5), height)
	end

	if self:HasSelection() then
		local start, stop = self:MakeSelection(self:Selection())
		local line, char = start[1], start[2]
		local endline, endchar = stop[1], stop[2]

		surface_SetDrawColor(colors.selection)
		local length = self.Rows[row]:len() - self.Scroll[2] + 1

		char = char - self.Scroll[2]
		endchar = endchar - self.Scroll[2]
		if char < 0 then char = 0 end
		if endchar < 0 then endchar = 0 end

		if row == line and line == endline then
			surface_DrawRect(char * width + startX, startY, width * (endchar - char), height)
		elseif row == line then
			surface_DrawRect(char * width + startX, startY, width * (length - char + 1), height)
		elseif row == endline then
			surface_DrawRect(startX, startY, width * endchar, height)
		elseif row > line and row < endline then
			surface_DrawRect(startX, startY, width * (length + 1), height)
		end
	end

	draw_SimpleText(tostring(row), self.CurrentFont, self.LineNumberWidth - 10, startY, colors.gutter_foreground, TEXT_ALIGN_RIGHT)

	local offset = -self.Scroll[2] + 1
	for i, cell in ipairs(self.PaintRows[row]) do
		if offset > self.Size[2] then return end
		if offset < 0 then -- When there is part of line horizontally begining before our scrolled area
			local length = cell[1]:len()
			if length > -offset then
				local line = cell[1]:sub(1-offset)
				offset = line:len()

				if cell[2][2] then --has background
					surface_SetDrawColor(cell[2][2])
					if usePigments == 1 and cell[3] == "color" then
						surface_DrawRect(startX, startY + height-2, width * offset, 2)
					else
						surface_DrawRect(startX, startY, width * offset, height)
					end
				end

				if cell[2][2] then
					draw_SimpleText(line .. " ", self.CurrentFont .. "_Bold", startX, startY, cell[2][1])
				else
					draw_SimpleText(line .. " ", self.CurrentFont, startX, startY, cell[2][1])
				end
			else
				offset = offset + length
			end
		else
			local length = cell[1]:len()
			if cell[2][2] then --has background
				surface_SetDrawColor(cell[2][2])
				if usePigments == 1 and cell[3] == "color" then
					surface_DrawRect(startX + offset * width, startY + height-2, width * length, 2)
				else
					surface_DrawRect(startX + offset * width, startY, width * length, height)
				end
			end
			if cell[2][3] == 2 then
				draw_SimpleText(cell[1] .. " ", self.CurrentFont .. "_Bold", offset * width + startX, startY, cell[2][1])
			elseif cell[2][3] == 1 then
				draw_SimpleText(cell[1] .. " ", self.CurrentFont .. "_Italic", offset * width + startX, startY, cell[2][1])
			else
				draw_SimpleText(cell[1] .. " ", self.CurrentFont, offset * width + startX, startY, cell[2][1])
			end

			offset = offset + length
		end
	end
	if self.HiddenRows[row+1] then
		draw_SimpleText("<...>", self.CurrentFont, offset * width + startX, startY, Color(64,64,64))
	end
end

function PANEL:PerformLayout()
	self.ScrollBar:SetSize(16, self:GetTall())
	self.ScrollBar:SetPos(self:GetWide() - 16, 0)

	self.Size[1] = math_floor(self:GetTall() / self.FontHeight) - 1
	self.Size[2] = math_floor((self:GetWide() - (self.LineNumberWidth + 6) - 16) / self.FontWidth) - 1

	self.ScrollBar:SetUp(self.Size[1], #self.Rows - 1)
end

function PANEL:HighlightArea(area, r, g, b, a)
	if not self.HighlightedAreas then self.HighlightedAreas = {} end
	if not r then
		local _start, _stop = area[1], area[2]
		for k, v in pairs(self.HighlightedAreas) do
			local start = v[1][1]
			local stop = v[1][2]
			if start[1] == _start[1] and start[2] == _start[2] and stop[1] == _stop[1] and stop[2] == _stop[2] then
				table.remove(self.HighlightedAreas, k)
				break
			end
		end
		return true
	elseif r and g and b and a then
		self.HighlightedAreas[#self.HighlightedAreas + 1] = { area, r, g, b, a }
		return true
	end
	return false
end
function PANEL:ClearHighlightedAreas() self.HighlightedAreas = nil end

function PANEL:PaintTextOverlay()

	if self.TextEntry:HasFocus() and self.Caret[2] - self.Scroll[2] >= 0 then
		local width, height = self.FontWidth, self.FontHeight

		if (RealTime() - self.Blink) % 0.8 < 0.4 then
			surface_SetDrawColor(colors.caret)
			local y = self.Caret[1]
			y = (self.Caret[1] - self:GetRowOffset(y) - self.Scroll[1]) * height
			surface_DrawRect((self.Caret[2] - self.Scroll[2]) * width + self.LineNumberWidth + 6, y, 1, height)
		end

		-- Area highlighting
		if self.HighlightedAreas then
			local xofs = self.LineNumberWidth + 6
			for key, data in pairs(self.HighlightedAreas) do
				local area, r, g, b, a = data[1], data[2], data[3], data[4], data[5]
				surface_SetDrawColor(r, g, b, a)
				local start, stop = self:MakeSelection(area)

				if start[1] == stop[1] then -- On the same line
					surface_DrawRect(xofs + (start[2]-self.Scroll[2]) * width, (start[1]-self.Scroll[1]) * height + 1, (stop[2]-start[2]) * width, 1)
					surface_DrawRect(xofs + (start[2]-self.Scroll[2]) * width, (start[1]-self.Scroll[1]) * height + height - 2, (stop[2]-start[2]) * width, 1)

					surface_DrawRect(xofs + (start[2]-self.Scroll[2]) * width + (stop[2]-start[2]) * width - 1, (start[1]-self.Scroll[1]) * height + 1, 1, height-2)
					surface_DrawRect(xofs + (start[2]-self.Scroll[2]) * width, (start[1]-self.Scroll[1]) * height + 1, 1, height-2)

				elseif start[1] < stop[1] then -- Ends below start
					for i = start[1], stop[1] do
						if i == start[1] then
							surface_DrawRect(xofs + (start[2]-self.Scroll[2]) * width, (i-self.Scroll[1]) * height, (#self.Rows[start[1]]-start[2]) * width, height)
						elseif i == stop[1] then
							surface_DrawRect(xofs + (self.Scroll[2]-1) * width, (i-self.Scroll[1]) * height, (#self.Rows[stop[1]]-stop[2]) * width, height)
						else
							surface_DrawRect(xofs + (self.Scroll[2]-1) * width, (i-self.Scroll[1]) * height, #self.Rows[i] * width, height)
						end
					end
				end
			end
		end

		-- Bracket highlighting by: {Jeremydeath}
		local WindowText = self:GetCode()
		local LinePos = table_concat(self.Rows, "\n", 1, self.Caret[1]-1):len()
		local CaretPos = LinePos + self.Caret[2] + 1

		local BracketPairs = {
			["{"] = "}",
			["}"] = "{",
			["["] = "]",
			["]"] = "[",
			["("] = ")",
			[")"] = "("
		}

		local CaretChars = WindowText:sub(CaretPos-1, CaretPos)
		local BrackSt, BrackEnd = CaretChars:find("[%(%){}%[%]]")

		local Bracket = false
		if BrackSt and BrackSt ~= 0 then
			Bracket = CaretChars:sub(BrackSt or 0, BrackEnd or 0)
		end
		if Bracket and BracketPairs[Bracket] then
			local End = 0
			local EndX = 1
			local EndLine = 1
			local StartX = 1

			if Bracket == "(" or Bracket == "[" or Bracket == "{" then
				BrackSt, End = WindowText:find("%b"..Bracket..BracketPairs[Bracket], CaretPos-1)

				if BrackSt and End then
					local OffsetSt = 1

					local BracketLines = string_Explode("\n", WindowText:sub(BrackSt, End))

					EndLine = self.Caret[1] + #BracketLines-1

					EndX = End-LinePos-2
					if #BracketLines>1 then
						EndX = BracketLines[#BracketLines]:len()-1
					end

					if Bracket == "{" then
						OffsetSt = 0
					end

					if (CaretPos - BrackSt) >= 0 and (CaretPos - BrackSt) <= 1 then
						local width, height = self.FontWidth, self.FontHeight
						local StartX = BrackSt - LinePos - 2
						surface_SetDrawColor(255, 0, 0, 50)
						surface_DrawRect((StartX-(self.Scroll[2]-1)) * width + self.LineNumberWidth + self.FontWidth + OffsetSt - 1, (self.Caret[1] - self.Scroll[1]) * height + 1, width-2, height-2)
						surface_DrawRect((EndX-(self.Scroll[2]-1)) * width + self.LineNumberWidth + 6, (EndLine - self.Scroll[1]) * height + 1, width-2, height-2)
					end
				end
			elseif Bracket == ")" or Bracket == "]" or Bracket == "}" then
				BrackSt, End = WindowText:reverse():find("%b"..Bracket..BracketPairs[Bracket], -CaretPos)
				if BrackSt and End then
					local len = WindowText:len()
					End = len-End + 1
					BrackSt = len-BrackSt + 1
					local BracketLines = string_Explode("\n", WindowText:sub(End, BrackSt))

					EndLine = self.Caret[1]-#BracketLines + 1

					local OffsetSt = -1

					EndX = End-LinePos-2
					if #BracketLines>1 then
						local PrevText = WindowText:sub(1, End):reverse()

						EndX = (PrevText:find("\n", 1, true) or 2)-2
					end

					if Bracket ~= "}" then
						OffsetSt = 0
					end

					if (CaretPos - BrackSt) >= 0 and (CaretPos - BrackSt) <= 1 then
						local width, height = self.FontWidth, self.FontHeight
						local StartX = BrackSt - LinePos - 2
						surface_SetDrawColor(255, 0, 0, 50)
						surface_DrawRect((StartX-(self.Scroll[2]-1)) * width + self.LineNumberWidth + self.FontWidth - 2, (self.Caret[1] - self.Scroll[1]) * height + 1, width-2, height-2)
						surface_DrawRect((EndX-(self.Scroll[2]-1)) * width + self.LineNumberWidth + 8 + OffsetSt, (EndLine - self.Scroll[1]) * height + 1, width-2, height-2)
					end
				end
			end
		end
	end
end

local display_caret_pos = CreateClientConVar("sf_editor_wire_display_caret_pos", "0", true, false)

function PANEL:Paint()
	self.LineNumberWidth = self.FontWidth * math.max(#tostring(self.Scroll[1] + self.Size[1] + 1),3) + 20

	if not input.IsMouseDown(MOUSE_LEFT) then
		self:OnMouseReleased(MOUSE_LEFT)
	end

	if not self.PaintRows then
		self.PaintRows = {}
	end

	if self.MouseDown then
		self.Caret = self:CursorToCaret()
	end

	surface_SetDrawColor(colors.gutter_background)
	surface_DrawRect(0, 0, self.LineNumberWidth + 4, self:GetTall())

	surface_SetDrawColor(colors.gutter_divider)
	surface_DrawRect(self.LineNumberWidth + 4, 0, 1, self:GetTall())

	surface_SetDrawColor(colors.background)
	surface_DrawRect(self.LineNumberWidth + 5, 0, self:GetWide() - (self.LineNumberWidth + 5), self:GetTall())

	self.Scroll[1] = math_floor(self.ScrollBar:GetScroll() + 1)

	local i = self.Scroll[1]
	local drawn = 0
	local offset = 0
	while drawn < self.Size[1] + 4 do
		if self.HiddenRows[i] then
			i = i + 1
			offset = offset + 1
			continue
		end
		self.RealLine[drawn] = i
		self.RowOffset[i] = offset
		self:PaintLine(i,drawn)
		drawn = drawn + 1
		i = i+1
	end


	-- Paint the overlay of the text (bracket highlighting and carret postition)
	self:PaintTextOverlay()

	if display_caret_pos:GetBool() then
		local str = "Length: " .. #self:GetCode() .. " Lines: " .. #self.Rows .. " Ln: " .. self.Caret[1] .. " Col: " .. self.Caret[2]
		if self:HasSelection() then
			str = str .. " Sel: " .. #self:GetSelection()
		end
		surface_SetFont("Default")
		local w, h = surface_GetTextSize(str)
		local _w, _h = self:GetSize()
		draw_WordBox(4, _w - w - (self.ScrollBar:IsVisible() and 16 or 0) - 10, _h - h - 10, str, "Default", Color(0, 0, 0, 100), Color(255, 255, 255, 255))
	end

	self:DoAction("Paint")

	return true
end

-- Moves the caret to a new position. Optionally also collapses the selection
-- into a single caret. If maintain_selection is nil, then the selection will
-- be maintained only if Shift is pressed.
function PANEL:SetCaret(caret, maintain_selection)
	self.Caret = self:CopyPosition(caret)

	self.Caret[1] = math.Clamp(self.Caret[1], 1, #self.Rows)
	self.Caret[2] = math.Clamp(self.Caret[2], 1, #self.Rows[self.Caret[1]] + 1)

	if maintain_selection == nil then
		maintain_selection = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
	end

	if not maintain_selection then
		self.Start = self:CopyPosition(self.Caret)
	end

	self:ScrollCaret()
end

function PANEL:CopyPosition(caret)
	return { caret[1], caret[2] }
end

function PANEL:MovePosition(caret, offset)
	local row, col = caret[1], caret[2]

	if offset > 0 then
		local numRows = #self.Rows
		while true do
			local length = #(self.Rows[row]) - col + 2
			if offset < length then
				col = col + offset
				break
			elseif row == numRows then
				col = col + length - 1
				break
			else
				offset = offset - length
				row = row + 1
				col = 1
			end
		end
	elseif offset < 0 then
		offset = -offset

		while true do
			if offset < col then
				col = col - offset
				break
			elseif row == 1 then
				col = 1
				break
			else
				offset = offset - col
				row = row - 1
				col = #(self.Rows[row]) + 1
			end
		end
	end

	return { row, col }
end

function PANEL:HasSelection()
	return self.Caret[1] ~= self.Start[1] or self.Caret[2] ~= self.Start[2]
end

function PANEL:Selection()
	return { { self.Caret[1], self.Caret[2] }, { self.Start[1], self.Start[2] } }
end

function PANEL:MakeSelection(selection)
	local start, stop = selection[1], selection[2]

	if start[1] < stop[1] or (start[1] == stop[1] and start[2] < stop[2]) then
		return start, stop
	else
		return stop, start
	end
end

function PANEL:GetArea(selection)
	local start, stop = self:MakeSelection(selection)

	if start[1] == stop[1] then
		return string_sub(self.Rows[start[1]], start[2], stop[2] - 1)
	else
		local text = string_sub(self.Rows[start[1]], start[2])

		for i = start[1] + 1, stop[1]-1 do
			text = text .. "\n" .. self.Rows[i]
		end

		return text .. "\n" .. string_sub(self.Rows[stop[1]], 1, stop[2] - 1)
	end
end
function PANEL:RecacheLine(line)
	local rows = #self.Rows
	while self.PaintRows[line] and self.PaintRows[line]["unfinished"] do
		self.PaintRows[line] = false
		line = line + 1
		if line > rows then return end
	end
	self.PaintRows[line] = false
end
function PANEL:SetArea(selection, text, isundo, isredo, before, after)
	local start, stop = self:MakeSelection(selection)

	local buffer = self:GetArea(selection)

	if start[1] ~= stop[1] or start[2] ~= stop[2] then
		-- clear selection
		self.Rows[start[1]] = string_sub(self.Rows[start[1]], 1, start[2] - 1) .. string_sub(self.Rows[stop[1]], stop[2])
		self:RecacheLine(start[1])

		for i = start[1] + 1, stop[1] do
			table_remove(self.Rows, start[1] + 1)
			table_remove(self.PaintRows, start[1] + 1)
		end

		-- add empty row at end of file (TODO!)
		if self.Rows[#self.Rows] ~= "" then
			self.Rows[#self.Rows + 1] = ""
			self:RecacheLine(#self.Rows + 1)
		end
	end

	if not text or text == "" then
		self.ScrollBar:SetUp(self.Size[1], #self.Rows - 1)

		self:OnTextChanged()

		if isredo then
			self.Undo[#self.Undo + 1] = { { self:CopyPosition(start), self:CopyPosition(start) }, buffer, after, before }
			return before
		elseif isundo then
			self.Redo[#self.Redo + 1] = { { self:CopyPosition(start), self:CopyPosition(start) }, buffer, after, before }
			return before
		else
			self.Redo = {}
			self.Undo[#self.Undo + 1] = { { self:CopyPosition(start), self:CopyPosition(start) }, buffer, self:CopyPosition(selection[1]), self:CopyPosition(start) }
			return start
		end
	end

	-- insert text
	local rows = string_Explode("\n", text)

	local remainder = string_sub(self.Rows[start[1]], start[2])
	self.Rows[start[1]] = string_sub(self.Rows[start[1]], 1, start[2] - 1) .. rows[1]
	self:RecacheLine(start[1])

	for i = 2, #rows do
		table_insert(self.Rows, start[1] + i - 1, rows[i])
		table_insert(self.PaintRows, start[1] + i - 1, false)
	end

	local stop = { start[1] + #rows - 1, #(self.Rows[start[1] + #rows - 1]) + 1 }

	self.Rows[stop[1]] = self.Rows[stop[1]] .. remainder
	self:RecacheLine(stop[1])

	-- add empty row at end of file (TODO!)
	if self.Rows[#self.Rows] ~= "" then
		self.Rows[#self.Rows + 1] = ""
		self:RecacheLine(#self.Rows + 1)
	end

	self.ScrollBar:SetUp(self.Size[1], #self.Rows - 1)


	self:OnTextChanged()

	if isredo then
		self.Undo[#self.Undo + 1] = { { self:CopyPosition(start), self:CopyPosition(stop) }, buffer, after, before }
		return before
	elseif isundo then
		self.Redo[#self.Redo + 1] = { { self:CopyPosition(start), self:CopyPosition(stop) }, buffer, after, before }
		return before
	else
		self.Redo = {}
		self.Undo[#self.Undo + 1] = { { self:CopyPosition(start), self:CopyPosition(stop) }, buffer, self:CopyPosition(selection[1]), self:CopyPosition(stop) }
		return stop
	end
end

function PANEL:GetSelection()
	return self:GetArea(self:Selection())
end

function PANEL:SetSelection(text)
	self:SetCaret(self:SetArea(self:Selection(), text), false)
end

function PANEL:OnTextChanged()
end

function PANEL:_OnLoseFocus()
	if self.TabFocus then
		self:RequestFocus()
		self.TabFocus = nil
	end
end

-- removes the first 0-4 spaces from a string and returns it
local function unindent(line)
	--local i = line:find("%S")
	--if i == nil or i > 5 then i = 5 end
	--return line:sub(i)
	return line:match("^ ? ? ? ?(.*)$")
end

function PANEL:_OnTextChanged()
	local ctrlv = false
	local text = self.TextEntry:GetValue()
	self.TextEntry:SetText("")

	if (input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)) and not (input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)) then
		-- ctrl+[shift+]key
		if input.IsKeyDown(KEY_V) then
			-- ctrl+[shift+]V
			ctrlv = true
		else
			-- ctrl+[shift+]key with key ~= V
			return
		end
	end

	if text == "" then return end
	if not ctrlv then
		if text == "\n" or text == "`" then return end
		if text == "}" and GetConVarNumber('sf_editor_wire_autoindent') ~= 0 then
			self:SetSelection(text)
			local row = self.Rows[self.Caret[1]]
			if string_match("{" .. row, "^%b{}.*$") then
				local newrow = unindent(row)
				self.Rows[self.Caret[1]] = newrow
				self.Caret[2] = self.Caret[2] + newrow:len()-row:len()
				self.Start[2] = self.Caret[2]
			end
			return
		end
	end

	self:SetSelection(text)
	SF.Editor.editor:Validate(false)

end

function PANEL:OnMouseWheeled(delta)
	self.Scroll[1] = self.Scroll[1] - 4 * delta
	if self.Scroll[1] < 1 then self.Scroll[1] = 1 end
	if self.Scroll[1] > #self.Rows then self.Scroll[1] = #self.Rows end
	self.ScrollBar:SetScroll(self.Scroll[1] - 1)
end

function PANEL:OnShortcut()
end

function PANEL:ScrollCaret()
	if self.Caret[1] - self.Scroll[1] < 2 then
		self.Scroll[1] = self.Caret[1] - 2
		if self.Scroll[1] < 1 then self.Scroll[1] = 1 end
	end

	if self.Caret[1] - self.Scroll[1] > self.Size[1] - 2 then
		self.Scroll[1] = self.Caret[1] - self.Size[1] + 2
		if self.Scroll[1] < 1 then self.Scroll[1] = 1 end
	end

	if self.Caret[2] - self.Scroll[2] < 4 then
		self.Scroll[2] = self.Caret[2] - 4
		if self.Scroll[2] < 1 then self.Scroll[2] = 1 end
	end

	if self.Caret[2] - 1 - self.Scroll[2] > self.Size[2] - 4 then
		self.Scroll[2] = self.Caret[2] - 1 - self.Size[2] + 4
		if self.Scroll[2] < 1 then self.Scroll[2] = 1 end
	end

	self.ScrollBar:SetScroll(self.Scroll[1] - 1)
end

-- Initialize find settings
local wire_expression2_editor_find_use_patterns = CreateClientConVar("wire_expression2_editor_find_use_patterns", "0", true, false)
local wire_expression2_editor_find_ignore_case = CreateClientConVar("wire_expression2_editor_find_ignore_case", "0", true, false)
local wire_expression2_editor_find_whole_word_only = CreateClientConVar("wire_expression2_editor_find_whole_word_only", "0", true, false)
local wire_expression2_editor_find_wrap_around = CreateClientConVar("wire_expression2_editor_find_wrap_around", "0", true, false)
local wire_expression2_editor_find_dir = CreateClientConVar("wire_expression2_editor_find_dir", "1", true, false)

function PANEL:HighlightFoundWord(caretstart, start, stop)
	local caretstart = caretstart or self:CopyPosition(self.Start)
	if istable(start) then
		self.Start = self:CopyPosition(start)
	elseif isnumber(start) then
		self.Start = self:MovePosition(caretstart, start)
	end
	if istable(stop) then
		self.Caret = { stop[1], stop[2] + 1 }
	elseif isnumber(stop) then
		self.Caret = self:MovePosition(caretstart, stop + 1)
	end
	self:ScrollCaret()
end

function PANEL:Find(str, looped)
	if looped and looped >= 2 then return end
	if str == "" then return end
	local _str = str

	local use_patterns = wire_expression2_editor_find_use_patterns:GetBool()
	local ignore_case = wire_expression2_editor_find_ignore_case:GetBool()
	local whole_word_only = wire_expression2_editor_find_whole_word_only:GetBool()
	local wrap_around = wire_expression2_editor_find_wrap_around:GetBool()
	local dir = wire_expression2_editor_find_dir:GetBool()

	-- Check if the match exists anywhere at all
	local temptext = self:GetCode()
	if ignore_case then
		temptext = temptext:lower()
		str = str:lower()
	end
	local _start, _stop = temptext:find(str, 1, not use_patterns)
	if not _start or not _stop then return false end

	if dir then -- Down
		local line = self.Rows[self.Start[1]]
		local text = line:sub(self.Start[2]) .. "\n"
		text = text .. table_concat(self.Rows, "\n", self.Start[1] + 1)
		if ignore_case then text = text:lower() end

		local offset = 2
		for loop = 1, 100 do
			local start, stop = text:find(str, offset, not use_patterns)
			if start and stop then

				if whole_word_only then
					local caretstart = self:MovePosition(self.Start, start)
					caretstart = { caretstart[1], caretstart[2]-1 }
					local caretstop = self:MovePosition(self.Start, stop)
					caretstop = { caretstop[1], caretstop[2]-1 }
					local wstart = self:getWordStart({ caretstart[1], caretstart[2] + 1 })
					local wstop = self:getWordEnd({ caretstart[1], caretstart[2] + 1 })
					if caretstart[1] == wstart[1] and caretstop[1] == wstop[1] and
					caretstart[2] == wstart[2] and caretstop[2] + 1 == wstop[2] then
						self:HighlightFoundWord(nil, caretstart, caretstop)
						return true
					else
						offset = start + 1
					end
				else
					self:HighlightFoundWord(nil, start-1, stop-1)
					return true
				end

			else
				break
			end
			if loop == 100 then error("\nInfinite loop protection enabled.\nPlease provide a detailed description of what you were doing when you got this error on www.wiremod.com.\n") return end
		end

		if wrap_around then
			self:SetCaret({ 1, 1 }, false)
			self:Find(_str, (looped or 0) + 1)
		end
	else -- Up
		local text = table_concat(self.Rows, "\n", 1, self.Start[1]-1)
		local line = self.Rows[self.Start[1]]
		text = text .. "\n" .. line:sub(1, self.Start[2]-1)

		str = string_reverse(str)
		text = string_reverse(text)

		if ignore_case then text = text:lower() end

		local offset = 2
		for loop = 1, 100 do
			local start, stop = text:find(str, offset, not use_patterns)
			if start and stop then

				if whole_word_only then
					local caretstart = self:MovePosition(self.Start, -start)
					caretstart = { caretstart[1], caretstart[2]-1 }
					local caretstop = self:MovePosition(self.Start, -stop)
					caretstop = { caretstop[1], caretstop[2]-1 }
					local wstart = self:getWordStart({ caretstart[1], caretstart[2] + 1 })
					local wstop = self:getWordEnd({ caretstart[1], caretstart[2] + 1 })
					if caretstart[1] == wstart[1] and caretstop[1] == wstop[1] and
					caretstart[2] == wstart[2] and caretstop[2] + 1 == wstop[2] then
						self:HighlightFoundWord(nil, caretstart, caretstop)
						return true
					else
						offset = start + 1
					end
				else
					self:HighlightFoundWord(nil, -(start-1), -(stop + 1))
					return true
				end

			else
				break
			end
			if loop == 100 then error("\nInfinite loop protection enabled.\nPlease provide a detailed description of what you were doing when you got this error on www.wiremod.com.\n") return end
		end

		if wrap_around then
			self:SetCaret({ #self.Rows, #self.Rows[#self.Rows] }, false)
			self:Find(_str, (looped or 0) + 1)
		end
	end
	return false
end

function PANEL:Replace(str, replacewith)
	if str == "" or str == replacewith then return end

	local ignore_case = wire_expression2_editor_find_ignore_case:GetBool()
	local use_patterns = wire_expression2_editor_find_use_patterns:GetBool()

	local selection = self:GetSelection()

	local _str = str
	if not use_patterns then
		str = str:gsub("[%-%^%$%(%)%%%.%[%]%*%+%?]", "%%%1")
		replacewith = replacewith:gsub("%%", "%%%1")
	end

	if selection:match(str) ~= nil then
		self:SetSelection(selection:gsub(str, replacewith))
		return self:Find(_str)
	else
		return self:Find(_str)
	end
end

function PANEL:ReplaceAll(str, replacewith)
	if str == "" then return end

	local whole_word_only = wire_expression2_editor_find_whole_word_only:GetBool()
	local ignore_case = wire_expression2_editor_find_ignore_case:GetBool()
	local use_patterns = wire_expression2_editor_find_use_patterns:GetBool()

	if not use_patterns then
		str = str:gsub("[%-%^%$%(%)%%%.%[%]%*%+%?]", "%%%1")
		replacewith = replacewith:gsub("%%", "%%%1")
	end

	local txt = self:GetCode()

	if ignore_case then
		local txt2 = txt -- Store original cased copy
		str = str:lower() -- Lowercase everything
		txt = txt:lower() -- Lowercase everything

		local pattern = "()"..str.."()"
		if whole_word_only then pattern = "[^a-zA-Z0-9_]()"..str.."()[^a-zA-Z0-9_]" end

		local positions = {}

		for startpos, endpos in string_gmatch(txt, pattern) do
			positions[#positions + 1] = { startpos, endpos }
		end

		-- Do the replacing backwards, or it won't work
		for i = #positions, 1, -1 do
			local startpos, endpos = positions[i][1], positions[i][2]
			txt2 = string_sub(txt2, 1, startpos-1) .. replacewith .. string_sub(txt2, endpos)
		end

		-- Replace everything with the edited copy
		self:SelectAll()
		self:SetSelection(txt2)
	else
		if whole_word_only then
			local pattern = "([^a-zA-Z0-9_])"..str.."([^a-zA-Z0-9_])"
			txt = " " .. txt
			txt = string_gsub(txt, pattern, "%1"..replacewith.."%2")
			txt = string_gsub(txt, pattern, "%1"..replacewith.."%2")
			txt = string_sub(txt, 2)
		else
			txt = string_gsub(txt, str, replacewith)
		end

		self:SelectAll()
		self:SetSelection(txt)
	end
end

function PANEL:CountFinds(str)
	if str == "" then return 0 end

	local whole_word_only = wire_expression2_editor_find_whole_word_only:GetBool()
	local ignore_case = wire_expression2_editor_find_ignore_case:GetBool()
	local use_patterns = wire_expression2_editor_find_use_patterns:GetBool()

	if not use_patterns then
		str = str:gsub("[%-%^%$%(%)%%%.%[%]%*%+%?]", "%%%1")
	end

	local txt = self:GetCode()

	if ignore_case then
		txt = txt:lower()
		str = str:lower()
	end

	if whole_word_only then
		local pattern = "([^a-zA-Z0-9_])"..str.."([^a-zA-Z0-9_])"
		txt = " " .. txt
		local num1, num2 = 0, 0
		txt, num1 = txt:gsub(pattern, "%1%2")
		if txt == "" then return num1 end
		txt, num2 = txt:gsub(pattern, "%1%2")
		return num1 + num2
	else
		local num
		txt, num = txt:gsub(str, "")
		return num
	end
end

function PANEL:FindAllWords(str)
	if str == "" then return end

	local txt = self:GetCode()
	-- [^a-zA-Z0-9_] ensures we only find whole words, and the gsub escapes any regex command characters that happen to be in str
	local pattern = "[^a-zA-Z0-9_]()" .. str:gsub("[%-%^%$%(%)%%%.%[%]%*%+%?]", "%%%1") .. "()[^a-zA-Z0-9_]"

	local ret = {}
	for start, stop in txt:gmatch(pattern) do
		ret[#ret + 1] = { start, stop }
	end

	return ret
end

function PANEL:CreateFindWindow()
	self.FindWindow = vgui.Create("DFrame", self)

	local pnl = self.FindWindow
	pnl:SetSize(322, 201)
	pnl:ShowCloseButton(true)
	pnl:SetDeleteOnClose(false) -- No need to create a new window every time
	pnl:MakePopup() -- Make it separate from the editor itself
	pnl:SetVisible(false) -- but hide it for now
	pnl:SetTitle("Find")
	pnl:SetScreenLock(true)

	local old = pnl.Close
	function pnl.Close()
		self.ForceDrawCursor = false
		old(pnl)
	end

	-- Center it above the editor
	local x, y = self:GetParent():GetPos()
	local w, h = self:GetSize()
	pnl:SetPos(x + w / 2-150, y + h / 2-100)

	pnl.TabHolder = vgui.Create("DPropertySheet", pnl)
	pnl.TabHolder:StretchToParent(1, 23, 1, 1)

	-- Options
	local common_panel = vgui.Create("DPanel", pnl)
	common_panel:SetSize(225, 60)
	common_panel:SetPos(10, 130)
	common_panel.Paint = function()
		local w, h = common_panel:GetSize()
		draw_RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 150))
	end

	local use_patterns = vgui.Create("DCheckBoxLabel", common_panel)
	use_patterns:SetText("Use Patterns")
	use_patterns:SetToolTip("Use/Don't use Lua patterns in the find.")
	use_patterns:SizeToContents()
	use_patterns:SetConVar("wire_expression2_editor_find_use_patterns")
	use_patterns:SetPos(4, 4)
	local old = use_patterns.Button.SetValue
	use_patterns.Button.SetValue = function(pnl, b)
		if wire_expression2_editor_find_whole_word_only:GetBool() then return end
		old(pnl, b)
	end

	local case_sens = vgui.Create("DCheckBoxLabel", common_panel)
	case_sens:SetText("Ignore Case")
	case_sens:SetToolTip("Ignore/Don't ignore case in the find.")
	case_sens:SizeToContents()
	case_sens:SetConVar("wire_expression2_editor_find_ignore_case")
	case_sens:SetPos(4, 24)

	local whole_word = vgui.Create("DCheckBoxLabel", common_panel)
	whole_word:SetText("Match Whole Word")
	whole_word:SetToolTip("Match/Don't match the entire word in the find.")
	whole_word:SizeToContents()
	whole_word:SetConVar("wire_expression2_editor_find_whole_word_only")
	whole_word:SetPos(4, 44)
	local old = whole_word.Button.Toggle
	whole_word.Button.Toggle = function(pnl)
		old(pnl)
		if pnl:GetValue() then use_patterns:SetValue(false) end
	end

	local wrap_around = vgui.Create("DCheckBoxLabel", common_panel)
	wrap_around:SetText("Wrap Around")
	wrap_around:SetToolTip("Start/Don't start from the top after reaching the bottom, or the bottom after reaching the top.")
	wrap_around:SizeToContents()
	wrap_around:SetConVar("wire_expression2_editor_find_wrap_around")
	wrap_around:SetPos(130, 4)

	local dir_down = vgui.Create("DCheckBoxLabel", common_panel)
	local dir_up = vgui.Create("DCheckBoxLabel", common_panel)

	dir_up:SetText("Up")
	dir_up:SizeToContents()
	dir_up:SetPos(130, 24)
	dir_up:SetTooltip("Note: Most patterns won't work when searching up because the search function reverses the string to search backwards.")
	dir_up:SetValue(not wire_expression2_editor_find_dir:GetBool())
	dir_down:SetText("Down")
	dir_down:SizeToContents()
	dir_down:SetPos(130, 44)
	dir_down:SetValue(wire_expression2_editor_find_dir:GetBool())

	function dir_up.Button:Toggle()
		dir_up:SetValue(true)
		dir_down:SetValue(false)
		RunConsoleCommand("wire_expression2_editor_find_dir", "0")
	end
	function dir_down.Button:Toggle()
		dir_down:SetValue(true)
		dir_up:SetValue(false)
		RunConsoleCommand("wire_expression2_editor_find_dir", "1")
	end

	-- Find tab
	local findtab = vgui.Create("DPanel")

	-- Label
	local FindLabel = vgui.Create("DLabel", findtab)
	FindLabel:SetText("Find:")
	FindLabel:SetPos(4, 4)
	FindLabel:SetTextColor(Color(0, 0, 0, 255))

	-- Text entry
	local FindEntry = vgui.Create("DTextEntry", findtab)
	FindEntry:SetPos(30, 4)
	FindEntry:SetSize(200, 20)
	FindEntry:RequestFocus()
	FindEntry.OnEnter = function(pnl)
		self:Find(pnl:GetValue())
		pnl:RequestFocus()
	end

	-- Find next button
	local FindNext = vgui.Create("DButton", findtab)
	FindNext:SetText("Find Next")
	FindNext:SetToolTip("Find the next match and highlight it.")
	FindNext:SetPos(233, 4)
	FindNext:SetSize(70, 20)
	FindNext.DoClick = function(pnl)
		self:Find(FindEntry:GetValue())
	end

	-- Find button
	local Find = vgui.Create("DButton", findtab)
	Find:SetText("Find")
	Find:SetToolTip("Find the next match, highlight it, and close the Find window.")
	Find:SetPos(233, 29)
	Find:SetSize(70, 20)
	Find.DoClick = function(pnl)
		self.FindWindow:Close()
		self:Find(FindEntry:GetValue())
	end

	-- Count button
	local Count = vgui.Create("DButton", findtab)
	Count:SetText("Count")
	Count:SetPos(233, 95)
	Count:SetSize(70, 20)
	Count:SetTooltip("Count the number of matches in the file.")
	Count.DoClick = function(pnl)
		Derma_Message(self:CountFinds(FindEntry:GetValue()) .. " matches found.", "", "Ok")
	end

	-- Cancel button
	local Cancel = vgui.Create("DButton", findtab)
	Cancel:SetText("Cancel")
	Cancel:SetPos(233, 120)
	Cancel:SetSize(70, 20)
	Cancel.DoClick = function(pnl)
		self.FindWindow:Close()
	end

	pnl.FindTab = pnl.TabHolder:AddSheet("Find", findtab, "icon16/page_white_find.png", false, false)
	pnl.FindTab.Entry = FindEntry

	-- Replace tab
	local replacetab = vgui.Create("DPanel")

	-- Label
	local FindLabel = vgui.Create("DLabel", replacetab)
	FindLabel:SetText("Find:")
	FindLabel:SetPos(4, 4)
	FindLabel:SetTextColor(Color(0, 0, 0, 255))

	-- Text entry
	local FindEntry = vgui.Create("DTextEntry", replacetab)
	local ReplaceEntry
	FindEntry:SetPos(30, 4)
	FindEntry:SetSize(200, 20)
	FindEntry:RequestFocus()
	FindEntry.OnEnter = function(pnl)
		self:Replace(pnl:GetValue(), ReplaceEntry:GetValue())
		ReplaceEntry:RequestFocus()
	end

	-- Label
	local ReplaceLabel = vgui.Create("DLabel", replacetab)
	ReplaceLabel:SetText("Replace With:")
	ReplaceLabel:SetPos(4, 32)
	ReplaceLabel:SizeToContents()
	ReplaceLabel:SetTextColor(Color(0, 0, 0, 255))

	-- Replace entry
	ReplaceEntry = vgui.Create("DTextEntry", replacetab)
	ReplaceEntry:SetPos(75, 29)
	ReplaceEntry:SetSize(155, 20)
	ReplaceEntry:RequestFocus()
	ReplaceEntry.OnEnter = function(pnl)
		self:Replace(FindEntry:GetValue(), pnl:GetValue())
		pnl:RequestFocus()
	end

	-- Find next button
	local FindNext = vgui.Create("DButton", replacetab)
	FindNext:SetText("Find Next")
	FindNext:SetToolTip("Find the next match and highlight it.")
	FindNext:SetPos(233, 4)
	FindNext:SetSize(70, 20)
	FindNext.DoClick = function(pnl)
		self:Find(FindEntry:GetValue())
	end

	-- Replace next button
	local ReplaceNext = vgui.Create("DButton", replacetab)
	ReplaceNext:SetText("Replace")
	ReplaceNext:SetToolTip("Replace the current selection if it matches, else find the next match.")
	ReplaceNext:SetPos(233, 29)
	ReplaceNext:SetSize(70, 20)
	ReplaceNext.DoClick = function(pnl)
		self:Replace(FindEntry:GetValue(), ReplaceEntry:GetValue())
	end

	-- Replace all button
	local ReplaceAll = vgui.Create("DButton", replacetab)
	ReplaceAll:SetText("Replace All")
	ReplaceAll:SetToolTip("Replace all occurences of the match in the entire file, and close the Find window.")
	ReplaceAll:SetPos(233, 54)
	ReplaceAll:SetSize(70, 20)
	ReplaceAll.DoClick = function(pnl)
		self.FindWindow:Close()
		self:ReplaceAll(FindEntry:GetValue(), ReplaceEntry:GetValue())
	end

	-- Count button
	local Count = vgui.Create("DButton", replacetab)
	Count:SetText("Count")
	Count:SetPos(233, 95)
	Count:SetSize(70, 20)
	Count:SetTooltip("Count the number of matches in the file.")
	Count.DoClick = function(pnl)
		Derma_Message(self:CountFinds(FindEntry:GetValue()) .. " matches found.", "", "Ok")
	end

	-- Cancel button
	local Cancel = vgui.Create("DButton", replacetab)
	Cancel:SetText("Cancel")
	Cancel:SetPos(233, 120)
	Cancel:SetSize(70, 20)
	Cancel.DoClick = function(pnl)
		self.FindWindow:Close()
	end

	pnl.ReplaceTab = pnl.TabHolder:AddSheet("Replace", replacetab, "icon16/page_white_wrench.png", false, false)
	pnl.ReplaceTab.Entry = FindEntry

	-- Go to line tab
	local gototab = vgui.Create("DPanel")

	-- Label
	local GotoLabel = vgui.Create("DLabel", gototab)
	GotoLabel:SetText("Go to Line:")
	GotoLabel:SetPos(4, 4)
	GotoLabel:SetTextColor(Color(0, 0, 0, 255))

	-- Text entry
	local GoToEntry = vgui.Create("DTextEntry", gototab)
	GoToEntry:SetPos(57, 4)
	GoToEntry:SetSize(173, 20)
	GoToEntry:SetNumeric(true)

	-- Goto Button
	local Goto = vgui.Create("DButton", gototab)
	Goto:SetText("Go to Line")
	Goto:SetPos(233, 4)
	Goto:SetSize(70, 20)

	-- Action
	local function GoToAction(panel)
		local val = tonumber(GoToEntry:GetValue())
		if val then
			val = math_Clamp(val, 1, #self.Rows)
			self:SetCaret({ val, #self.Rows[val] + 1 }, false)
		end
		GoToEntry:SetText(tostring(val))
		self.FindWindow:Close()
	end
	GoToEntry.OnEnter = GoToAction
	Goto.DoClick = GoToAction

	pnl.GoToLineTab = pnl.TabHolder:AddSheet("Go to Line", gototab, "icon16/page_white_go.png", false, false)
	pnl.GoToLineTab.Entry = GoToEntry

	-- Tab buttons
	local old = pnl.FindTab.Tab.OnMousePressed
	pnl.FindTab.Tab.OnMousePressed = function(...)
		pnl.FindTab.Entry:SetText(pnl.ReplaceTab.Entry:GetValue() or "")
		local active = pnl.TabHolder:GetActiveTab()
		if active == pnl.GoToLineTab.Tab then
			pnl:SetHeight(200)
			pnl.TabHolder:StretchToParent(1, 23, 1, 1)
		end
		old(...)
	end

	local old = pnl.ReplaceTab.Tab.OnMousePressed
	pnl.ReplaceTab.Tab.OnMousePressed = function(...)
		pnl.ReplaceTab.Entry:SetText(pnl.FindTab.Entry:GetValue() or "")
		local active = pnl.TabHolder:GetActiveTab()
		if active == pnl.GoToLineTab.Tab then
			pnl:SetHeight(200)
			pnl.TabHolder:StretchToParent(1, 23, 1, 1)
		end
		old(...)
	end

	local old = pnl.GoToLineTab.Tab.OnMousePressed
	pnl.GoToLineTab.Tab.OnMousePressed = function(...)
		pnl:SetHeight(86)
		pnl.TabHolder:StretchToParent(1, 23, 1, 1)
		pnl.GoToLineTab.Entry:SetText(self.Caret[1])
		old(...)
	end
end

function PANEL:OpenFindWindow(mode)
	if not self.FindWindow then self:CreateFindWindow() end
	self.FindWindow:SetVisible(true)
	self.FindWindow:MakePopup() -- This will move it above the E2 editor if it is behind it.
	self.ForceDrawCursor = true

	local selection = self:GetSelection():Left(100)

	if mode == "find" then
		if selection and selection ~= "" then self.FindWindow.FindTab.Entry:SetText(selection) end
		self.FindWindow.TabHolder:SetActiveTab(self.FindWindow.FindTab.Tab)
		self.FindWindow.FindTab.Entry:RequestFocus()
		self.FindWindow:SetHeight(201)
		self.FindWindow.TabHolder:StretchToParent(1, 23, 1, 1)
	elseif mode == "find and replace" then
		if selection and selection ~= "" then self.FindWindow.ReplaceTab.Entry:SetText(selection) end
		self.FindWindow.TabHolder:SetActiveTab(self.FindWindow.ReplaceTab.Tab)
		self.FindWindow.ReplaceTab.Entry:RequestFocus()
		self.FindWindow:SetHeight(201)
		self.FindWindow.TabHolder:StretchToParent(1, 23, 1, 1)
	elseif mode == "go to line" then
		self.FindWindow.TabHolder:SetActiveTab(self.FindWindow.GoToLineTab.Tab)
		local caretPos = self.Caret[1]
		self.FindWindow.GoToLineTab.Entry:SetText(caretPos)
		self.FindWindow.GoToLineTab.Entry:RequestFocus()
		self.FindWindow.GoToLineTab.Entry:SelectAllText()
		self.FindWindow.GoToLineTab.Entry:SetCaretPos(tostring(caretPos):len())
		self.FindWindow:SetHeight(83)
		self.FindWindow.TabHolder:StretchToParent(1, 23, 1, 1)
	end
end

function PANEL:CanUndo()
	return #self.Undo > 0
end

function PANEL:DoUndo()
	if #self.Undo > 0 then
		local undo = self.Undo[#self.Undo]
		self.Undo[#self.Undo] = nil

		self:SetCaret(self:SetArea(undo[1], undo[2], true, false, undo[3], undo[4]), false)
	end
end

function PANEL:CanRedo()
	return #self.Redo > 0
end

function PANEL:DoRedo()
	if #self.Redo > 0 then
		local redo = self.Redo[#self.Redo]
		self.Redo[#self.Redo] = nil

		self:SetCaret(self:SetArea(redo[1], redo[2], false, true, redo[3], redo[4]), false)
	end
end

function PANEL:SelectAll()
	self.Caret = { #self.Rows, #(self.Rows[#self.Rows]) + 1 }
	self.Start = { 1, 1 }
	self:ScrollCaret()
end

function PANEL:PasteCode(code)
	local tab_scroll = self:CopyPosition(self.Scroll)
	local tab_start, tab_caret = self:MakeSelection(self:Selection())
	self:SetSelection(code)

	self.Scroll = self:CopyPosition(tab_scroll)
	-- trigger scroll bar update (TODO: find a better way)
	self:ScrollCaret()
end

function PANEL:Indent(shift)
	-- TAB with a selection --
	-- remember scroll position
	local tab_scroll = self:CopyPosition(self.Scroll)

	-- normalize selection, so it spans whole lines
	local tab_start, tab_caret = self:MakeSelection(self:Selection())
	tab_start[2] = 1

	if tab_caret[2] ~= 1 then
		tab_caret[1] = tab_caret[1] + 1
		tab_caret[2] = 1
	end

	-- remember selection
	self.Caret = self:CopyPosition(tab_caret)
	self.Start = self:CopyPosition(tab_start)
	-- (temporarily) adjust selection, so there is no empty line at its end.
	if self.Caret[2] == 1 then
		self.Caret = self:MovePosition(self.Caret, -1)
	end
	if shift then
		-- shift-TAB with a selection --
		local tmp = self:GetSelection():gsub("\n ? ? ? ?", "\n")

		-- makes sure that the first line is outdented
		self:SetSelection(unindent(tmp))
	else
		-- plain TAB with a selection --
		self:SetSelection("    " .. self:GetSelection():gsub("\n", "\n    "))
	end
	-- restore selection
	self.Caret = self:CopyPosition(tab_caret)
	self.Start = self:CopyPosition(tab_start)
	-- restore scroll position
	self.Scroll = self:CopyPosition(tab_scroll)
	-- trigger scroll bar update (TODO: find a better way)
	self:ScrollCaret()
end

-- Comment the currently selected area
function PANEL:BlockCommentSelection(removecomment)
	if not self:HasSelection() then return end

	local scroll = self:CopyPosition(self.Scroll)

	local new_selection = self:DoAction("BlockCommentSelection", removecomment)
	if not new_selection then return end

	self.Start, self.Caret = self:MakeSelection(new_selection)
	-- restore scroll position
	self.Scroll = scroll
	-- trigger scroll bar update (TODO: find a better way)
	self:ScrollCaret()
end

-- CommentSelection
-- Idea by Jeremydeath
-- Rewritten by Divran to use block comment
function PANEL:CommentSelection(removecomment)
	if not self:HasSelection() then return end

	-- Remember scroll position
	local scroll = self:CopyPosition(self.Scroll)

	-- Normalize selection, so it spans whole lines
	local sel_start, sel_caret = self:MakeSelection(self:Selection())
	sel_start[2] = 1

	if sel_caret[2] ~= 1 then
		sel_caret[1] = sel_caret[1] + 1
		sel_caret[2] = 1
	end

	-- Remember selection
	self.Caret = self:CopyPosition(sel_caret)
	self.Start = self:CopyPosition(sel_start)
	-- (temporarily) adjust selection, so there is no empty line at its end.
	if self.Caret[2] == 1 then
		self.Caret = self:MovePosition(self.Caret, -1)
	end
	local new_selection = self:DoAction("CommentSelection", removecomment)
	if not new_selection then return end

	self.Start, self.Caret = self:MakeSelection(new_selection)

	-- restore scroll position
	self.Scroll = scroll
	-- trigger scroll bar update (TODO: find a better way)
	self:ScrollCaret()
end

function PANEL:ContextHelp()
	local word
	if self:HasSelection() then
		word = self:GetSelection()
	else
		local row, col = unpack(self.Caret)
		local line = self.Rows[row]
		if not line:sub(col, col):match("^[a-zA-Z0-9_]$") then
			col = col - 1
		end
		if not line:sub(col, col):match("^[a-zA-Z0-9_]$") then
			surface_PlaySound("buttons/button19.wav")
			return
		end

		-- TODO substitute this for getWordStart, if it fits.
		local startcol = col
		while startcol > 1 and line:sub(startcol-1, startcol-1):match("^[a-zA-Z0-9_]$") do
			startcol = startcol - 1
		end

		-- TODO substitute this for getWordEnd, if it fits.
		local _, endcol = line:find("[^a-zA-Z0-9_]", col)
		endcol = (endcol or 0) - 1

		word = line:sub(startcol, endcol)
	end

	self:DoAction("ShowContextHelp", word)
end

function PANEL:Copy()
	if not self:HasSelection() then return end
	self.clipboard = string_gsub(self:GetSelection(), "\n", "\r\n")
	return SetClipboardText(self.clipboard)
end

function PANEL:Cut()
	self:Copy()
	return self:SetSelection("")
end

-- TODO these two functions have no place in here
function PANEL:PreviousTab()
	local parent = self:GetParent()

	local currentTab = parent:GetActiveTabIndex() - 1
	if currentTab < 1 then currentTab = currentTab + parent:GetNumTabs() end

	parent:SetActiveTabIndex(currentTab)
end

function PANEL:NextTab()
	local parent = self:GetParent()

	local currentTab = parent:GetActiveTabIndex() + 1
	local numTabs = parent:GetNumTabs()
	if currentTab > numTabs then currentTab = currentTab - numTabs end

	parent:SetActiveTabIndex(currentTab)
end

function PANEL:DuplicateLine()
	-- Save current selection
	local old_start = self:CopyPosition(self.Start)
	local old_end = self:CopyPosition(self.Caret)
	local old_scroll = self:CopyPosition(self.Scroll)

	local str = self:GetSelection()
	if str ~= "" then -- If you have a selection
		self:SetSelection(str:rep(2)) -- Repeat it
	else -- If you don't
		-- Select the current line
		self.Start = { self.Start[1], 1 }
		self.Caret = { self.Start[1], #self.Rows[self.Start[1]] + 1 }
		-- Get the text
		local str = self:GetSelection()
		-- Repeat it
		self:SetSelection(str .. "\n" .. str)
	end

	-- Restore selection
	self.Caret = old_end
	self.Start = old_start
	self.Scroll = old_scroll
	self:ScrollCaret()
end

function PANEL:_OnKeyCodeTyped(code)
	local handled = true
	self.Blink = RealTime()

	local alt = input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
	if alt then return end

	local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
	local control = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)

	-- allow ctrl-ins and shift-del (shift-ins, like ctrl-v, is handled by vgui)
	if not shift and control and code == KEY_INSERT then
		shift, control, code = true, false, KEY_C
	elseif shift and not control and code == KEY_DELETE then
		shift, control, code = false, true, KEY_X
	end

	if control then
		if code == KEY_A then
			self:SelectAll()
		elseif code == KEY_Z then
			self:DoUndo()
		elseif code == KEY_Y then
			self:DoRedo()
		elseif code == KEY_X then
			self:Cut()
		elseif code == KEY_C then
			self:Copy()
			-- pasting is now handled by the textbox that is used to capture input
			--[[
		elseif code == KEY_V then
			if self.clipboard then
				self:SetSelection(self.clipboard)
			end
			]]
		elseif code == KEY_F then
			self:OpenFindWindow("find")
		elseif code == KEY_H then
			self:OpenFindWindow("find and replace")
		elseif code == KEY_G then
			self:OpenFindWindow("go to line")
		elseif code == KEY_K then
			self:CommentSelection(shift)
		elseif code == KEY_Q then
			self:GetParent():Close()
		elseif code == KEY_T then
			self:GetParent():NewTab()
		elseif code == KEY_W then
			self:GetParent():CloseTab()
		elseif code == KEY_PAGEUP then
			self:PreviousTab()
		elseif code == KEY_PAGEDOWN then
			self:NextTab()
		elseif code == KEY_UP then
			self.Scroll[1] = self.Scroll[1] - 1
			if self.Scroll[1] < 1 then self.Scroll[1] = 1 end
		elseif code == KEY_DOWN then
			self.Scroll[1] = self.Scroll[1] + 1
		elseif code == KEY_LEFT then
			self:SetCaret(self:wordLeft(self.Caret))
		elseif code == KEY_RIGHT then
			self:SetCaret(self:wordRight(self.Caret))
			--[[ -- old code that scrolls on ctrl-left/right:
		elseif code == KEY_LEFT then
			self.Scroll[2] = self.Scroll[2] - 1
			if self.Scroll[2] < 1 then self.Scroll[2] = 1 end
		elseif code == KEY_RIGHT then
			self.Scroll[2] = self.Scroll[2] + 1
			]]
		elseif code == KEY_HOME then
			self:SetCaret({ 1, 1 })
		elseif code == KEY_END then
			self:SetCaret({ #self.Rows, 1 })
		elseif code == KEY_D then
			self:DuplicateLine()
		else
			handled = false
		end

	else

		if code == KEY_ENTER then
			local row = self.Rows[self.Caret[1]]:sub(1, self.Caret[2]-1)
			local diff = (row:find("%S") or (row:len() + 1))-1
			local tabs = string_rep("    ", math_floor(diff / 4))
			self:SetSelection("\n" .. tabs)
		elseif code == KEY_UP then
			self.Caret[1] = self.Caret[1] - 1
			while self.HiddenRows[self.Caret[1]] do
				self.Caret[1] = self.Caret[1] - 1
			end
			self:SetCaret(self.Caret)
		elseif code == KEY_DOWN then
			self.Caret[1] = self.Caret[1] + 1
			while self.HiddenRows[self.Caret[1]] do
				self.Caret[1] = self.Caret[1] + 1
			end
			self:SetCaret(self.Caret)
		elseif code == KEY_LEFT then
			if self:HasSelection() and not shift then
				self:SetCaret(self.Caret, false)
			else
				self:SetCaret(self:MovePosition(self.Caret, -1))
			end
		elseif code == KEY_RIGHT then
			if self:HasSelection() and not shift then
				self:SetCaret(self.Caret, false)
			else
				self:SetCaret(self:MovePosition(self.Caret, 1))
			end
		elseif code == KEY_PAGEUP then
			self.Caret[1] = self.Caret[1] - math_ceil(self.Size[1] / 2)
			self.Scroll[1] = self.Scroll[1] - math_ceil(self.Size[1] / 2)
			self:SetCaret(self.Caret)
		elseif code == KEY_PAGEDOWN then
			self.Caret[1] = self.Caret[1] + math_ceil(self.Size[1] / 2)
			self.Scroll[1] = self.Scroll[1] + math_ceil(self.Size[1] / 2)
			self:SetCaret(self.Caret)
		elseif code == KEY_HOME then
			local row = self.Rows[self.Caret[1]]
			local first_char = row:find("%S") or row:len() + 1
			if self.Caret[2] == first_char then
				self.Caret[2] = 1
			else
				self.Caret[2] = first_char
			end
			self:SetCaret(self.Caret)
		elseif code == KEY_END then
			local length = #(self.Rows[self.Caret[1]])
			self.Caret[2] = length + 1
			self:SetCaret(self.Caret)
		elseif code == KEY_BACKSPACE then
			if self:HasSelection() then
				self:SetSelection()
			else
				local buffer = self:GetArea({ self.Caret, { self.Caret[1], 1 } })
				local delta = -1
				if self.Caret[2] % 4 == 1 and #(buffer) > 0 and string_rep(" ", #(buffer)) == buffer then
					delta = -4
				end
				self:SetCaret(self:SetArea({ self.Caret, self:MovePosition(self.Caret, delta) }))
			end
		elseif code == KEY_DELETE then
			if self:HasSelection() then
				self:SetSelection()
			else
				local buffer = self:GetArea({ { self.Caret[1], self.Caret[2] + 4 }, { self.Caret[1], 1 } })
				local delta = 1
				if self.Caret[2] % 4 == 1 and string_rep(" ", #(buffer)) == buffer and #(self.Rows[self.Caret[1]]) >= self.Caret[2] + 4 - 1 then
					delta = 4
				end
				self:SetCaret(self:SetArea({ self.Caret, self:MovePosition(self.Caret, delta) }))
			end
		elseif code == KEY_F1 then
			self:ContextHelp()
		else
			handled = false
		end
	end

	if code == KEY_TAB or (control and (code == KEY_I or code == KEY_O)) then
		if code == KEY_O then shift = not shift end
		if code == KEY_TAB and control then shift = not shift end
		if self:HasSelection() then
			self:Indent(shift)
		else
			-- TAB without a selection --
			if shift then
				local newpos = self.Caret[2]-4
				if newpos < 1 then newpos = 1 end
				self.Start = { self.Caret[1], newpos }
				if self:GetSelection():find("%S") then
					-- TODO: what to do if shift-tab is pressed within text?
					self.Start = self:CopyPosition(self.Caret)
				else
					self:SetSelection("")
				end
			else
				local count = (self.Caret[2] + 2) % 4 + 1
				self:SetSelection(string_rep(" ", count))
			end
		end
		-- signal that we want our focus back after (since TAB normally switches focus)
		if code == KEY_TAB then self.TabFocus = true end
		handled = true
	end

	if control and not handled then
		handled = self:OnShortcut(code)
	end
	SF.Editor.editor:Validate(false)


	return handled
end


-- helpers for ctrl-left/right
function PANEL:wordLeft(caret)
	local row = self.Rows[caret[1]]
	if caret[2] == 1 then
		if caret[1] == 1 then return caret end
		caret = { caret[1]-1, #self.Rows[caret[1]-1] }
		row = self.Rows[caret[1]]
	end
	local pos = row:sub(1, caret[2]-1):match("[^%w@]()[%w@]+[^%w@]*$")
	caret[2] = pos or 1
	return caret
end

function PANEL:wordRight(caret)
	local row = self.Rows[caret[1]]
	if caret[2] > #row then
		if caret[1] == #self.Rows then return caret end
		caret = { caret[1] + 1, 1 }
		row = self.Rows[caret[1]]
		if row:sub(1, 1) ~= " " then return caret end
	end
	local pos = row:match("[^%w@]()[%w@]", caret[2])
	caret[2] = pos or (#row + 1)
	return caret
end

function PANEL:GetTokenAtPosition(caret)
	local column = caret[2]
	local line = self.PaintRows[caret[1]]
	if line then
		local startindex = 1
		for index, data in pairs(line) do
			startindex = startindex + #data[1]
			if startindex >= column then return data[3] end
		end
	end
end

-- Syntax highlighting --------------------------------------------------------

function PANEL:ResetTokenizer(row)
	self.line = self.Rows[row]
	self.position = 0
	self.character = ""
	self.tokendata = ""

	self:DoAction("ResetTokenizer", row)
end

function PANEL:NextCharacter()
	if not self.character then return end

	self.tokendata = self.tokendata .. self.character
	self.position = self.position + 1

	if self.position <= self.line:len() then
		self.character = self.line:sub(self.position, self.position)
	else
		self.character = nil
	end
end

function PANEL:SkipPattern(pattern)
	-- TODO: share code with NextPattern
	if not self.character then return nil end
	local startpos, endpos, text = self.line:find(pattern, self.position)

	if startpos ~= self.position then return nil end
	local buf = self.line:sub(startpos, endpos)
	if not text then text = buf end

	--self.tokendata = self.tokendata .. text

	self.position = endpos + 1
	if self.position <= #self.line then
		self.character = self.line:sub(self.position, self.position)
	else
		self.character = nil
	end
	return text
end

function PANEL:IsVarLine()
	local line = self.Rows[self.Caret[1]]
	local word = line:match("^@(%w+)")
	return (word == "inputs" or word == "outputs" or word == "persist")
end

function PANEL:IsDirectiveLine()
	local line = self.Rows[self.Caret[1]]
	return line:match("^@") ~= nil
end

function PANEL:getWordStart(caret, getword)
	local line = self.Rows[caret[1]]

	for startpos, endpos in line:gmatch("()[a-zA-Z0-9_]+()") do -- "()%w+()"
		if startpos <= caret[2] and endpos >= caret[2] then
			return { caret[1], startpos }, getword and line:sub(startpos, endpos-1) or nil
		end
	end
	return { caret[1], 1 }
end

function PANEL:getWordEnd(caret, getword)
	local line = self.Rows[caret[1]]

	for startpos, endpos in line:gmatch("()[a-zA-Z0-9_]+()") do -- "()%w+()"
		if startpos <= caret[2] and endpos >= caret[2] then
			return { caret[1], endpos }, getword and line:sub(startpos, endpos-1) or nil
		end
	end
	return { caret[1], #line + 1 }
end

function PANEL:NextPattern(pattern)
	if not self.character then return false end
	local startpos, endpos, text = self.line:find(pattern, self.position)

	if startpos ~= self.position then return false end
	local buf = self.line:sub(startpos, endpos)
	if not text then text = buf end

	self.tokendata = self.tokendata .. text

	self.position = endpos + 1
	if self.position <= #self.line then
		self.character = self.line:sub(self.position, self.position)
	else
		self.character = nil
	end
	return true
end

function PANEL:GetSyntaxColor(name)
	return self:DoAction("GetSyntaxColor", name)
end

function PANEL:SyntaxColorLine(line, prev)
	prev = prev or {}
	if #self.Rows[line] > 2048 then -- Too long to parse
		local cols = TabHandler.Modes.Text.SyntaxColorLine(self, line, prev)
		for k,v in pairs(prev) do -- Pass along unfinished etc
			if isnumber(k) then continue end
			cols[k] = v
		end
		return cols
	end
	return self:DoAction("SyntaxColorLine", line, prev)
end

function PANEL:Think()
	self:DoAction("Think")
end
-- register editor panel
vgui.Register(TabHandler.ControlName, PANEL, "Panel");
return TabHandler