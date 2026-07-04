class Portal::SettingsPage < PortalLayout
  needs cert_ttl_seconds : Int64? = nil
  needs authz_config : Dirless::Ops::WebUI::AuthzConfigResponse? = nil

  def page_title : String
    "Settings"
  end

  def active_nav : String
    "settings"
  end

  def content
    raw "<style>#{settings_css}</style>"

    ttl_seconds = (@cert_ttl_seconds || (8 * 3600_i64)).to_i64
    ttl_hours = ttl_seconds // 3600_i64
    if ttl_hours >= 24_i64 && ttl_hours % 24_i64 == 0_i64
      ttl_value = (ttl_hours // 24_i64).to_s
      ttl_unit = "days"
    else
      ttl_value = ttl_hours.to_s
      ttl_unit = "hours"
    end

    div class: "s-card" do
      div class: "s-card-title" do
        text "SSH Certificate TTL"
      end
      para class: "s-desc" do
        text "How long issued SSH certificates remain valid. Shorter values are more secure; longer values reduce how often users need to run "
        code "dirless-connect ssh login"
        text "."
      end
      form action: "/directory/settings", method: "post", class: "s-row s-settings-form" do
        input type: "number", name: "ttl_value", value: ttl_value,
          min: "1", max: "720", class: "s-ttl-input", required: "required"
        tag "select", name: "ttl_unit", class: "s-ttl-select" do
          if ttl_unit == "hours"
            option "Hours", value: "hours", selected: "selected"
            option "Days", value: "days"
          else
            option "Hours", value: "hours"
            option "Days", value: "days", selected: "selected"
          end
        end
        button "Save", type: "submit", class: "btn btn-primary"
      end
    end

    div class: "s-card" do
      div class: "s-card-title" do
        text "SSH Certificate Access"
      end
      para class: "s-desc" do
        text "Users install "
        code "dirless-connect"
        text " on their laptop to obtain short-lived SSH certificates - no static authorized_keys management required."
      end
      div class: "s-connect-steps" do
        div class: "s-connect-step" do
          strong "1. Install"
          para "Download dirless-connect from "
          a "github.com/dirless/dirless-connect", href: "https://github.com/dirless/dirless-connect", target: "_blank"
          para "and place the binary in your PATH."
        end
        div class: "s-connect-step" do
          strong "2. Register (once)"
          raw "<pre class=\"s-code\">dirless-connect ssh register</pre>"
          para "Sends a magic link to the user's email to verify identity and register their keypair."
        end
        div class: "s-connect-step" do
          strong "3. Get a certificate (per TTL)"
          raw "<pre class=\"s-code\">dirless-connect ssh login</pre>"
          para "Issues a fresh SSH certificate valid for the configured TTL."
        end
        div class: "s-connect-step" do
          strong "4. Connect"
          raw "<pre class=\"s-code\">ssh username@hostname</pre>"
          para "The certificate is picked up automatically by ssh. No key management needed."
        end
      end
    end

    if cfg = @authz_config
      enforce = cfg.enforce_group_memberships
      rules = cfg.host_group_rules

      div class: "s-card" do
        div class: "s-card-title" do
          text "Login Authorization"
        end
        para class: "s-desc" do
          text "When enforcement is on, only users in an authorized group will exist on each host. "
          text "Users not in any authorized group for that host will not resolve via NSS - "
          text "blocking all login methods (SSH, console, SFTP, tunnels). "
          strong "Note: files owned by unauthorized users will show raw UIDs on restricted hosts."
        end
        form action: "/settings/authz-toggle", method: "post", class: "s-row" do
          input type: "hidden", name: "enforce", value: enforce ? "false" : "true"
          if enforce
            button "Disable enforcement", type: "submit", class: "btn btn-secondary"
            span " - enforcement is currently ", class: "s-status-label"
            strong "ON", class: "s-status-on"
          else
            button "Enable enforcement", type: "submit", class: "btn btn-primary"
            span " - enforcement is currently ", class: "s-status-label"
            strong "OFF", class: "s-status-off"
          end
        end
      end

      div class: "s-card" do
        div class: "s-card-title" do
          text "Host Access Rules"
        end
        para class: "s-desc" do
          text "Each rule grants all members of a group login access to a specific host (matched by hostname). "
          text "A host with no matching rules will allow no users when enforcement is on."
        end

        if rules.empty?
          para class: "s-no-rules" do
            text "No rules configured."
          end
        else
          tag "table", class: "s-rules-table" do
            tag "thead" do
              tag "tr" do
                tag "th" do
                  text "Group"
                end
                tag "th" do
                  text "Hostname"
                end
                tag "th" do
                end
              end
            end
            tag "tbody" do
              rules.each_with_index do |rule, i|
                tag "tr" do
                  tag "td", class: "s-rule-cell" do
                    code rule.group
                  end
                  tag "td", class: "s-rule-cell" do
                    code rule.host
                  end
                  tag "td", class: "s-rule-actions" do
                    form action: "/settings/authz-rule-remove", method: "post" do
                      input type: "hidden", name: "rule_index", value: i.to_s
                      button "Remove", type: "submit", class: "btn btn-danger-sm"
                    end
                  end
                end
              end
            end
          end
        end

        tag "hr", class: "s-divider"

        para class: "s-desc" do
          strong "Add rule"
        end
        form action: "/settings/authz-rule-add", method: "post", class: "s-add-rule-form" do
          input type: "text", name: "group", placeholder: "Group name",
            class: "s-rule-input", required: "required"
          input type: "text", name: "host", placeholder: "Hostname (e.g. web-01)",
            class: "s-rule-input", required: "required"
          button "Add", type: "submit", class: "btn btn-primary"
        end
      end
    end
  end

  private def settings_css : String
    <<-CSS
    .s-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 1.5rem;
      margin-bottom: 1.5rem;
    }
    .s-card-title {
      font-size: 0.78rem;
      font-weight: 700;
      color: var(--muted);
      margin-bottom: 1rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .s-desc {
      font-size: 0.875rem;
      color: var(--text-dim);
      margin: 0 0 1rem;
      line-height: 1.5;
    }
    .s-row {
      display: flex;
      align-items: center;
      gap: 0.75rem;
    }
    .s-settings-form { gap: 0.5rem; }
    .s-ttl-input {
      width: 5rem;
      padding: 0.4rem 0.6rem;
      border-radius: 6px;
      border: 1px solid var(--border);
      background: var(--surface2);
      color: var(--text);
      font-size: 0.875rem;
      font-family: inherit;
    }
    .s-ttl-select {
      padding: 0.4rem 0.6rem;
      border-radius: 6px;
      border: 1px solid var(--border);
      background: var(--surface2);
      color: var(--text);
      font-size: 0.875rem;
      font-family: inherit;
    }
    .s-connect-steps {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
      margin-top: 0.5rem;
    }
    @media (max-width: 640px) { .s-connect-steps { grid-template-columns: 1fr; } }
    .s-connect-step { font-size: 0.875rem; color: var(--text-dim); line-height: 1.5; }
    .s-connect-step strong { display: block; color: var(--text); margin-bottom: 0.25rem; }
    .s-connect-step p { margin: 0.25rem 0 0; }
    .s-code {
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.82rem;
      background: var(--surface2);
      border: 1px solid var(--border);
      border-radius: 4px;
      padding: 0.4rem 0.6rem;
      margin: 0.35rem 0;
      white-space: pre;
      overflow-x: auto;
    }
    .btn {
      padding: 0.45rem 1rem;
      border-radius: 6px;
      font-size: 0.875rem;
      font-weight: 600;
      cursor: pointer;
      border: none;
      font-family: inherit;
      transition: opacity 0.15s;
    }
    .btn:hover { opacity: 0.85; }
    .btn-primary { background: var(--accent); color: #0d1117; }
    .btn-secondary {
      background: var(--surface2);
      color: var(--text);
      border: 1px solid var(--border);
    }
    .btn-danger-sm {
      padding: 0.2rem 0.6rem;
      font-size: 0.78rem;
      font-weight: 600;
      border-radius: 4px;
      cursor: pointer;
      border: 1px solid var(--border);
      background: transparent;
      color: var(--text-dim);
      font-family: inherit;
      transition: background 0.1s, color 0.1s;
    }
    .btn-danger-sm:hover { background: #b00020; color: #fff; border-color: #b00020; }
    .s-status-label { font-size: 0.875rem; color: var(--text-dim); margin-left: 0.5rem; }
    .s-status-on  { color: var(--accent); font-size: 0.875rem; }
    .s-status-off { color: var(--text-dim); font-size: 0.875rem; }
    .s-no-rules { font-size: 0.875rem; color: var(--text-dim); margin: 0.25rem 0 1rem; }
    .s-rules-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.875rem;
      margin-bottom: 1rem;
    }
    .s-rules-table th {
      text-align: left;
      font-size: 0.72rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: var(--muted);
      padding: 0 0 0.5rem;
      border-bottom: 1px solid var(--border);
    }
    .s-rule-cell { padding: 0.45rem 0.75rem 0.45rem 0; color: var(--text); }
    .s-rule-actions { padding: 0.3rem 0; }
    .s-divider { border: none; border-top: 1px solid var(--border); margin: 1rem 0; }
    .s-add-rule-form { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
    .s-rule-input {
      padding: 0.4rem 0.6rem;
      border-radius: 6px;
      border: 1px solid var(--border);
      background: var(--surface2);
      color: var(--text);
      font-size: 0.875rem;
      font-family: inherit;
      width: 14rem;
    }
    CSS
  end
end
