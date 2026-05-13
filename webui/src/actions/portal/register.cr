class Portal::Register < Lucky::Action
  accepted_formats [:html]

  get "/register" do
    plan = params.get?(:plan).to_s.strip.downcase
    plan = "beta" unless {"beta", "starter", "growth", "scale"}.includes?(plan)
    html Portal::RegisterPage, errors: {} of String => String, values: {"plan" => plan}
  end
end
