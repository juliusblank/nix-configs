{ config, ... }:

{
  # AeroSpace tiling WM config — installed as Homebrew cask in each host's
  # configuration.nix; this module manages ~/.aerospace.toml only.
  #
  # Layout: 6 workspaces (1=term+code, 2=web, 3=comms, 4=docs+tickets, 5=music, 6=flex).
  # Mod key: alt. Default layout: tiles. Cycling: macOS native (cmd+tab, cmd+`).
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

    # Pin workspaces to monitors when both are connected. AeroSpace tests each
    # entry in the array in order; the first match wins. If none match (e.g.
    # undocked), the workspace falls back to the active monitor.
    #
    # External monitors host workspaces 1/2/4 (primary work surface):
    #   - DELL U2724DE: office
    #   - DELL P2419HC: travel/secondary dock
    #   - PHL 42M2N8900: home 42" 4K
    # Laptop hosts workspaces 3/5/6 (comms, music, flex).
    [workspace-to-monitor-force-assignment]
    1 = ['DELL U2724DE', 'DELL P2419HC', 'PHL 42M2N8900', 'main']
    2 = ['DELL U2724DE', 'DELL P2419HC', 'PHL 42M2N8900', 'main']
    4 = ['DELL U2724DE', 'DELL P2419HC', 'PHL 42M2N8900', 'main']
    3 = ['Built-in Retina Display', 'secondary']
    5 = ['Built-in Retina Display', 'secondary']
    6 = ['Built-in Retina Display', 'secondary']

    # --- Auto-assign apps to workspaces ---

    # Workspace 1: term + code
    [[on-window-detected]]
    if.app-id = 'com.mitchellh.ghostty'
    run = ['move-node-to-workspace 1']

    [[on-window-detected]]
    if.app-id = 'com.microsoft.VSCode'
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

    # --- Keybindings (mod = alt) ---
    [mode.main.binding]

    # Focus
    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'

    # Move window
    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'

    # Switch workspace
    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'

    # Move focused window to workspace
    alt-shift-1 = 'move-node-to-workspace 1'
    alt-shift-2 = 'move-node-to-workspace 2'
    alt-shift-3 = 'move-node-to-workspace 3'
    alt-shift-4 = 'move-node-to-workspace 4'
    alt-shift-5 = 'move-node-to-workspace 5'
    alt-shift-6 = 'move-node-to-workspace 6'

    # Workspace cycling (back-and-forth)
    alt-tab = 'workspace-back-and-forth'

    # Resize
    alt-minus = 'resize smart -50'
    alt-equal = 'resize smart +50'

    # Toggle floating / tiling for focused window
    alt-f = 'layout floating tiling'

    # Toggle fullscreen for focused window (fills the workspace)
    alt-shift-f = 'fullscreen'

    # Reload config
    alt-r = 'reload-config'
  '';
}
