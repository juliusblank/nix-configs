{ pkgs, ... }:

let
  /**
    Vale style `TaktileBlog`: the banned and avoided words of the
    `tktl-eng:tktl-eng-blog-voice` skill (rule 9). Banned words are errors;
    avoided words are warnings with the replacement the skill gives. The
    skill bans only the hype sense, so a warning can be a false hit
    (`agent harness`, `elevated permissions`): keep the word then.
  */
  banned = ''
    extends: existence
    message: "Banned in Taktile blog posts: '%s'."
    level: error
    ignorecase: true
    tokens:
      - revolutionar(?:y|ies)
      - magic(?:al)?
      - game-changing
      - the future is here
  '';

  avoid = ''
    extends: substitution
    message: "Avoid '%[2]s': %[1]s."
    level: warning
    ignorecase: true
    swap:
      'leverag(?:e|es|ed|ing)': use
      'harness(?:es|ed|ing)': use
      'delv(?:e|es|ed|ing)(?: into)?': look at
      'streamlin(?:e|es|ed|ing)': simplify, or say what got shorter
      'unlock(?:s|ed|ing)?': let or enable (unless literal)
      'robust': name the property (retries, idempotent, tested at N rps)
      'seamless(?:ly)?': delete it, or say what does not break
      'cutting-edge': say what is new
      'supercharg(?:e|es|ed|ing)': give the number
      '10x': give the measured number
      'empower(?:s|ed|ing)?': let
      'elevat(?:e|es|ed|ing)': raise (unless literal)
      'foster(?:s|ed|ing)?': build or support
      'revolutioniz(?:e|es|ed|ing)': change, and say how
  '';
in
{
  # Prose writing: Vale style for Taktile blog posts and a Markdown prose mode
  # in Neovim. Used by the `blog` zse layout (roadmap #37, home/modules/zellij.nix).

  # Vale reads this config only when it gets `--config` (the blog draft view and
  # nvim-lint pass it); it does not apply to other repos.
  xdg.configFile = {
    "vale/taktile-blog/.vale.ini".text = ''
      StylesPath = styles
      MinAlertLevel = suggestion

      [*.{md,markdown}]
      BasedOnStyles = TaktileBlog
    '';
    "vale/taktile-blog/styles/TaktileBlog/Banned.yml".text = banned;
    "vale/taktile-blog/styles/TaktileBlog/Avoid.yml".text = avoid;
  };

  programs.neovim = {
    plugins = with pkgs.vimPlugins; [
      zen-mode-nvim
      render-markdown-nvim
      nvim-lint
    ];
    initLua = ''
      -- Prose mode for Markdown: soft wrap at word boundaries, spell check,
      -- rendered headings / code, ZenMode on <leader>z.
      require('zen-mode').setup({ window = { width = 90 } })
      require('render-markdown').setup({})
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'markdown',
        callback = function()
          vim.opt_local.wrap = true
          vim.opt_local.linebreak = true
          vim.opt_local.spell = true
          vim.opt_local.spelllang = 'en_us'
          vim.keymap.set('n', 'j', 'gj', { buffer = true })
          vim.keymap.set('n', 'k', 'gk', { buffer = true })
          vim.keymap.set('n', '<leader>z', '<cmd>ZenMode<cr>', { buffer = true })
        end,
      })

      -- Vale with the TaktileBlog style, only for files in engineering-blog.
      local lint = require('lint')
      lint.linters.vale.cmd = '${pkgs.vale}/bin/vale'
      table.insert(lint.linters.vale.args, 1,
        '--config=' .. vim.fn.expand('~/.config/vale/taktile-blog/.vale.ini'))
      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave' }, {
        pattern = { '*.md', '*.markdown' },
        callback = function(args)
          if vim.api.nvim_buf_get_name(args.buf):find('engineering%-blog') then
            lint.try_lint('vale')
          end
        end,
      })

      -- Claude edits the same files: load changes from disk when the buffer
      -- has no unsaved edits (on focus, on idle and every 2 s).
      vim.opt.autoread = true
      vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold' }, {
        command = 'silent! checktime',
      })
      vim.uv.new_timer():start(2000, 2000, vim.schedule_wrap(function()
        if vim.fn.mode() ~= 'c' then vim.cmd('silent! checktime') end
      end))
    '';
  };
}
