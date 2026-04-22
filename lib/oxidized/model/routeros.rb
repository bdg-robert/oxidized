class RouterOS < Oxidized::Model
  using Refinements

  prompt /\[\w+@\S+(\s+\S+)*\]\s?>\s?$/
  comment '# '

  cmd :all do |cfg|
    cfg.gsub! /\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[m|K]/, '' # strip ANSI colours
    if screenscrape
      cfg = cfg.cut_both
      cfg.gsub! /^\r+(.+)/, '\1'
      cfg.gsub! /([^\r]*)\r+$/, '\1'
    end
    cfg.lines.map { |line| line.rstrip }.join("\n") + "\n"
  end

  cmd '/system resource print' do |cfg|
    comment cfg.keep_lines [
      /(version|factory-software|total-memory|cpu|cpu-count|total-hdd-space|architecture-name|board-name|platform):/
    ]
  end

  cmd '/system routerboard print' do |cfg|
    comment cfg.keep_lines [
      /(firmware-type|current-firmware):/
    ]
  end

  cmd '/system package update print' do |cfg|
    version_line = cfg.each_line.grep(/installed-version:\s|current-version:\s/).first
    if version_line && (m = version_line.match(/(\d+)/))
      @ros_version = m[1].to_i
    end
    comment(version_line.to_s)
  end

  cmd '/system history print without-paging' do |cfg|
    comment cfg
  end

  cmd :significant_changes do |cfg|
    cfg.gsub(/^(#\s+installed-version: [^\n]+\n).*?^(?=# software id)/m, '\1')
  end

  post do
    logger.debug "Running /export for routeros version #{@ros_version || 'unknown'}"
    run_cmd = if vars(:remove_secret)
                '/export hide-sensitive'
              elsif @ros_version && @ros_version >= 7
                '/export show-sensitive'
              else
                '/export'
              end
    cmd run_cmd do |cfg|
      cfg.gsub! /\\\r?\n\s+/, '' # unwrap backslash line continuations
      cfg.reject_lines [
        /^# inactive time\b/,
        /^# received packet from \S+ bad format/,
        /^# poe-out status: short_circuit/,
        /^# Firmware upgraded successfully/,
        /^# \S+ not ready/,
        /^# Interface not running/,
        /^#.+please restart the device in order to apply the new setting/,
        /^#\s\w{3}\/\d{2}\/\d{4}/,   # v6 "by RouterOS" timestamp
        /^#\s\d{4}-\d{2}-\d{2}/      # v7 "by RouterOS" timestamp
      ]
    end
  end

  cfg :telnet do
    username /^Login:/
    password /^Password:/
  end

  cfg :telnet, :ssh do
    pre_logout 'quit'
  end

  cfg :ssh do
    exec true
  end
end
