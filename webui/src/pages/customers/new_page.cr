class Customers::NewPage < MainLayout
  needs errors : Hash(String, String)
  needs values : Hash(String, String)

  def content
    div class: "mb-6" do
      a "← Customers", href: "/customers", class: "text-blue-600 hover:underline text-sm"
    end

    h1 "Add Customer", class: "text-2xl font-bold text-gray-900 mb-6"

    div class: "bg-white rounded-lg shadow-sm border border-gray-200 p-6 max-w-lg" do
      form action: "/customers", method: "post" do
        field("Name", "name",
          placeholder: "ewmilnqiuhxu-5000",
          required: true,
          hint: "12 lowercase letters, dash, port (1024–59999)",
          pattern: "[a-z]{12}-[0-9]+")

        field("HMAC Secret", "hmac_secret",
          placeholder: "64-character hex string",
          required: true,
          hint: "Exactly 64 lowercase hex characters (0-9, a-f)",
          pattern: "[0-9a-f]{64}")

        div class: "mb-4 -mt-2 bg-gray-50 border border-gray-200 rounded px-4 py-3" do
          para "Generate one with:", class: "text-xs text-gray-500 mb-1"
          pre class: "text-xs font-mono text-gray-800 select-all" do
            text "openssl rand -hex 32"
          end
        end

        field("Email", "email", placeholder: "admin@example.com", required: true)
        field("Company", "company", placeholder: "Acme Corp")
        field("AWS Account ID", "aws_account_id", placeholder: "123456789012")
        textarea_field("Notes", "notes")

        div class: "mt-6 flex gap-3" do
          button type: "submit",
            class: "bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700" do
            text "Create Customer"
          end
          a "Cancel", href: "/customers",
            class: "text-gray-600 px-4 py-2 rounded text-sm hover:bg-gray-100"
        end
      end
    end
  end

  private def field(label : String, name : String, placeholder : String = "",
                    required : Bool = false, hint : String? = nil, pattern : String? = nil)
    error = errors[name]?
    input_class = "w-full border rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 #{error ? "border-red-400 focus:ring-red-400" : "border-gray-300 focus:ring-blue-500"}"
    div class: "mb-4" do
      label_text = required ? "#{label} *" : label
      label label_text, for: name, class: "block text-sm font-medium text-gray-700 mb-1"

      if required
        input type: "text", id: name, name: name, placeholder: placeholder,
          value: values[name]? || "", required: "required",
          pattern: pattern || "", title: hint || "",
          class: input_class
      else
        input type: "text", id: name, name: name, placeholder: placeholder,
          value: values[name]? || "", class: input_class
      end

      if error
        para error, class: "text-xs text-red-600 mt-1"
      elsif hint
        para hint, class: "text-xs text-gray-400 mt-1"
      end
    end
  end

  private def textarea_field(label : String, name : String)
    div class: "mb-4" do
      label label, for: name, class: "block text-sm font-medium text-gray-700 mb-1"
      textarea id: name, name: name, rows: "3",
        class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" do
        text values[name]? || ""
      end
    end
  end
end
