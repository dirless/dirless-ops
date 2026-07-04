class Nodes::NewPage < MainLayout
  def content
    div class: "mb-6" do
      a "← Nodes", href: "/nodes", class: "text-blue-600 hover:underline text-sm"
    end

    h1 "Add Node", class: "text-2xl font-bold text-gray-900 mb-6"

    div class: "bg-white rounded-lg shadow-sm border border-gray-200 p-6 max-w-lg" do
      form action: "/nodes", method: "post" do
        field("Name", "name", placeholder: "node-0", required: true)
        field("IP Address", "ip", placeholder: "203.0.113.10", required: true)
        field("Region", "region", placeholder: "USEAST2", required: true)
        field("Provider", "provider", placeholder: "atlanticnet", value: "atlanticnet")
        field("CPU Cores", "cpu_count", placeholder: "4")
        field("Memory (GB)", "memory_gb", placeholder: "8")

        div class: "mb-4 flex items-center gap-2" do
          input type: "checkbox", id: "is_primary", name: "is_primary", value: "true",
            class: "rounded border-gray-300"
          label "Mark as primary node", for: "is_primary",
            class: "text-sm text-gray-700"
        end

        div class: "mt-6 flex gap-3" do
          button type: "submit",
            class: "bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700" do
            text "Add Node"
          end
          a "Cancel", href: "/nodes",
            class: "text-gray-600 px-4 py-2 rounded text-sm hover:bg-gray-100"
        end
      end
    end
  end

  private def field(label : String, name : String, placeholder : String = "",
                    required : Bool = false, value : String = "")
    div class: "mb-4" do
      label_text = required ? "#{label} *" : label
      label label_text, for: name, class: "block text-sm font-medium text-gray-700 mb-1"
      if required
        input type: "text", id: name, name: name, placeholder: placeholder, value: value, required: "required",
          class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
      else
        input type: "text", id: name, name: name, placeholder: placeholder, value: value,
          class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
      end
    end
  end
end
