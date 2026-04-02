local M = {}

-- ============================================================================
-- OKLab color math utilities (self-contained, no dependencies)
-- ============================================================================

--- Parse "#RRGGBB" hex string to r, g, b floats in 0-1 range.
local function hex_to_rgb(hex)
  local r = tonumber(hex:sub(2, 3), 16) / 255
  local g = tonumber(hex:sub(4, 5), 16) / 255
  local b = tonumber(hex:sub(6, 7), 16) / 255
  return r, g, b
end

--- Convert r, g, b floats (0-1) back to "#RRGGBB" string.
local function rgb_to_hex(r, g, b)
  local function clamp(v)
    return math.max(0, math.min(1, v))
  end
  return string.format("#%02x%02x%02x", math.floor(clamp(r) * 255 + 0.5), math.floor(clamp(g) * 255 + 0.5), math.floor(clamp(b) * 255 + 0.5))
end

--- sRGB gamma transfer: linear -> sRGB component.
local function linear_to_srgb(c)
  if c <= 0.0031308 then
    return 12.92 * c
  end
  return 1.055 * (c ^ (1 / 2.4)) - 0.055
end

--- sRGB gamma transfer: sRGB -> linear component.
local function srgb_to_linear(c)
  if c <= 0.04045 then
    return c / 12.92
  end
  return ((c + 0.055) / 1.055) ^ 2.4
end

--- Convert linear RGB to OKLab (Bjorn Ottosson 2021).
--- Returns L, a, b in OKLab space.
local function rgb_to_oklab(r, g, b)
  local lr = srgb_to_linear(r)
  local lg = srgb_to_linear(g)
  local lb = srgb_to_linear(b)

  -- Linear RGB to LMS
  local l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
  local m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
  local s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

  -- Cube root
  local l_ = l ^ (1 / 3)
  local m_ = m ^ (1 / 3)
  local s_ = s ^ (1 / 3)

  -- LMS' to OKLab
  local L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
  local A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
  local B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

  return L, A, B
end

--- Convert OKLab to sRGB, clamped to 0-1.
--- Returns r, g, b in sRGB 0-1 range.
local function oklab_to_rgb(L, A, B)
  -- OKLab to LMS'
  local l_ = L + 0.3963377774 * A + 0.2158037573 * B
  local m_ = L - 0.1055613458 * A - 0.0638541728 * B
  local s_ = L - 0.0894841775 * A - 1.2914855480 * B

  -- Cube
  local l = l_ * l_ * l_
  local m = m_ * m_ * m_
  local s = s_ * s_ * s_

  -- LMS to linear RGB
  local lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
  local lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
  local lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

  return linear_to_srgb(lr), linear_to_srgb(lg), linear_to_srgb(lb)
end

--- Interpolate two hex colors in OKLab space.
--- t=0 returns hex1, t=1 returns hex2.
local function lerp_oklab(hex1, hex2, t)
  local r1, g1, b1 = hex_to_rgb(hex1)
  local r2, g2, b2 = hex_to_rgb(hex2)

  local L1, a1, b1_ = rgb_to_oklab(r1, g1, b1)
  local L2, a2, b2_ = rgb_to_oklab(r2, g2, b2)

  local L = L1 + (L2 - L1) * t
  local A = a1 + (a2 - a1) * t
  local B = b1_ + (b2_ - b1_) * t

  local r, g, b = oklab_to_rgb(L, A, B)
  return rgb_to_hex(r, g, b)
end

--- Read the Normal highlight group's bg color as a hex string.
--- Falls back to "#1e1e2e" (neutral dark) if Normal has no bg (transparent terminal).
local function get_normal_bg()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if ok and hl and hl.bg then
    return string.format("#%06x", hl.bg)
  end
  return "#1e1e2e"
end

-- ============================================================================
-- Highlight categories:
--   Brand:    hardcoded hex, never change (StoreUA*, StoreWave*)
--   Linked:   { link = "Group" } with default=true, colorscheme can override
--   Derived:  computed from Normal bg via OKLab interpolation, re-computed on
--             ColorScheme change so the plugin harmonizes with any theme
-- ============================================================================

-- Linked highlights: colorschemes can override these
local theme_highlights = {
  StoreTabActive = { link = "FloatBorder" },
  StoreTabInactive = { link = "Comment" },
  StoreSortKey = { link = "StoreTabIcon" },
}

-- Brand highlights: always use exact hex values
local brand_highlights = {
  StoreUABlue = { fg = "#0057b7", bold = true },
  StoreUAYellow = { fg = "#ffd700", bold = true },
  StoreWaveBlue1 = { fg = "#4d7fce", bold = true },
  StoreWaveBlue2 = { fg = "#1a6bc4", bold = true },
  StoreWaveBlue3 = { fg = "#0057b7", bold = true },
  StoreWaveYellow1 = { fg = "#ffe680", bold = true },
  StoreWaveYellow2 = { fg = "#ffd940", bold = true },
  StoreWaveYellow3 = { fg = "#ffd700", bold = true },
}

--- Compute highlights derived from the active colorscheme's Normal bg.
--- Called on every apply() so colors stay in sync with the theme.
local function derive_highlights()
  local bg = get_normal_bg()
  return {
    StoreTabIcon = { fg = lerp_oklab(bg, "#73daca", 0.85), bold = true },
  }
end

local function apply()
  for name, hl in pairs(theme_highlights) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", hl, { default = true }))
  end
  for name, hl in pairs(brand_highlights) do
    vim.api.nvim_set_hl(0, name, hl)
  end
  for name, hl in pairs(derive_highlights()) do
    vim.api.nvim_set_hl(0, name, hl)
  end
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("store_highlights", { clear = true }),
    callback = apply,
  })
end

return M
