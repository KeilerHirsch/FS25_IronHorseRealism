--
-- IronHorseHud
--
-- ONE unified HUD. Modules do not render on their own; they push lines/warnings
-- into the frame buffer during onDraw and the HUD renders them together in one
-- consistent block. This is what replaces the three separate HUDs of the mods
-- IronHorse Realism supersedes.
--

IronHorseHud = {}

IronHorseHud.lines = {}
IronHorseHud.POS_X = 0.013
IronHorseHud.POS_Y = 0.30
IronHorseHud.LINE_H = 0.022
IronHorseHud.TEXT_SIZE = 0.016

---Start a new HUD frame (clears the buffer).
function IronHorseHud.beginFrame()
    IronHorseHud.lines = {}
end

---Push a normal line.
-- @param string text
function IronHorseHud.addLine(text)
    IronHorseHud.lines[#IronHorseHud.lines + 1] = { text = text, warn = false }
end

---Push a warning line (rendered highlighted).
-- @param string text
function IronHorseHud.addWarning(text)
    IronHorseHud.lines[#IronHorseHud.lines + 1] = { text = text, warn = true }
end

---Render the accumulated lines. Client-side only (guarded by the engine's draw
-- loop). Uses renderText, no textures needed for the foundation.
function IronHorseHud.endFrame()
    if #IronHorseHud.lines == 0 or setTextColor == nil or renderText == nil then
        return
    end
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    local y = IronHorseHud.POS_Y
    for i = #IronHorseHud.lines, 1, -1 do
        local line = IronHorseHud.lines[i]
        if line.warn then
            setTextColor(1, 0.35, 0.2, 1)
        else
            setTextColor(1, 1, 1, 1)
        end
        renderText(IronHorseHud.POS_X, y, IronHorseHud.TEXT_SIZE, line.text)
        y = y + IronHorseHud.LINE_H
    end
    setTextColor(1, 1, 1, 1)
end
