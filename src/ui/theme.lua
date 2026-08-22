local themes = {
  dark = {desktop = 0x101822, surface = 0x1B2733, raised = 0x263746, panel = 0x0A1118,
    titleActive = 0x167A9E, titleInactive = 0x263746, foreground = 0xF1F7FA,
    secondary = 0x9EB1C0, accent = 0x39BDE5, selection = 0x176783,
    success = 0x51C878, warning = 0xE8B84A, error = 0xED6464, border = 0x496172,
    field = 0x111B24, shadow = 0x05090C, chromeText = 0xFFFFFF},
  light = {desktop = 0xBFD7EA, surface = 0xF4F7FA, raised = 0xFFFFFF, panel = 0xDCE6EE,
    titleActive = 0x28789B, titleInactive = 0xA8BAC7, foreground = 0x18232D,
    secondary = 0x526675, accent = 0x147EA8, selection = 0x95CEE4,
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
