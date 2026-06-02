require "rails_helper"

module Sendoff
  RSpec.describe "Companies", type: :request do
    include Engine.routes.url_helpers

    describe "GET /companies (index)" do
      it "renders 200 and lists companies with counts" do
        company = create(:company, name: "Acme Widgets", segment: "brand")
        create(:lead, company: company)
        create(:pipeline_entry, company: company, lead: create(:lead, company: company))

        get companies_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Widgets")
        expect(response.body).to include(company.domain)
      end

      it "respects the segment filter" do
        agency = create(:company, :agency, name: "Bright Agency", segment: "agency")
        brand  = create(:company, name: "Brandy Co", segment: "brand")

        get companies_path(segment: "agency")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Bright Agency")
        expect(response.body).not_to include("Brandy Co")
      end

      it "respects the search filter" do
        hit  = create(:company, name: "Findable Inc", segment: "brand")
        miss = create(:company, name: "Hidden Corp", segment: "brand")

        get companies_path(q: "findable")

        expect(response.body).to include("Findable Inc")
        expect(response.body).not_to include("Hidden Corp")
      end
    end

    describe "GET /companies/:id (show)" do
      it "renders 200 with the company and its leads" do
        company = create(:company, name: "Detail Co", segment: "brand")
        lead    = create(:lead, company: company, email: "person@detail.example")

        get company_path(company)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Detail Co")
        expect(response.body).to include(lead.email)
      end
    end
  end
end
