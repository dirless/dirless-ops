class Portal::SettingsPage < PortalLayout
  needs cert_ttl_seconds : Int64? = nil

  def page_title : String
    "Settings"
  end

  def active_nav : String
    "settings"
  end

  def content
    raw "<style>#{settings_css}</style>"

    ttl_seconds = (@cert_ttl_seconds || (8 * 3600_i64)).to_i64
    ttl_hours   = ttl_seconds // 3600_i64
    if ttl_hours >= 24_i64 && ttl_hours % 24_i64 == 0_i64
      ttl_value = (ttl_hours // 24_i64).to_s
      ttl_unit  = "days"
    else
      ttl_value = ttl_hours.to_s
      ttl_unit  = "hours"
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
            option "Days",  value: "days"
          else
            option "Hours", value: "hours"
            option "Days",  value: "days", selected: "selected"
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
        text " on their laptop to obtain short-lived SSH certificates — no static authorized_keys management required."
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
          strong "3. Get a certificate (daily)"
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
    CSS
  end
end
