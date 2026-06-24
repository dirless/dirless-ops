class Portal::BootstrapResultPage
  include Lucky::HTMLPage

  needs success : Bool
  needs username : String = ""
  needs error_message : String = ""

  def render
    html_doctype
    html lang: "en" do
      head do
        title "SSH Registration - Dirless"
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        raw "<style>#{css}</style>"
      end
      body do
        div class: "wrapper" do
          div class: "card" do
            div class: "logo" do
              span "dir", class: "logo-main"
              span "less", class: "logo-accent"
            end
            if @success
              div class: "icon success-icon" do
                raw "&#10003;"
              end
              h1 "Registration complete", class: "heading"
              para class: "body" do
                text "Your SSH key has been registered for "
                strong @username
                text ". Run the following command to get your certificate:"
              end
              pre class: "code" do
                text "dirless-connect ssh login"
              end
            else
              div class: "icon error-icon" do
                raw "&#10007;"
              end
              h1 "Registration failed", class: "heading"
              para @error_message, class: "body"
              para class: "body hint" do
                text "Run "
                code "dirless-connect ssh register"
                text " to request a new link."
              end
            end
          end
        end
      end
    end
  end

  private def css : String
    <<-CSS
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0d1117; color: #e6edf3; min-height: 100vh;
      display: flex; align-items: center; justify-content: center;
    }
    .wrapper { width: 100%; max-width: 440px; padding: 1.5rem; }
    .card {
      background: #161b22; border: 1px solid #30363d; border-radius: 12px;
      padding: 2.5rem 2rem; text-align: center;
    }
    .logo { font-size: 1.6rem; font-weight: 700; margin-bottom: 1.5rem; }
    .logo-main  { color: #e6edf3; }
    .logo-accent { color: #58a6ff; }
    .icon {
      width: 56px; height: 56px; border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      font-size: 1.6rem; font-weight: 700; margin: 0 auto 1.25rem;
    }
    .success-icon { background: #1a3a2a; color: #3fb950; border: 2px solid #3fb950; }
    .error-icon   { background: #3a1a1a; color: #f85149; border: 2px solid #f85149; }
    .heading { font-size: 1.2rem; font-weight: 600; margin-bottom: 0.75rem; }
    .body { font-size: 0.9rem; color: #8b949e; line-height: 1.6; margin-bottom: 0.75rem; }
    .body strong { color: #e6edf3; }
    .hint { margin-top: 0.5rem; }
    .hint code { background: #21262d; padding: 0.1em 0.35em; border-radius: 4px; font-size: 0.85rem; color: #79c0ff; }
    .code {
      background: #21262d; border: 1px solid #30363d; border-radius: 6px;
      padding: 0.75rem 1rem; font-size: 0.875rem; font-family: monospace;
      color: #79c0ff; margin: 0.5rem 0 1rem; text-align: left;
    }
    CSS
  end
end
