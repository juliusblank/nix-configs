{ config, ... }:

{
  # AeroSpace tiling WM config — installed as Homebrew cask in each host's
  # configuration.nix; this module manages ~/.aerospace.toml only.
  #
  # Layout: 6 workspaces (1=term+code, 2=web, 3=comms, 4=docs+tickets, 5=music, 6=flex).
  # Mod key: cmd+ctrl. Default layout: tiles. Cycling: macOS native (cmd+tab, cmd+`).
  #
  # Monitor pinning when docked (workspace-to-monitor-force-assignment):
  #   main (4K external):  workspaces 1, 2, 4 — primary work surface
  #   secondary (laptop):  workspaces 3, 5, 6 — comms, music, flex
  # When undocked, all workspaces collapse to the laptop screen.
  home.file."${config.home.homeDirectory}/.aerospace.toml".text = ''
    after-login-command = []
    after-startup-command = []

    start-at-login = true

    # Layout
    default-root-container-layout = 'tiles'
    default-root-container-orientation = 'auto'
    accordion-padding = 30

    # Don't quit AeroSpace when the last window of the last workspace closes
    on-focused-monitor-changed = ['move-mouse monitor-lazy-center']

    # Pin workspaces to monitors when both are connected. The first matching
    # monitor regex wins; if none match (e.g. undocked), the workspace falls
    # back to the active monitor.
    #
    # TODO: replace 'main' / 'secondary' below with the actual monitor names
    # once both setups are connected. Run `aerospace list-monitors` to discover
    # the exact names (e.g. 'LG HDR 4K', 'Built-in Retina Display') and update.
    # Until then this assigns by AeroSpace's positional aliases — works but
    # depends on display arrangement in System Settings.
    [workspace-to-monitor-force-assignment]
    1 = 'main'
    2 = 'main'
    4 = 'main'
    3 = 'secondary'
    5 = 'secondary'
    6 = 'secondary'

    # --- Auto-assign apps to workspaces ---

    # Workspace 1: term + code
    [[on-window-detected]]
    if.app-id = 'com.mitchellh.ghostty'
    run = ['move-node-to-workspace 1']

    [[on-window-detected]]
    if.app-id = 'com.microsoft.VSCode'
    run = ['move-node-to-workspace 1']

    [[on-window-detected]]
    if.app-id = 'com.todesktop.230313mzl4w4u92'  # Cursor
    run = ['move-node-to-workspace 1']

    # Workspace 2: web
    [[on-window-detected]]
    if.app-id = 'org.mozilla.firefox'
    run = ['move-node-to-workspace 2']

    [[on-window-detected]]
    if.app-id = 'company.thebrowser.Browser'  # Arc
    run = ['move-node-to-workspace 2']

    # Workspace 3: comms
    [[on-window-detected]]
    if.app-id = 'com.tinyspeck.slackmacgap'
    run = ['move-node-to-workspace 3']

    [[on-window-detected]]
    if.app-id = 'com.apple.mail'
    run = ['move-node-to-workspace 3']

    [[on-window-detected]]
    if.app-id = 'ru.keepcoder.Telegram'
    run = ['move-node-to-workspace 3']

    # Workspace 4: docs + tickets
    [[on-window-detected]]
    if.app-id = 'notion.id'
    run = ['move-node-to-workspace 4']

    [[on-window-detected]]
    if.app-id = 'com.linear'
    run = ['move-node-to-workspace 4']

    [[on-window-detected]]
    if.app-id = 'md.obsidian'
    run = ['move-node-to-workspace 4']

    # Workspace 5: music
    [[on-window-detected]]
    if.app-id = 'com.spotify.client'
    run = ['move-node-to-workspace 5']

    # Float utility apps that don't tile well
    [[on-window-detected]]
    if.app-id = 'com.apple.systempreferences'
    run = ['layout floating']

    [[on-window-detected]]
    if.app-id = 'com.apple.SystemPreferences'
    run = ['layout floating']

    [[on-window-detected]]
    if.app-id = 'com.1password.1password'
    run = ['layout floating']

    [[on-window-detected]]
    if.app-id = 'com.apple.finder'
    run = ['layout floating']

    # --- Keybindings (mod = cmd+ctrl) ---
    [mode.main.binding]

    # Focus
    cmd-ctrl-h = 'focus left'
    cmd-ctrl-j = 'focus down'
    cmd-ctrl-k = 'focus up'
    cmd-ctrl-l = 'focus right'

    # Move window
    cmd-ctrl-shift-h = 'move left'
    cmd-ctrl-shift-j = 'move down'
    cmd-ctrl-shift-k = 'move up'
    cmd-ctrl-shift-l = 'move right'

    # Switch workspace
    cmd-ctrl-1 = 'workspace 1'
    cmd-ctrl-2 = 'workspace 2'
    cmd-ctrl-3 = 'workspace 3'
    cmd-ctrl-4 = 'workspace 4'
    cmd-ctrl-5 = 'workspace 5'
    cmd-ctrl-6 = 'workspace 6'

    # Move focused window to workspace
    cmd-ctrl-shift-1 = 'move-node-to-workspace 1'
    cmd-ctrl-shift-2 = 'move-node-to-workspace 2'
    cmd-ctrl-shift-3 = 'move-node-to-workspace 3'
    cmd-ctrl-shift-4 = 'move-node-to-workspace 4'
    cmd-ctrl-shift-5 = 'move-node-to-workspace 5'
    cmd-ctrl-shift-6 = 'move-node-to-workspace 6'

    # Workspace cycling (back-and-forth)
    cmd-ctrl-tab = 'workspace-back-and-forth'

    # Resize
    cmd-ctrl-minus = 'resize smart -50'
    cmd-ctrl-equal = 'resize smart +50'

    # Toggle layouts
    cmd-ctrl-slash = 'layout tiles horizontal vertical'
    cmd-ctrl-comma = 'layout accordion horizontal vertical'

    # Toggle floating / tiling for focused window
    cmd-ctrl-f = 'layout floating tiling'

    # Reload config
    cmd-ctrl-r = 'reload-config'

    # Service mode (for less common commands; press cmd-ctrl-; to enter, esc to exit)
    cmd-ctrl-semicolon = 'mode service'

    [mode.service.binding]
    esc = ['reload-config', 'mode main']
    r = ['flatten-workspace-tree', 'mode main']  # reset workspace tree
    f = ['layout floating tiling', 'mode main']  # toggle layout
    backspace = ['close-all-windows-but-current', 'mode main']
  '';
}
