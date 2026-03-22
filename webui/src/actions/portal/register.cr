class Portal::Register < Lucky::Action
  accepted_formats [:html]

  get "/portal/register" do
    html Portal::RegisterPage, errors: {} of String => String, values: {} of String => String
  end
end
