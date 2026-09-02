-- AutoLang — Phase 0 spike (Hammerspoon)
--
-- Purpose: prove the transliteration + hotkey flow *feels* right before
-- committing to the Swift build. This is throwaway validation, not the product.
--
-- Setup:
--   1. brew install --cask hammerspoon   (not currently installed on this Mac)
--   2. copy this file's contents into ~/.hammerspoon/init.lua
--   3. reload Hammerspoon, grant Accessibility when asked
--   4. type a word, press Ctrl-Opt-H to convert the last word to the other layout
--
-- Limitations vs the Swift app: no menu-bar indicator, no input-source switch,
-- crude "last word" grab via ⌥⌫ selection. Good enough to sanity-check the map.

-- Physical US key -> Hebrew letter (standard Israeli layout).
local EN_TO_HE = {
  q="/", w="'", e="ק", r="ר", t="א", y="ט", u="ו", i="ן", o="ם", p="פ",
  a="ש", s="ד", d="ג", f="כ", g="ע", h="י", j="ח", k="ל", l="ך", [";"]="ף",
  z="ז", x="ס", c="ב", v="ה", b="נ", n="מ", m="צ", [","]="ת", ["."]="ץ", ["/"]=".",
}

-- Invert for HE -> EN.
local HE_TO_EN = {}
for en, he in pairs(EN_TO_HE) do HE_TO_EN[he] = en end

local function looksHebrew(s)
  return s:match("[\216-\219]") ~= nil -- crude: any UTF-8 Hebrew lead byte
end

local function convert(word)
  local map = looksHebrew(word) and HE_TO_EN or EN_TO_HE
  local out = {}
  -- iterate unicode-ish: for HE we walk chars, for EN we walk bytes
  for _, ch in utf8.codes(word) do
    local c = utf8.char(ch)
    out[#out + 1] = map[c] or map[c:lower()] or c
  end
  return table.concat(out)
end

hs.hotkey.bind({"ctrl", "alt"}, "H", function()
  -- select the previous word, read it, replace it
  hs.eventtap.keyStroke({"alt", "shift"}, "left")
  hs.timer.usleep(40000)
  local sel = hs.pasteboard.getContents()
  hs.eventtap.keyStroke({"cmd"}, "c")
  hs.timer.usleep(60000)
  local word = hs.pasteboard.getContents() or ""
  if #word == 0 then return end
  hs.eventtap.keyStrokes(convert(word))
end)

hs.alert.show("AutoLang spike loaded — Ctrl-Opt-H converts the last word")
