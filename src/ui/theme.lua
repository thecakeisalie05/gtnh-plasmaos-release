local themes = {
  dark = {desktop = 0x17212B, surface = 0x263544, raised = 0x30475A, panel = 0x101820,
    titleActive = 0x3B82A0, titleInactive = 0x34414D, foreground = 0xF1F5F9,
    secondary = 0xAAB8C5, accent = 0x55C2E6, selection = 0x286783,
    success = 0x62C370, warning = 0xE9B949, error = 0xE05D5D, border = 0x6B7C8B},
  light = {desktop = 0xBFD7EA, surface = 0xF4F7FA, raised = 0xFFFFFF, panel = 0xDCE6EE,
    titleActive = 0x28789B, titleInactive = 0xA8BAC7, foreground = 0x18232D,
    secondary = 0x526675, accent = 0x147EA8, selection = 0x95CEE4,
    success = 0x277A3B, warning = 0x9A6500, error = 0xB3261E, border = 0x6A7B87},
  highContrast = {desktop = 0x000000, surface = 0x000000, raised = 0x000000, panel = 0x000000,
    titleActive = 0x0000FF, titleInactive = 0x333333, foreground = 0xFFFFFF,
    secondary = 0xFFFFFF, accent = 0xFFFF00, selection = 0x0000FF,
    success = 0x00FF00, warning = 0xFFFF00, error = 0xFF0000, border = 0xFFFFFF},
  lowColor = {desktop = 0x000000, surface = 0x000000, raised = 0x000000, panel = 0x000000,
    titleActive = 0xFFFFFF, titleInactive = 0x000000, foreground = 0xFFFFFF,
    secondary = 0xFFFFFF, accent = 0xFFFFFF, selection = 0xFFFFFF,
    success = 0xFFFFFF, warning = 0xFFFFFF, error = 0xFFFFFF, border = 0xFFFFFF},
}

return {
  get = function(name) return themes[name] or themes.dark end,
  names = function() return {"dark", "light", "highContrast", "lowColor"} end,
}
