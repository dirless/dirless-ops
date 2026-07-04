require "./countries"

class Portal::RegisterPage
  include Lucky::HTMLPage

  needs errors : Hash(String, String)
  needs values : Hash(String, String)

  def render
    html_doctype
    html lang: "en" do
      head do
        title "Create account - Dirless"
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        raw "<style>#{register_css}</style>"
        raw <<-JS
        <script>
          document.addEventListener('DOMContentLoaded', function() {
            var radios = document.querySelectorAll('input[name="plan"]');
            var btn = document.getElementById('submit-btn');
            function update() {
              var val = document.querySelector('input[name="plan"]:checked').value;
              btn.textContent = val === 'free' ? 'Create account' : 'Create account & continue to payment';
              document.querySelectorAll('.plan-card').forEach(function(card) {
                card.classList.remove('plan-card-selected');
              });
              document.querySelector('input[name="plan"]:checked').closest('.plan-card').classList.add('plan-card-selected');
            }
            radios.forEach(function(r) { r.addEventListener('change', update); });
            update();
          });
        </script>
        JS
      end
      body do
        div class: "auth-wrapper" do
          div class: "auth-card" do
            div class: "auth-logo" do
              a href: "/" do
                span "dir", class: "logo-main"
                span "less", class: "logo-accent"
              end
            end
            h1 "Create your account", class: "auth-heading"

            if base_error = @errors["_base"]?
              div class: "alert alert-error" do
                text base_error
              end
            end

            form action: "/register", method: "post", novalidate: "novalidate" do
              div class: "form-row" do
                div class: "form-group" do
                  label "First name", for: "first_name", class: "form-label"
                  input type: "text", id: "first_name", name: "first_name",
                    value: @values["first_name"]? || "",
                    autofocus: "autofocus", autocomplete: "given-name", required: "required",
                    class: "form-input #{"form-input-error" unless @errors["first_name"]?.nil?}",
                    placeholder: "Jane"
                  if err = @errors["first_name"]?
                    span err, class: "field-error"
                  end
                end

                div class: "form-group" do
                  label "Last name", for: "last_name", class: "form-label"
                  input type: "text", id: "last_name", name: "last_name",
                    value: @values["last_name"]? || "",
                    autocomplete: "family-name", required: "required",
                    class: "form-input #{"form-input-error" unless @errors["last_name"]?.nil?}",
                    placeholder: "Smith"
                  if err = @errors["last_name"]?
                    span err, class: "field-error"
                  end
                end
              end

              div class: "form-group" do
                label "Company name", for: "company", class: "form-label"
                input type: "text", id: "company", name: "company",
                  value: @values["company"]? || "",
                  autocomplete: "organization", required: "required",
                  class: "form-input #{"form-input-error" unless @errors["company"]?.nil?}",
                  placeholder: "Acme Inc."
                if err = @errors["company"]?
                  span err, class: "field-error"
                end
              end

              div class: "form-group" do
                label "Email", for: "email", class: "form-label"
                input type: "email", id: "email", name: "email",
                  value: @values["email"]? || "",
                  autocomplete: "email", required: "required",
                  class: "form-input #{"form-input-error" unless @errors["email"]?.nil?}",
                  placeholder: "you@company.com"
                if err = @errors["email"]?
                  span err, class: "field-error"
                end
              end

              div class: "form-group" do
                label "Country", for: "country", class: "form-label"
                selected_country = @values["country"]? || "US"
                tag "select", id: "country", name: "country", required: "required",
                  class: "form-input #{"form-input-error" unless @errors["country"]?.nil?}" do
                  COUNTRIES.each do |code, name|
                    if code == selected_country
                      option name, value: code, selected: "selected"
                    else
                      option name, value: code
                    end
                  end
                end
                if err = @errors["country"]?
                  span err, class: "field-error"
                end
              end

              # Honeypot: invisible to humans, dumb form-bots fill it in.
              # CreateAccount silently drops submissions where it has a value.
              div style: "position:absolute;left:-9999px;top:-9999px;height:0;overflow:hidden;", "aria-hidden": "true" do
                label "Website", for: "website"
                input type: "text", id: "website", name: "website", value: "",
                  autocomplete: "off", tabindex: "-1"
              end

              div class: "form-group" do
                label "Password", for: "password", class: "form-label"
                input type: "password", id: "password", name: "password",
                  autocomplete: "new-password", required: "required", minlength: "12",
                  class: "form-input #{"form-input-error" unless @errors["password"]?.nil?}",
                  placeholder: "At least 12 characters"
                if err = @errors["password"]?
                  span err, class: "field-error"
                end
              end

              div class: "form-group" do
                label "Confirm password", for: "confirm_password", class: "form-label"
                input type: "password", id: "confirm_password", name: "confirm_password",
                  autocomplete: "new-password", required: "required", minlength: "12",
                  class: "form-input #{"form-input-error" unless @errors["confirm_password"]?.nil?}",
                  placeholder: "Repeat your password"
                if err = @errors["confirm_password"]?
                  span err, class: "field-error"
                end
              end

              div class: "form-group" do
                label "Choose your plan", class: "form-label"
                div class: "plan-grid" do
                  selected_plan = @values["plan"]? || "free"
                  [
                    {value: "free", label: "Free", price: "Free", sub: "Up to 10 servers"},
                    {value: "growth", label: "Growth", price: "$10/mo", sub: "Up to 50 servers"},
                    {value: "scale", label: "Scale", price: "$30/mo", sub: "Up to 200 servers"},
                  ].each do |plan|
                    checked = selected_plan == plan[:value]
                    div class: "plan-card #{"plan-card-selected" if checked}" do
                      label class: "plan-label" do
                        if checked
                          input type: "radio", name: "plan", value: plan[:value], class: "plan-radio", checked: "checked"
                        else
                          input type: "radio", name: "plan", value: plan[:value], class: "plan-radio"
                        end
                        div class: "plan-info" do
                          span plan[:label], class: "plan-name"
                          span plan[:price], class: "plan-price"
                          span plan[:sub], class: "plan-sub"
                        end
                      end
                    end
                  end
                end
                para class: "plan-note" do
                  text "* Free plan - up to 10 servers, no credit card required"
                end
              end

              button type: "submit", class: "btn-submit", id: "submit-btn" do
                text "Create account"
              end
            end

            div class: "auth-footer" do
              text "Already have an account? "
              a "Sign in", href: "/login"
            end
          end
        end
      end
    end
  end

  private def register_css : String
    <<-CSS
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg:       #0d1117;
      --surface:  #161b22;
      --surface2: #1c2330;
      --border:   #30363d;
      --accent:   #58a6ff;
      --accent2:  #3fb950;
      --muted:    #8b949e;
      --text:     #e6edf3;
      --text-dim: #c9d1d9;
      --danger:   #f85149;
    }

    html { scroll-behavior: smooth; }

    body {
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 16px;
      line-height: 1.6;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }

    .auth-wrapper {
      width: 100%;
      max-width: 440px;
      padding: 1.5rem;
    }

    .auth-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 2.25rem 2rem;
    }

    .auth-logo {
      text-align: center;
      margin-bottom: 1.5rem;
    }

    .auth-logo a {
      font-size: 1.6rem;
      font-weight: 700;
      letter-spacing: -0.5px;
      color: var(--text);
      text-decoration: none;
    }

    .logo-main { color: var(--text); }
    .logo-accent { color: var(--accent); }

    .auth-heading {
      font-size: 1.1rem;
      font-weight: 700;
      color: var(--text);
      text-align: center;
      margin-bottom: 1.5rem;
    }

    .alert {
      padding: 0.65rem 0.9rem;
      border-radius: 6px;
      font-size: 0.88rem;
      margin-bottom: 1.25rem;
    }

    .alert-error {
      background: rgba(248, 81, 73, 0.12);
      border: 1px solid rgba(248, 81, 73, 0.35);
      color: #ff7b72;
    }

    .form-row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 0 0.75rem;
    }

    .form-group {
      margin-bottom: 1.1rem;
    }

    .form-label {
      display: block;
      font-size: 0.85rem;
      font-weight: 600;
      color: var(--text-dim);
      margin-bottom: 0.35rem;
    }

    .form-input {
      display: block;
      width: 100%;
      background: var(--bg);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.55rem 0.75rem;
      font-size: 0.9rem;
      color: var(--text);
      font-family: inherit;
      transition: border-color 0.15s;
      outline: none;
    }

    .form-input::placeholder {
      color: var(--muted);
    }

    .form-input:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px rgba(88, 166, 255, 0.12);
    }

    .form-input-error {
      border-color: var(--danger) !important;
    }

    .field-error {
      display: block;
      font-size: 0.8rem;
      color: #ff7b72;
      margin-top: 0.3rem;
    }

    .btn-submit {
      display: block;
      width: 100%;
      background: var(--accent);
      color: #0d1117;
      border: none;
      border-radius: 6px;
      padding: 0.65rem 1rem;
      font-size: 0.95rem;
      font-weight: 700;
      cursor: pointer;
      font-family: inherit;
      margin-top: 0.5rem;
      transition: opacity 0.15s;
    }

    .btn-submit:hover {
      opacity: 0.85;
    }

    .auth-footer {
      text-align: center;
      margin-top: 1.25rem;
      font-size: 0.85rem;
      color: var(--muted);
    }

    .plan-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 0.5rem;
      margin-top: 0.35rem;
    }

    .plan-card {
      border: 1px solid var(--border);
      border-radius: 6px;
      background: var(--bg);
      cursor: pointer;
      transition: border-color 0.15s;
    }

    .plan-card:hover {
      border-color: var(--accent);
    }

    .plan-card-selected {
      border-color: var(--accent);
      background: rgba(88, 166, 255, 0.06);
    }

    .plan-label {
      display: flex;
      align-items: flex-start;
      gap: 0.5rem;
      padding: 0.6rem 0.75rem;
      cursor: pointer;
      width: 100%;
    }

    .plan-radio {
      margin-top: 0.2rem;
      accent-color: var(--accent);
      flex-shrink: 0;
    }

    .plan-info {
      display: flex;
      flex-direction: column;
      gap: 0.1rem;
    }

    .plan-name {
      font-size: 0.85rem;
      font-weight: 600;
      color: var(--text);
    }

    .plan-price {
      font-size: 0.9rem;
      font-weight: 700;
      color: var(--accent);
    }

    .plan-sub {
      font-size: 0.75rem;
      color: var(--muted);
    }

    .plan-note {
      font-size: 0.75rem;
      color: var(--muted);
      margin-top: 0.4rem;
    }
    CSS
  end
end
