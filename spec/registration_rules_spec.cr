require "spec"
require "../src/dirless/ops/registration_rules"

private def valid_args
  {email: "alice@example.com", password: "longenoughpass", first_name: "Alice",
   last_name: "Anderson", company: "Acme", country: "US"}
end

private def validate(**overrides)
  args = valid_args.merge(overrides)
  Dirless::Ops::RegistrationRules.validate(
    args[:email], args[:password], args[:first_name],
    args[:last_name], args[:company], args[:country])
end

describe Dirless::Ops::RegistrationRules do
  it "accepts a fully valid registration" do
    validate.should be_empty
  end

  it "requires every field" do
    errors = Dirless::Ops::RegistrationRules.validate("", "", "", "", "", "")
    errors.keys.sort!.should eq ["company", "country", "email", "first_name", "last_name", "password"]
  end

  it "rejects malformed emails" do
    validate(email: "not-an-email").has_key?("email").should be_true
    validate(email: "a@b").has_key?("email").should be_true
    validate(email: "a b@c.com").has_key?("email").should be_true
  end

  it "rejects short passwords with the length in the message" do
    errors = validate(password: "short")
    errors["password"].should contain "12"
  end

  it "rejects blocked disposable domains and their subdomains" do
    validate(email: "bot@web-library.net").has_key?("email").should be_true
    validate(email: "bot@mail.web-library.net").has_key?("email").should be_true
    validate(email: "bot@web-library.net")["email"].should eq "Please use your work email address"
  end

  it "does not block lookalike domains" do
    validate(email: "user@notweb-library.net.example.com").should be_empty
    validate(email: "user@web-library.net.evil.example").should be_empty
  end
end
