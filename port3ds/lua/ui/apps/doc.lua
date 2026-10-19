-- Document / mail / diary reader (bottom screen, drag to scroll). Texts come from SystemText,
-- where the game keeps the bodies of its mails, diaries and text files.
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_desktop_text" }
local scroll = {}
local function lang() return Settings.CurrentLanguage.Value end
local function st(id)
  local ok, s = pcall(NgoEx.SystemTextFromTypeString, id, lang())   -- unknown ids raise in the game code
  if ok and type(s) == "string" and s ~= "" and s ~= id then return s end
end

-- window -> {title text id or literal, body text id(s)}
local DOCS = {
  YachinMail = { "window_mail", { "Event_Aim_Rent_Mail001" } },
  Mail = { "window_mail", { "Event_Aim_Rent_Mail001" } },
  Event_Diary001 = { "Shortcut_nikki", { "Event_Diary001" } },
  Event_Diary002 = { "Shortcut_nikki", { "Event_Diary002" } },
  Event_Diary003 = { "Shortcut_nikki", { "Event_Diary003" } },
  Event_Diary004 = { "Shortcut_nikki", { "Event_Diary004" } },
  PsycheNikki1 = { "Shortcut_nikki", { "Event_Psyche_Nikki_1" } },
  PsycheNikki2 = { "Shortcut_nikki", { "Event_Psyche_Nikki_2" } },
  PsycheNikki3 = { "Shortcut_nikki", { "Event_Psyche_Nikki_3" } },
  PsycheNikki4 = { "Shortcut_nikki", { "Event_Psyche_Nikki_4" } },
  FirstDiary = { "Shortcut_nikki", { "FirstDiary" } },
  MyDocument = { "System_secret", { "System_secret_Contents" } },
  TextEditor = { "System_secret", { "System_secret_Contents" } },
  HintTextAfterEnding = { "Start_Menu_Mydocument", { "NetShutHint" } },
}

local function yakujo_text()
  local parts = {}
  for drug = 0, 4 do
    local base = 6 + drug * 5
    parts[#parts + 1] = "■ " .. (st("yakujo_" .. base) or "")
    for k = 1, 4 do
      parts[#parts + 1] = (st("yakujo_" .. (k + 1)) or "") .. ": " .. (st("yakujo_" .. (base + k)) or "")
    end
    parts[#parts + 1] = ""
  end
  return table.concat(parts, "\n")
end

local function content(win)
  -- windows answer unknown fields with NULL (for the game's scripts): read our own fields raw
  local text = rawget(win, "text")
  if text then return rawget(win, "title") or win.app, text end
  if win.app == "Yakujo" then return "Prospecto", yakujo_text() end
  local d = DOCS[win.app]
  if d then
    local body = {}
    for _, id in ipairs(d[2]) do body[#body + 1] = st(id) or "" end
    return st(d[1]) or win.app, table.concat(body, "\n\n")
  end
  return st(win.app) or win.app, st(win.app .. "_Body") or ""
end

function M.draw(win, x0, y0, w0, h0)
  local title, text = content(win)
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, title, "icon_desktop_text")
  if win.closeable and T.close("doc_close") then
    WindowManager:Close(win) return
  end
  G.rect(x, y, w, h, c.white)
  local _, th = G.measure(text, 1, w - 14)
  if scroll.win ~= win then scroll.win, scroll.y = win, 0 end
  local sy = T.scroller(scroll, x, y, w, h, th + 8)
  G.clip(x, y, w, h)
  G.text(text, x + 4, y + 4 - sy, c.ink, 1, w - 14)
  G.unclip()
end

M.DOCS = DOCS
return M
