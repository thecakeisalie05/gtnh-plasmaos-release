local themes = {
  dark = {desktop = 0x0B1017, surface = 0x18232E, raised = 0x2A3A48, panel = 0x070B10,
    titleActive = 0x087F9D, titleInactive = 0x344654, foreground = 0xF4F8FA,
    secondary = 0xA9BAC6, accent = 0x43D1F2, selection = 0x146985,
    success = 0x4FC879, warning = 0xF0B94C, error = 0xE95765, border = 0x6C8596,
    field = 0x101820, shadow = 0x020406, chromeText = 0xFFFFFF},
  light = {desktop = 0xAFC9DC, surface = 0xF4F7FA, raised = 0xDCE7EF, panel = 0x253746,
    titleActive = 0x086F91, titleInactive = 0x6F8798, foreground = 0x14212B,
    secondary = 0x4A6070, accent = 0x087A9F, selection = 0x5BA9C2,
    success = 0x277A3B, warning = 0x9A6500, error = 0xB3261E, border = 0x6A7B87,
    field = 0xE7EEF3, shadow = 0x81919C, chromeText = 0xFFFFFF},
  highContrast = {desktop = 0x000000, surface = 0x000000, raised = 0x000000, panel = 0x000000,
    titleActive = 0x0000FF, titleInactive = 0x333333, foreground = 0xFFFFFF,
    secondary = 0xFFFFFF, accent = 0xFFFF00, selection = 0x0000FF,
    success = 0x00FF00, warning = 0xFFFF00, error = 0xFF0000, border = 0xFFFFFF,
    field = 0x000000, shadow = 0x000000, chromeText = 0xFFFFFF},
  lowColor = {desktop = 0x000000, surface = 0x000000, raised = 0x000000, panel = 0x000000,
    titleActive = 0xFFFFFF, titleInactive = 0x000000, foreground = 0xFFFFFF,
    secondary = 0xFFFFFF, accent = 0xFFFFFF, selection = 0xFFFFFF,
    success = 0xFFFFFF, warning = 0xFFFFFF, error = 0xFFFFFF, border = 0xFFFFFF,
    field = 0x000000, shadow = 0x000000, chromeText = 0x000000},
}

return {
  get = function(name) return themes[name] or themes.dark end,
  names = function() return {"dark", "light", "highContrast", "lowColor"} end,
}
